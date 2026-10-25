import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:flutter_graphql_codegen/src/schema_downloader.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:flutter_graphql_codegen/src/client_extension_generator.dart';
import 'package:flutter_graphql_codegen/src/operation_analyzer.dart';
import 'package:dart_style/dart_style.dart' show FormatterException;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'code_utils.dart';
import 'config.dart';
import 'config_context.dart';
import 'declarations.dart';
import 'diagnostics.dart';
import 'document_utils.dart';
import 'formatting.dart';
import 'naming.dart';
import 'operation_groups.dart';
import 'type_usage.dart';

/// An operation file and the public top-level names it declares.
class _Declarations {
  final String operation;

  /// Package-relative path of the document defining [operation].
  final String source;
  final Set<String> names;

  _Declarations(this.operation, this.source, this.names);
}

/// Schema-derived data shared by all operations of a build.
class _SchemaArtifacts {
  final DocumentNode schemaDoc;
  final String typesCode;
  final Set<String> definedTypes;

  _SchemaArtifacts(this.schemaDoc, this.typesCode, this.definedTypes);
}

/// Fragments of other packages (`fragment_imports`).
class _ImportedFragments {
  final Map<String, FragmentDefinitionNode> fragments;

  /// Fragment name -> URI of the library declaring it.
  final Map<String, String> libraries;

  /// Names declared by those libraries -> library URI.
  final Map<String, String> declarations;

  const _ImportedFragments(this.fragments, this.libraries, this.declarations);

  static const none = _ImportedFragments({}, {}, {});
}

class GraphQLCodegenBuilder implements Builder {
  final GraphQLCodegenConfig config;

  /// Remote schemas are downloaded once per builder instance (i.e. once per
  /// `build_runner build`; restart `watch` to pick up remote schema changes).
  final Map<String, Future<String>> _remoteSchemas = {};

  String? _cachedSchemaText;

  /// The `prune_types` selection [_cachedArtifacts] was generated for.
  String? _cachedUsedTypes;
  _SchemaArtifacts? _cachedArtifacts;
  String? _parsedSchemaText;
  DocumentNode? _parsedSchema;
  String? _lastWrittenTypes;
  bool _loggedConfigWarnings = false;

  /// Language version generated code is formatted for (that of the package
  /// being built); null means the formatter's latest.
  Version? _languageVersion;
  bool _languageVersionResolved = false;

  /// Directories of other packages by name, for `fragment_imports`; packages
  /// not listed are looked up in `.dart_tool/package_config.json`. Meant for
  /// tests.
  final Map<String, String> packageRoots;

  GraphQLCodegenBuilder(this.config, {this.packageRoots = const {}});

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;

    // Skip non-GraphQL files
    if (!inputId.path.endsWith('.graphql')) {
      return;
    }

    if (!_languageVersionResolved) {
      _languageVersionResolved = true;
      _languageVersion = await _packageLanguageVersion(buildStep);
    }

    if (!_loggedConfigWarnings) {
      _loggedConfigWarnings = true;
      config.warnings.forEach(log.warning);
    }

    final content = await buildStep.readAsString(inputId);
    final DocumentNode document;
    try {
      document = gql_lang.parseString(content, url: inputId.path);
    } catch (e, st) {
      throw _report(CodegenException(
        CodegenErrorCodes.buildOperationParse,
        'Failed to parse ${inputId.path}: $e',
        cause: e,
        stackTrace: st,
      ));
    }

    // Schema files produce nothing; fragment-only files only fragments.dart
    // (with result_types: operation).
    if (document.definitions.any((d) => d is TypeSystemDefinitionNode)) {
      return;
    }
    final operations =
        document.definitions.whereType<OperationDefinitionNode>().toList();
    final operationTypes = CodegenConfigContext.operationResultTypes;
    if (operations.isEmpty &&
        (!operationTypes ||
            !document.definitions.any((d) => d is FragmentDefinitionNode))) {
      return;
    }

    log.fine('Processing GraphQL operations in ${inputId.path}');

    final schemaText = await _loadSchema(buildStep);
    final imported = await _importedFragments(buildStep);
    _importedDeclarations = imported.declarations;

    // With prune_types, types.dart depends on every document: it declares
    // what their operations and fragments use.
    Set<String>? usedTypes;
    if (operationTypes &&
        CodegenConfigContext.pruneTypes &&
        CodegenConfigContext.typesImport == null) {
      usedTypes = await _usedTypes(buildStep, document, schemaText, imported);
    }
    final artifacts = _artifactsFor(schemaText, usedTypes);
    await _writeTypesFile(artifacts.typesCode);

    final Map<String, FragmentDefinitionNode> fragments;
    var fragmentLibraries = const <String, String>{};
    if (operationTypes) {
      // Every document reads all fragments, so fragments.dart and the
      // classes implementing fragment interfaces follow any change.
      final local = await _allFragments(buildStep, document);
      _checkImportedFragmentNames(local, imported);
      fragments = {...imported.fragments, ...local};
      fragmentLibraries = imported.libraries;
      await _writeFragmentsFile(artifacts, fragments, fragmentLibraries);
    } else {
      final local = await _externalFragments(buildStep, document);
      _checkImportedFragmentNames({
        ...local,
        for (final f
            in document.definitions.whereType<FragmentDefinitionNode>())
          f.name.value: f,
      }, imported);
      fragments = {...imported.fragments, ...local};
    }

    // This document's operation files are declared anew below.
    await (_declarationsLoaded ??= _loadDeclarations());
    _declarations.removeWhere((_, d) => d.source == inputId.path);

    // Output file name -> operation that generates it, for this document.
    final outputs = <String, String>{};
    for (final operation in operations) {
      final operationName = operation.name?.value;
      if (operationName == null) {
        log.warning('Skipping anonymous ${operation.type.name} in '
            '${inputId.path}: name the operation to generate code for it.');
        continue;
      }

      final fileName = _generateOutputFileName(operationName);
      final previous = outputs[fileName];
      if (previous != null) {
        throw _report(CodegenException(
          CodegenErrorCodes.buildDuplicateOperation,
          previous == operationName
              ? 'Operation "$operationName" is defined more than once in '
                  '${inputId.path}'
              : 'Operations "$previous" and "$operationName" in '
                  '${inputId.path} both generate $fileName',
        ));
      }
      outputs[fileName] = operationName;
      await _checkOutputOwner(buildStep, fileName, operationName);

      final String code;
      try {
        code = ClientExtensionGenerator.generateOperationFile(
          operationName,
          operation.type.name,
          content,
          artifacts.schemaDoc,
          artifacts.definedTypes,
          fragments: fragments,
          fragmentLibraries: fragmentLibraries,
          sourcePath: inputId.path,
          group: _groupOf(inputId.path),
        );
      } on CodegenException catch (e) {
        throw _report(e);
      }
      await _checkDeclarations(buildStep, fileName, operationName, code);

      await _writeToOutputDirectory(operationName, code);
      log.fine('Generated ${config.outputDir}/$fileName');
    }

    await _writeGroupFiles(buildStep, artifacts);

    // Generate index file after processing operations (if enabled)
    if (config.emitIndex) {
      await _generateIndexFile(inputId.package);
    }
  }

  /// Throws when [fileName] was generated from another document that still
  /// defines an operation writing to the same file.
  Future<void> _checkOutputOwner(
      BuildStep buildStep, String fileName, String operationName) async {
    final file = File(p.join(config.outputDir, fileName));
    if (!await file.exists()) return;
    final source = RegExp(r'^// Source: (.+)$', multiLine: true)
        .firstMatch(await file.readAsString())
        ?.group(1);
    if (source == null || source == buildStep.inputId.path) return;

    final sourceId = AssetId(buildStep.inputId.package, source);
    if (!await buildStep.canRead(sourceId)) return;
    final DocumentNode other;
    try {
      other = gql_lang.parseString(await buildStep.readAsString(sourceId));
    } catch (_) {
      // Parse errors are reported when that document itself is built.
      return;
    }
    final clash = other.definitions
        .whereType<OperationDefinitionNode>()
        .map((op) => op.name?.value)
        .whereType<String>()
        .where((name) => _generateOutputFileName(name) == fileName)
        .firstOrNull;
    if (clash == null) return;

    throw _report(CodegenException(
      CodegenErrorCodes.buildDuplicateOperation,
      clash == operationName
          ? 'Operation "$operationName" is defined in both $source and '
              '${buildStep.inputId.path} (output file $fileName)'
          : 'Operation "$clash" in $source and operation "$operationName" in '
              '${buildStep.inputId.path} both generate $fileName',
    ));
  }

  /// Operation files by output file name, with the names they declare.
  ///
  /// All files are written into one directory and exported together by
  /// index.dart, so a name two of them declare breaks the build (e.g. `A_B_C`
  /// from operation `A_B` field `c` and from operation `A` path `b.c`).
  /// build_runner builds each document in its own step and only tracks the
  /// documents a step reads, so this registry is how one step knows what the
  /// others declared: it is filled from the operation files already on disk
  /// (from earlier builds, once per builder instance) and updated as files
  /// are generated.
  ///
  /// Limits: an entry from disk can be outdated while its document has
  /// changed but not been rebuilt yet in this build. Entries whose
  /// operation is no longer defined in its document are ignored, but one
  /// whose selection changed is compared as it was last generated.
  final Map<String, _Declarations> _declarations = {};
  Future<void>? _declarationsLoaded;

  /// Names declared by the last generated fragments.dart.
  Set<String> _fragmentDeclarations = const {};

  static final _operationHeader =
      RegExp(r'^// Operation: (\w+) ', multiLine: true);
  static final _sourceHeader = RegExp(r'^// Source: (.+)$', multiLine: true);

  Future<void> _loadDeclarations() async {
    final dir = Directory(config.outputDir);
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.g.dart')) continue;
      final text = await entity.readAsString();
      final operation = _operationHeader.firstMatch(text)?.group(1);
      final source = _sourceHeader.firstMatch(text)?.group(1);
      if (operation == null || source == null) continue;
      _declarations.putIfAbsent(
          p.basename(entity.path),
          () => _Declarations(
              operation, source, topLevelDeclarations(text).toSet()));
    }
  }

  /// Registers the names [code] (the file [fileName] of [operationName])
  /// declares and throws when another operation file or fragments.dart
  /// declares one of them too.
  Future<void> _checkDeclarations(BuildStep buildStep, String fileName,
      String operationName, String code) async {
    final source = buildStep.inputId.path;
    final names = topLevelDeclarations(code).toSet();

    // Compared and registered without an await in between, so steps
    // running concurrently see each other.
    final clashes = [
      for (final MapEntry(key: file, value: other) in _declarations.entries)
        if (file != fileName && other.names.intersection(names).isNotEmpty)
          other,
    ];
    _declarations[fileName] = _Declarations(operationName, source, names);

    String list(Set<String> common) {
      final sorted = common.toList()..sort();
      final shown = sorted.take(3).map((n) => '"$n"').join(', ');
      return sorted.length > 3 ? '$shown and ${sorted.length - 3} more' : shown;
    }

    final withFragments = names.intersection(_fragmentDeclarations);
    if (withFragments.isNotEmpty) {
      throw _report(CodegenException(
        CodegenErrorCodes.buildDuplicateDeclaration,
        'Operation "$operationName" in $source declares '
        '${list(withFragments)}, which fragments.dart declares as well; '
        'rename the operation or the fragment',
      ));
    }
    _checkImportedDeclarations('Operation "$operationName" in $source', names);
    for (final other in clashes) {
      if (!await _stillDefined(buildStep, other)) continue;
      final common = names.intersection(other.names);
      final where = other.source == source
          ? 'in $source'
          : 'in ${other.source} and $source';
      throw _report(CodegenException(
        CodegenErrorCodes.buildDuplicateDeclaration,
        'Operations "${other.operation}" and "$operationName" ($where) both '
        'generate ${list(common)}, so index.dart cannot export both; rename '
        'one of the operations (or alias a field so the class names differ)',
      ));
    }
  }

  /// Whether the document of [d] still defines its operation.
  Future<bool> _stillDefined(BuildStep buildStep, _Declarations d) async {
    final id = AssetId(buildStep.inputId.package, d.source);
    if (!await buildStep.canRead(id)) return false;
    try {
      final doc = gql_lang.parseString(await buildStep.readAsString(id));
      return doc.definitions
          .whereType<OperationDefinitionNode>()
          .any((op) => op.name?.value == d.operation);
    } catch (_) {
      // Parse errors are reported when that document itself is built.
      return false;
    }
  }

  CodegenException _report(CodegenException e) {
    log.severe(e.format(format: CodegenConfigContext.diagnosticsFormat));
    return e;
  }

  /// Loads the schema text.
  ///
  /// Local schemas inside the package are read through [buildStep] so that
  /// editing the schema triggers regeneration.
  Future<String> _loadSchema(BuildStep buildStep) async {
    final source = config.schemaUrl;

    if (source.startsWith('http://') || source.startsWith('https://')) {
      final cached = _remoteSchemas[source];
      if (cached != null) return cached;
      final future = SchemaDownloader.downloadSchema(source,
          headers: config.schemaHeaders);
      _remoteSchemas[source] = future;
      try {
        return await future;
      } catch (e, st) {
        _remoteSchemas.remove(source);
        if (e is CodegenException) throw _report(e);
        throw _report(CodegenException(
          CodegenErrorCodes.schemaDownloadFailed,
          'Failed to download schema from $source: $e',
          cause: e,
          stackTrace: st,
        ));
      }
    }

    final assetId = _schemaAssetId(buildStep.inputId.package);
    if (assetId != null && await buildStep.canRead(assetId)) {
      return buildStep.readAsString(assetId);
    }
    if (source.startsWith('package:')) {
      throw _report(CodegenException(
        CodegenErrorCodes.schemaFileNotFound,
        'Schema file not found: $source (it must be in lib/ of a dependency '
        'of this package)',
      ));
    }

    try {
      return await SchemaDownloader.downloadSchema(source);
    } on FileSystemException catch (e, st) {
      throw _report(CodegenException(
        CodegenErrorCodes.schemaFileNotFound,
        'Schema file not found: $source',
        cause: e,
        stackTrace: st,
      ));
    } on FormatException catch (e, st) {
      throw _report(CodegenException(
        CodegenErrorCodes.schemaInvalid,
        e.message,
        cause: e,
        stackTrace: st,
      ));
    }
  }

  /// The schema as an asset of [package], if it is a path inside the package,
  /// or as an asset of another package for a `package:` URI (e.g. the schema
  /// of a package shared by several packages).
  AssetId? _schemaAssetId(String package) {
    if (config.schemaUrl.startsWith('package:')) {
      return _packageUriAssetId(config.schemaUrl);
    }
    final relative = _packageRelativePath(config.schemaUrl);
    return relative == null ? null : AssetId(package, relative);
  }

  /// Converts a local path or `file://` URI into a package-relative POSIX
  /// path, or returns null when it points outside the current package.
  static String? _packageRelativePath(String path) {
    var local = path;
    if (local.startsWith('file://')) {
      local = p.fromUri(Uri.parse(local));
    }
    if (p.isAbsolute(local)) {
      local = p.relative(local, from: Directory.current.path);
    }
    final posix = p.posix.normalize(local.replaceAll(r'\', '/'));
    if (posix.startsWith('../') || posix == '..' || p.posix.isAbsolute(posix)) {
      return null;
    }
    return posix;
  }

  /// The parsed schema, reused while [schemaText] is unchanged.
  DocumentNode _schemaDocFor(String schemaText) {
    if (schemaText != _parsedSchemaText) {
      _parsedSchema = gql_lang.parseString(schemaText);
      _parsedSchemaText = schemaText;
    }
    return _parsedSchema!;
  }

  /// Schema artifacts; with [usedTypes] (`prune_types`), types.dart declares
  /// only those types.
  _SchemaArtifacts _artifactsFor(String schemaText, [Set<String>? usedTypes]) {
    final usedKey =
        usedTypes == null ? null : (usedTypes.toList()..sort()).join(',');
    final cached = _cachedArtifacts;
    if (cached != null &&
        schemaText == _cachedSchemaText &&
        usedKey == _cachedUsedTypes) {
      return cached;
    }

    try {
      final schemaDoc = _schemaDocFor(schemaText);
      final typesCode =
          TypeGenerator.generateTypesFile(schemaText, only: usedTypes);
      final artifacts = _SchemaArtifacts(
        schemaDoc,
        typesCode,
        OperationAnalyzer.extractDefinedTypes(typesCode),
      );
      _cachedSchemaText = schemaText;
      _cachedUsedTypes = usedKey;
      _cachedArtifacts = artifacts;
      return artifacts;
    } catch (e, st) {
      if (e is CodegenException) throw _report(e);
      throw _report(CodegenException(
        CodegenErrorCodes.schemaInvalid,
        'Failed to process schema ${config.schemaUrl}: $e',
        cause: e,
        stackTrace: st,
      ));
    }
  }

  /// Fragments defined in other documents (matched by `document_paths`) that
  /// [document] spreads but does not define itself.
  Future<Map<String, FragmentDefinitionNode>> _externalFragments(
      BuildStep buildStep, DocumentNode document) async {
    final local = DocumentUtils.collectFragments([document]);
    final missing = _fragmentSpreads(document).difference(local.keys.toSet());
    if (missing.isEmpty) return const {};

    final docs = <DocumentNode>[];
    final seen = <AssetId>{buildStep.inputId};
    for (final pattern in config.documentPaths) {
      final relative = _packageRelativePath(pattern);
      if (relative == null) continue;
      await for (final id in buildStep.findAssets(Glob(relative))) {
        if (!seen.add(id)) continue;
        final text = await buildStep.readAsString(id);
        if (!text.contains('fragment')) continue;
        try {
          docs.add(gql_lang.parseString(text, url: id.path));
        } catch (_) {
          // Parse errors are reported when that document itself is built.
        }
      }
    }
    // Missing fragments still left are reported by the generator.
    return DocumentUtils.collectFragments(docs);
  }

  /// Parsed documents by asset, reused while their content is unchanged.
  final Map<AssetId, (String, DocumentNode?)> _parsedDocuments = {};

  /// All fragments of the documents matched by `document_paths`, plus those
  /// of [document] (the one being built).
  Future<Map<String, FragmentDefinitionNode>> _allFragments(
      BuildStep buildStep, DocumentNode document) async {
    final docs =
        await _allDocuments(buildStep, document, mustContain: 'fragment');
    try {
      return DocumentUtils.collectFragments(docs);
    } on CodegenException catch (e) {
      throw _report(e);
    }
  }

  /// The schema types the operations and fragments of all documents use
  /// (`prune_types`).
  Future<Set<String>> _usedTypes(BuildStep buildStep, DocumentNode document,
      String schemaText, _ImportedFragments imported) async {
    final docs = await _allDocuments(buildStep, document);
    final Map<String, FragmentDefinitionNode> fragments;
    try {
      fragments = {
        ...imported.fragments,
        ...DocumentUtils.collectFragments(docs),
      };
    } on CodegenException catch (e) {
      throw _report(e);
    }
    return TypeUsage.collect(
      _schemaDocFor(schemaText),
      [
        for (final doc in docs)
          ...doc.definitions.whereType<OperationDefinitionNode>(),
      ],
      fragments,
    );
  }

  /// The documents matched by `document_paths` (only those whose text has
  /// [mustContain], if given) plus [document], sorted by path.
  Future<List<DocumentNode>> _allDocuments(
      BuildStep buildStep, DocumentNode document,
      {String? mustContain}) async {
    final docs = <AssetId, DocumentNode>{buildStep.inputId: document};
    for (final pattern in config.documentPaths) {
      final relative = _packageRelativePath(pattern);
      if (relative == null) continue;
      await for (final id in buildStep.findAssets(Glob(relative))) {
        if (docs.containsKey(id)) continue;
        final text = await buildStep.readAsString(id);
        if (mustContain != null && !text.contains(mustContain)) continue;
        final cached = _parsedDocuments[id];
        DocumentNode? parsed;
        if (cached != null && cached.$1 == text) {
          parsed = cached.$2;
        } else {
          try {
            parsed = gql_lang.parseString(text, url: id.path);
          } catch (_) {
            // Parse errors are reported when that document itself is built.
          }
          _parsedDocuments[id] = (text, parsed);
        }
        if (parsed != null) docs[id] = parsed;
      }
    }
    final ids = docs.keys.toList()..sort((a, b) => a.path.compareTo(b.path));
    return [for (final id in ids) docs[id]!];
  }

  // ---------------------------------------------------------------------------
  // fragment_imports: fragments generated by other packages
  // ---------------------------------------------------------------------------

  /// The fragments of `fragment_imports`, read through [buildStep] from the
  /// other packages' `lib/` (so their changes trigger a rebuild).
  ///
  /// build_runner can only list the assets of the package being built, so
  /// the files matching a `documents` glob are listed on disk (in the
  /// package's directory from `.dart_tool/package_config.json`) and then read
  /// through [buildStep]. A file added to the other package is picked up
  /// once a document of this package is rebuilt.
  Future<_ImportedFragments> _importedFragments(BuildStep buildStep) async {
    final imports = CodegenConfigContext.fragmentImports;
    if (imports.isEmpty) return _ImportedFragments.none;

    final fragments = <String, FragmentDefinitionNode>{};
    final libraries = <String, String>{};
    final declarations = <String, String>{};
    for (final import in imports) {
      final docs = [
        for (final id in await _findPackageAssets(buildStep, import.documents))
          if (await _parsedAsset(buildStep, id) case final doc?) doc,
      ];
      final Map<String, FragmentDefinitionNode> found;
      try {
        found = DocumentUtils.collectFragments(docs);
      } on CodegenException catch (e) {
        throw _report(e);
      }
      if (found.isEmpty) {
        _warnOnce('fragment_imports: no fragments found in '
            '${import.documents}');
      }
      for (final MapEntry(key: name, value: fragment) in found.entries) {
        final other = libraries[name];
        if (other != null && other != import.dart) {
          throw _report(CodegenException(
            CodegenErrorCodes.buildDuplicateFragment,
            'Fragment "$name" is imported from both $other and '
            '${import.dart} (fragment_imports); rename one of them',
          ));
        }
        fragments[name] = fragment;
        libraries[name] = import.dart;
      }

      final names = await _libraryDeclarations(buildStep, import.dart);
      if (names == null) {
        _warnOnce('fragment_imports: ${import.dart} not found; generate the '
            'code of its package first');
        continue;
      }
      for (final name in names) {
        declarations.putIfAbsent(name, () => import.dart);
      }
      for (final name in found.keys) {
        if (!names.contains('${name.toCamelCase()}FragmentName')) {
          _warnOnce('fragment_imports: ${import.dart} does not declare '
              'fragment "$name" (from ${import.documents}); regenerate the '
              'code of its package');
        }
      }
    }
    return _ImportedFragments(fragments, libraries, declarations);
  }

  /// Throws when a fragment of this package ([local]) has the name of an
  /// imported one: both libraries would declare its interface.
  void _checkImportedFragmentNames(
      Map<String, FragmentDefinitionNode> local, _ImportedFragments imported) {
    for (final name in local.keys) {
      final library = imported.libraries[name];
      if (library == null) continue;
      throw _report(CodegenException(
        CodegenErrorCodes.buildDuplicateFragment,
        'Fragment "$name" is defined in this package and imported from '
        '$library (fragment_imports); rename one of them',
      ));
    }
  }

  /// Throws when [names] (declared by [file]) clash with declarations of
  /// imported fragment libraries, which index.dart exports too.
  void _checkImportedDeclarations(String file, Set<String> names) {
    final clashes = names.where(_importedDeclarations.containsKey).toList()
      ..sort();
    if (clashes.isEmpty) return;
    final name = clashes.first;
    throw _report(CodegenException(
      CodegenErrorCodes.buildDuplicateDeclaration,
      '$file declares "$name", which ${_importedDeclarations[name]} '
      '(fragment_imports) declares as well; rename the operation or fragment',
    ));
  }

  /// Declarations of the imported fragment libraries of the current build
  /// step: name -> library URI.
  Map<String, String> _importedDeclarations = const {};

  /// Top-level names declared by the Dart library [uri] (`package:`), or null
  /// when it can't be read.
  Future<Set<String>?> _libraryDeclarations(
      BuildStep buildStep, String uri) async {
    final id = _packageUriAssetId(uri);
    if (id == null || !await buildStep.canRead(id)) return null;
    final text = await buildStep.readAsString(id);
    final cached = _libraryNames[id];
    if (cached != null && cached.$1 == text) return cached.$2;
    final names = topLevelDeclarations(text).toSet();
    _libraryNames[id] = (text, names);
    return names;
  }

  final Map<AssetId, (String, Set<String>)> _libraryNames = {};

  /// The document [id], parsed (and cached while unchanged); null when it
  /// can't be parsed or defines no fragment.
  Future<DocumentNode?> _parsedAsset(BuildStep buildStep, AssetId id) async {
    final text = await buildStep.readAsString(id);
    if (!text.contains('fragment')) return null;
    final cached = _parsedDocuments[id];
    if (cached != null && cached.$1 == text) return cached.$2;
    DocumentNode? parsed;
    try {
      parsed = gql_lang.parseString(text, url: id.uri.toString());
    } catch (_) {
      // Reported when the other package builds that document.
    }
    _parsedDocuments[id] = (text, parsed);
    return parsed;
  }

  /// Assets matching the `package:name/glob` [pattern], sorted. Those of
  /// another package are listed on disk, see [_importedFragments].
  Future<List<AssetId>> _findPackageAssets(
      BuildStep buildStep, String pattern) async {
    final (package, path) = splitPackageUri(pattern)!;
    final glob = Glob('lib/$path');
    final ids = <AssetId>[];
    if (package == buildStep.inputId.package) {
      ids.addAll(await buildStep.findAssets(glob).toList());
    } else {
      final root = await _packageRoot(package);
      if (root == null) {
        throw _report(CodegenException(
          CodegenErrorCodes.cfgInvalid,
          'fragment_imports: package "$package" of $pattern is not a '
          'dependency of this package',
        ));
      }
      if (await Directory(root).exists()) {
        await for (final entity in glob.list(root: root, followLinks: false)) {
          if (entity is! File) continue;
          final relative = p.relative(entity.path, from: root);
          final id = AssetId(package, p.split(relative).join('/'));
          if (await buildStep.canRead(id)) ids.add(id);
        }
      }
    }
    return ids..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Directory of package [package] (the parent of its `lib/`), or null when
  /// it is not in the package config.
  Future<String?> _packageRoot(String package) async {
    final known = packageRoots[package];
    if (known != null) return known;
    return (_packageRootsFromConfig ??= _readPackageConfig())
        .then((roots) => roots[package]);
  }

  Future<Map<String, String>>? _packageRootsFromConfig;

  /// Package directories from the `.dart_tool/package_config.json` of the
  /// package being built (or of the pub workspace it belongs to).
  static Future<Map<String, String>> _readPackageConfig() async {
    var dir = Directory.current.absolute;
    while (true) {
      final file = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final roots = <String, String>{};
        for (final package in (json['packages'] as List).cast<Map>()) {
          // rootUri is relative to the config file (or absolute).
          final root = file.uri.resolve(package['rootUri'] as String);
          roots[package['name'] as String] = p.fromUri(root);
        }
        return roots;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return const {};
      dir = parent;
    }
  }

  /// The asset of a `package:name/path` URI (`lib/path` of package `name`).
  static AssetId? _packageUriAssetId(String uri) {
    final parts = splitPackageUri(uri);
    return parts == null ? null : AssetId(parts.$1, 'lib/${parts.$2}');
  }

  final Set<String> _warned = {};

  void _warnOnce(String message) {
    if (_warned.add(message)) log.warning(message);
  }

  String? _fragmentsSignature;

  /// Writes fragments.dart for [fragments], or removes it when there are
  /// none. Fragments in [libraries] are imported ones: used, not declared.
  Future<void> _writeFragmentsFile(
      _SchemaArtifacts artifacts,
      Map<String, FragmentDefinitionNode> fragments,
      Map<String, String> libraries) async {
    final names = fragments.keys.toList()..sort();
    final signature = [
      identityHashCode(artifacts),
      for (final name in names) gql_lang.printNode(fragments[name]!),
      for (final name in names) libraries[name] ?? '',
      for (final name in _importedDeclarations.keys.toList()..sort()) name,
    ].join('\n');
    final file = File(p.join(config.outputDir, 'fragments.dart'));
    if (signature == _fragmentsSignature &&
        await file.exists() == fragments.isNotEmpty) {
      return;
    }

    final String? code;
    try {
      code = ClientExtensionGenerator.generateFragmentsFile(
          artifacts.schemaDoc, fragments,
          fragmentLibraries: libraries);
    } on CodegenException catch (e) {
      throw _report(e);
    }
    _fragmentDeclarations =
        code == null ? const {} : topLevelDeclarations(code).toSet();
    _checkImportedDeclarations('fragments.dart', _fragmentDeclarations);
    if (code == null) {
      if (await file.exists() &&
          (await file.readAsString())
              .contains('Generated by flutter_graphql_codegen')) {
        await file.delete();
      }
    } else {
      final outputDir = Directory(config.outputDir);
      if (!outputDir.existsSync()) {
        await outputDir.create(recursive: true);
      }
      await _writeIfChanged(file, _format(code, 'fragments.dart'));
      log.fine('Generated fragments file: ${file.path}');
    }
    _fragmentsSignature = signature;
  }

  static Set<String> _fragmentSpreads(DocumentNode document) {
    final names = <String>{};
    void visit(SelectionSetNode set) {
      for (final sel in set.selections) {
        if (sel is FragmentSpreadNode) {
          names.add(sel.name.value);
        } else if (sel is FieldNode && sel.selectionSet != null) {
          visit(sel.selectionSet!);
        } else if (sel is InlineFragmentNode) {
          visit(sel.selectionSet);
        }
      }
    }

    for (final def in document.definitions) {
      if (def is OperationDefinitionNode) visit(def.selectionSet);
      if (def is FragmentDefinitionNode) visit(def.selectionSet);
    }
    return names;
  }

  // ---------------------------------------------------------------------------
  // Operation groups (group_operations: directory)
  // ---------------------------------------------------------------------------

  /// Directory the groups of documents are relative to.
  late final String? _documentsRoot = documentsRoot(
      config.documentPaths.map(_packageRelativePath).whereType<String>());

  /// The group of the operations in document [path], or null when they are
  /// not grouped (grouping is off, or the document is directly in the
  /// documents root).
  OperationGroup? _groupOf(String path) =>
      CodegenConfigContext.groupOperations == 'directory'
          ? OperationGroup.forDocument(path, _documentsRoot,
              fileNaming: config.fileNaming)
          : null;

  /// Group files written by the last [_writeGroupFiles], sorted.
  List<String> _groupFiles = const [];

  static final _operationKindHeader =
      RegExp(r'^// Operation: (\w+) \((\w+)\)', multiLine: true);

  /// Writes the file of every group that operation files in the output
  /// directory belong to, and deletes the group files of groups without
  /// any.
  ///
  /// Like index.dart, the files follow what is on disk, so the operation
  /// files of other documents (from this or earlier builds) count too.
  Future<void> _writeGroupFiles(
      BuildStep buildStep, _SchemaArtifacts artifacts) async {
    final dir = Directory(config.outputDir);
    if (!await dir.exists()) return;

    final operationFiles = <String, List<String>>{};
    final existing = <String, File>{};
    // Getter names that would clash with the client's own members or the
    // operations' extension methods on it.
    final taken = {...ClientExtensionGenerator.clientMemberNames};
    final grouping = CodegenConfigContext.groupOperations == 'directory';
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Without grouping only group files of earlier builds are looked for.
      if (!grouping && entity.path.endsWith('.g.dart')) continue;
      // The headers are all that is needed.
      final text = await entity
          .openRead(0, 4096)
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      if (!text.contains('Generated by flutter_graphql_codegen')) continue;
      final fileName = p.basename(entity.path);
      if (OperationGroup.groupOfGroupFile(text) != null) {
        existing[fileName] = entity;
        continue;
      }
      final header = _operationKindHeader.firstMatch(text);
      if (header == null) continue;
      taken.addAll(ClientExtensionGenerator.operationMemberNames(
          header.group(1)!, header.group(2)!));
      final group = OperationGroup.groupOfOperationFile(text);
      if (group != null) {
        operationFiles.putIfAbsent(group, () => []).add(fileName);
      }
    }

    final byName = <String, OperationGroup>{};
    final byFile = <String, OperationGroup>{};
    final codes = <OperationGroup, String>{};
    for (final path in operationFiles.keys.toList()..sort()) {
      final group =
          OperationGroup.fromPath(path, fileNaming: config.fileNaming);
      final other = byName[group.name] ?? byFile[group.fileName];
      if (other != null) {
        throw _report(CodegenException(
          CodegenErrorCodes.buildDuplicateDeclaration,
          'The documents directories "${other.path}" and "$path" both '
          'become the operation group "${group.name}" '
          '(${group.fileName}); rename one of them',
        ));
      }
      byName[group.name] = byFile[group.fileName] = group;
      codes[group] =
          group.groupFile(group.getterName(taken), operationFiles[path]!);
    }

    final typeNames = topLevelDeclarations(artifacts.typesCode).toSet();
    for (final MapEntry(key: group, value: code) in codes.entries) {
      final names = topLevelDeclarations(code).toSet();
      String? where;
      if (names.intersection(typeNames).isNotEmpty) {
        where = 'types.dart';
      } else if (names.intersection(_fragmentDeclarations).isNotEmpty) {
        where = 'fragments.dart';
      } else {
        for (final d in _declarations.values) {
          if (d.names.intersection(names).isNotEmpty &&
              await _stillDefined(buildStep, d)) {
            where = 'operation "${d.operation}" in ${d.source}';
            break;
          }
        }
      }
      if (where != null) {
        throw _report(CodegenException(
          CodegenErrorCodes.buildDuplicateDeclaration,
          'The operation group of the documents in "${group.path}" declares '
          '${names.map((n) => '"$n"').join(' and ')}, and $where declares '
          'one of these names as well; rename the directory or the '
          'declaration',
        ));
      }
    }

    for (final MapEntry(key: group, value: code) in codes.entries) {
      await _writeIfChanged(File(p.join(config.outputDir, group.fileName)),
          _format(code, group.fileName));
    }
    for (final MapEntry(key: name, value: file) in existing.entries) {
      if (!byFile.containsKey(name)) await file.delete();
    }
    _groupFiles = byFile.keys.toList()..sort();
  }

  /// Generates index.dart file with all operations
  Future<void> _generateIndexFile(String package) async {
    try {
      // Find all generated .g.dart files
      final generatedFiles = <File>[];
      await _findGeneratedFiles(generatedFiles);

      final exports = <String>[];
      final operations = <String>[];

      // Sort files deterministically by basename
      generatedFiles
          .sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      for (final file in generatedFiles) {
        final content = await file.readAsString();

        if (!content.contains('Generated by flutter_graphql_codegen')) {
          continue;
        }

        // Files are in the same folder as index.dart, use a safe file name
        final fileName = p.basename(file.path);
        exports.add("export '$fileName';");

        // Extract operation name from file name, respecting the configured naming mode
        final baseName = fileName.replaceAll('_graphql.g.dart', '');
        final operationName = _fileBaseNameToOperationName(baseName);
        operations.add('// $operationName');
      }

      final hasFragments =
          File(p.join(config.outputDir, 'fragments.dart')).existsSync();
      if (exports.isEmpty && !hasFragments) {
        log.fine('No generated GraphQL files found for index');
        return;
      }

      final import = packageImportOf(package, config.outputDir);
      final usage = import == null ? '' : "\n// Usage: import '$import';\n";

      // Create index file
      final indexContent = '''// AUTO-GENERATED FILE - DO NOT EDIT
// Generated by flutter_graphql_codegen
// GraphQL operations index

// Export types
${_sharedLibraryExports()}${hasFragments ? "export 'fragments.dart';\n" : ''}
// Export all generated operations
${exports.join('\n')}
${_groupFiles.isEmpty ? '' : '\n// Export operation groups\n${_groupFiles.map((f) => "export '$f';").join('\n')}\n'}
// Available operations:
${operations.join('\n')}
$usage''';

      // Create the directory if it does not exist
      final outputDir = Directory(config.outputDir);
      if (!outputDir.existsSync()) {
        await outputDir.create(recursive: true);
      }

      // Write index file
      final indexFile = File(p.join(config.outputDir, 'index.dart'));
      await _writeIfChanged(indexFile, _format(indexContent, 'index.dart'));
    } catch (e, st) {
      throw _report(CodegenException(
          CodegenErrorCodes.buildIndexFailed, 'Failed to generate index.dart',
          cause: e, stackTrace: st));
    }
  }

  /// Exports of index.dart for types.dart (that of another package with
  /// `types_import`) and the `fragments.dart` of other packages
  /// (`fragment_imports`, operation result types only), so importing
  /// index.dart is enough to use the generated code.
  static String _sharedLibraryExports() => [
        for (final library in {
          CodegenConfigContext.typesImport ?? 'types.dart',
          if (CodegenConfigContext.operationResultTypes)
            for (final import in CodegenConfigContext.fragmentImports)
              import.dart,
        })
          "export '$library';\n",
      ].join();

  /// The `package:` URI of `index.dart` in [outputDir], or null when
  /// [outputDir] is not inside `lib/` of [package].
  static String? packageImportOf(String package, String outputDir) {
    final relative = _packageRelativePath(outputDir);
    if (relative == null || !relative.startsWith('lib/')) return null;
    final inLib =
        relative.substring('lib/'.length).replaceAll(RegExp(r'/+$'), '');
    return 'package:$package/${inLib.isEmpty ? '' : '$inLib/'}index.dart';
  }

  static Future<Version?> _packageLanguageVersion(BuildStep buildStep) async {
    try {
      final config = await buildStep.packageConfig;
      final version = config[buildStep.inputId.package]?.languageVersion;
      return version == null ? null : Version(version.major, version.minor, 0);
    } catch (_) {
      return null;
    }
  }

  /// Formats generated [code]; if that fails (a generator bug), the code is
  /// written unformatted so it can still be inspected.
  String _format(String code, String fileName) {
    try {
      return formatGeneratedCode(code, languageVersion: _languageVersion);
    } on FormatterException catch (e) {
      log.warning('Could not format generated $fileName, writing it '
          'unformatted. Please report this: ${e.message()}');
      return code;
    }
  }

  /// Writes types.dart when its content changed since the last write.
  ///
  /// With `types_import` the types of another package are used instead, and
  /// a types.dart generated here earlier is removed.
  Future<void> _writeTypesFile(String typesCode) async {
    if (CodegenConfigContext.typesImport != null) {
      await _removeGeneratedTypesFile();
      return;
    }
    if (typesCode == _lastWrittenTypes) return;

    // Create the directory if it does not exist
    final outputDir = Directory(config.outputDir);
    if (!outputDir.existsSync()) {
      await outputDir.create(recursive: true);
    }

    final typesFile = File(p.join(config.outputDir, 'types.dart'));
    await _writeIfChanged(typesFile, _format(typesCode, 'types.dart'));
    _lastWrittenTypes = typesCode;
    log.fine('Generated types file: ${typesFile.path}');
  }

  bool _removedTypesFile = false;

  /// Deletes types.dart in the output directory if this generator wrote it
  /// (before `types_import` was set).
  Future<void> _removeGeneratedTypesFile() async {
    if (_removedTypesFile) return;
    _removedTypesFile = true;
    final file = File(p.join(config.outputDir, 'types.dart'));
    if (await file.exists() &&
        (await file.readAsString())
            .contains('Generated by flutter_graphql_codegen')) {
      await file.delete();
      log.fine('Removed ${file.path}: types_import is set');
    }
  }

  /// Writes operation file to the configured output directory
  Future<void> _writeToOutputDirectory(
      String operationName, String content) async {
    // Create the directory if it does not exist
    final outputDir = Directory(config.outputDir);
    if (!outputDir.existsSync()) {
      await outputDir.create(recursive: true);
    }

    // Create the file in the output directory
    final fileName = _generateOutputFileName(operationName);
    final filePath = p.join(config.outputDir, fileName);
    final file = File(filePath);

    await _writeIfChanged(file, _format(content, fileName));
  }

  /// Finds all generated .g.dart files
  Future<void> _findGeneratedFiles(List<File> files) async {
    // Search files in the output directory instead of the entire lib
    final outputDir = Directory(config.outputDir);
    if (!outputDir.existsSync()) {
      return;
    }

    await for (final entity
        in outputDir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.g.dart')) {
        files.add(entity);
      }
    }
  }

  /// Converts a file base name back to a PascalCase operation name,
  /// handling any configured naming mode (snake_case, kebab-case, camelCase, PascalCase).
  String _fileBaseNameToOperationName(String baseName) {
    // Split on underscores or hyphens to handle snake_case and kebab-case
    final parts = baseName.split(RegExp(r'[_\-]'));
    if (parts.length > 1) {
      // snake_case or kebab-case: capitalize each part
      return parts
          .where((p) => p.isNotEmpty)
          .map((p) => p[0].toUpperCase() + p.substring(1))
          .join('');
    }
    // camelCase or PascalCase: just capitalize first letter
    if (baseName.isNotEmpty) {
      return baseName[0].toUpperCase() + baseName.substring(1);
    }
    return baseName;
  }

  /// Generates the output file name based on operation name
  /// Example: GetProductList -> get_product_list_graphql.g.dart
  String _generateOutputFileName(String operationName) {
    // Respect configured file naming mode
    final base = transformFileBaseName(operationName, config.fileNaming);
    return '${base}_graphql.g.dart';
  }

  /// Deterministic write helper: writes file only if content has changed.
  Future<void> _writeIfChanged(File file, String newContent) async {
    if (await file.exists()) {
      final current = await file.readAsString();
      if (current == newContent) {
        return;
      }
    }
    await file.writeAsString(newContent);
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        '.graphql': ['.g.dart'],
      };
}

Builder graphqlCodegenBuilder(BuilderOptions options) {
  final configPath = options.config['config_path'] as String?;
  if (configPath == null) {
    throw ArgumentError('Missing config_path in builder options');
  }

  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    throw FileSystemException('Config file not found', configPath);
  }

  final cfg = GraphQLCodegenConfig.fromYaml(configFile.readAsStringSync());
  // Push to global context for static generators
  CodegenConfigContext.fileNaming = cfg.fileNaming;
  CodegenConfigContext.strictNullability = cfg.strictNullability;
  CodegenConfigContext.emitIndex = cfg.emitIndex;
  CodegenConfigContext.diagnosticsFormat = cfg.diagnosticsFormat;
  CodegenConfigContext.scalarMapping = Map.of(cfg.scalarMapping);
  CodegenConfigContext.unknownEnumFallback = cfg.unknownEnumFallback;
  CodegenConfigContext.deprecatedAnnotations = cfg.deprecatedAnnotations;
  CodegenConfigContext.includeNullInputs = cfg.includeNullInputs;
  CodegenConfigContext.validateDocuments = cfg.validateDocuments;
  CodegenConfigContext.resultTypes = cfg.resultTypes;
  CodegenConfigContext.flutterWidgets = cfg.flutterWidgets;
  CodegenConfigContext.flutterHooks = cfg.flutterHooks;
  CodegenConfigContext.enumConfigs = Map.of(cfg.enums);
  CodegenConfigContext.groupOperations = cfg.groupOperations;
  CodegenConfigContext.typesImport = cfg.typesImport;
  CodegenConfigContext.pruneTypes = cfg.pruneTypes;
  CodegenConfigContext.fragmentImports = List.of(cfg.fragmentImports);
  CodegenConfigContext.scalarImports = Map.of(cfg.scalarImports);
  CodegenConfigContext.scalarConverters = Map.of(cfg.scalarConverters);
  CodegenConfigContext.strictScalars = cfg.strictScalars;

  return GraphQLCodegenBuilder(cfg);
}
