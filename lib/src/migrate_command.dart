/// `dart run flutter_graphql_codegen:migrate`: writes `graphql_codegen.yaml`
/// from the `build.yaml` options of Artemis or graphql_codegen, and lists
/// what has to be checked by hand.
library;

import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Exit code for wrong usage.
const int _usageError = 64;

/// What [migrateBuildYaml] made of a `build.yaml`.
class Migration {
  Migration(this.from, this.config, this.notes);

  /// `artemis` or `graphql_codegen`.
  final String from;

  /// The text of `graphql_codegen.yaml`.
  final String config;

  /// What the config can't carry over, for the person migrating.
  final List<String> notes;
}

/// The build can't be migrated (no generator found, several schemas, ...).
class MigrationException implements Exception {
  MigrationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Converts the options of the Artemis or graphql_codegen builder in
/// [buildYaml] to a `graphql_codegen.yaml`.
///
/// [schemaFiles] lists the files matching a glob that hold a GraphQL schema
/// (graphql_codegen finds the schema among its documents); by default the
/// files under [root] are read.
Migration migrateBuildYaml(
  String buildYaml, {
  String root = '.',
  List<String> Function(String glob)? schemaFiles,
}) {
  final Object? doc;
  try {
    doc = loadYaml(buildYaml);
  } on YamlException catch (e) {
    throw MigrationException('build.yaml is not valid YAML: ${e.message}');
  }
  final found = <String, Map<Object?, Object?>>{};
  if (doc case {'targets': final Map<Object?, Object?> targets}) {
    for (final target in targets.values) {
      if (target case {'builders': final Map<Object?, Object?> builders}) {
        for (final MapEntry(:key, :value) in builders.entries) {
          final name = '$key'.split(RegExp('[:|]')).first;
          if (name != 'artemis' && name != 'graphql_codegen') continue;
          final options = value is Map ? value['options'] : null;
          found[name] = options is Map ? options : const {};
        }
      }
    }
  }
  if (found.isEmpty) {
    throw MigrationException('build.yaml has no options for the artemis or '
        'graphql_codegen builder');
  }
  if (found.length > 1) {
    throw MigrationException('build.yaml configures both artemis and '
        'graphql_codegen; pass --from to pick one');
  }
  final MapEntry(key: from, value: options) = found.entries.single;
  return from == 'artemis'
      ? _fromArtemis(options)
      : _fromGraphqlCodegen(
          options, schemaFiles ?? (glob) => _localSchemaFiles(root, glob));
}

Migration _fromArtemis(Map<Object?, Object?> options) {
  final notes = <String>[];
  final maps = [
    for (final m in (options['schema_mapping'] as List?) ?? const [])
      if (m is Map) m,
  ];
  if (maps.isEmpty) {
    throw MigrationException('The artemis options have no schema_mapping');
  }
  final schemas = {for (final m in maps) '${m['schema']}'};
  if (schemas.length > 1) {
    throw MigrationException('The schema_mapping uses ${schemas.length} '
        'schemas (${schemas.join(', ')}), and flutter_graphql_codegen reads '
        'one schema per package. Move the operations of each schema to a '
        'package of its own, each with its own graphql_codegen.yaml.');
  }
  final documents = <String>{
    for (final m in maps)
      if (m['queries_glob'] case final Object glob) '$glob',
    for (final m in maps)
      if (m['fragments_glob'] case final Object glob) '$glob',
    if (options['fragments_glob'] case final Object glob) '$glob',
  };
  final outputs = {
    for (final m in maps)
      if (m['output'] case final Object output) '$output',
  };
  final outputDir = outputs.isEmpty
      ? 'lib/graphql/generated'
      : p.posix.join(p.posix.dirname(outputs.first), 'generated');
  notes.add('The generated code goes to $outputDir/ as one file per '
      'operation; import $outputDir/index.dart where you imported '
      '${outputs.isEmpty ? 'the Artemis output' : outputs.join(', ')}.');

  for (final m in maps) {
    if (m['type_name_field'] case final Object field
        when '$field' != '__typename') {
      notes.add('type_name_field: $field is not supported; __typename is '
          'used and added to every selection.');
    }
    if (m['naming_scheme'] case final Object scheme) {
      notes.add('naming_scheme: $scheme has no equivalent. Classes are named '
          '<Operation>_<field>, e.g. GetUser_User (see README, Result '
          'classes).');
    }
  }
  if (options['generate_helpers'] != false) {
    notes.add('ArtemisClient and the <Operation>Query classes are not '
        'generated: call the GraphQLClient extensions instead '
        '(client.getUser(...), client.getUserData(...)).');
  }
  if (options['ignore_for_file'] != null) {
    notes.add('ignore_for_file has no equivalent; the generated files '
        'already ignore type=lint.');
  }
  notes.add('Enums get \$unknown for values added on the server later '
      '(unknown_enum_fallback: true), where Artemis had artemisUnknown.');

  final scalars = <String, Map<String, String>>{};
  for (final s in (options['scalar_mapping'] as List?) ?? const []) {
    if (s is! Map || s['graphql_type'] == null) continue;
    final graphql = '${s['graphql_type']}';
    final dart = s['dart_type'];
    final type = dart is Map ? '${dart['name']}' : '$dart';
    final typeImports = dart is Map
        ? [for (final i in (dart['imports'] as List?) ?? const []) '$i']
        : const <String>[];
    // Per scalar, or (older Artemis) shared, for scalars with
    // use_custom_parser: true.
    final parser = s['custom_parser_import'] ??
        (s['use_custom_parser'] == true
            ? options['custom_parser_import']
            : null);
    final entry = <String, String>{'type': type};
    if (parser != null) {
      // Artemis' coercers for the non-null case; the converter handles null.
      final dartName = type.replaceAll(RegExp(r'\W'), '');
      entry
        ..['import'] = '$parser'
        ..['from_json'] = 'fromGraphQL${graphql}ToDart$dartName'
        ..['to_json'] = 'fromDart${dartName}ToGraphQL$graphql';
      if (typeImports.isNotEmpty) {
        notes.add('Scalar $graphql: only one import per scalar is read. '
            'Export ${typeImports.join(', ')} from $parser, or the type '
            '$type won\'t be found.');
      }
    } else if (typeImports.isNotEmpty) {
      entry['import'] = typeImports.first;
      notes.add('Scalar $graphql: $type is parsed with $type.fromJson and '
          'written with toJson(); check that it has them, or add from_json '
          'and to_json (see README, Custom scalars).');
    }
    scalars[graphql] = entry;
  }

  return Migration(
      'artemis',
      _write(
        from: 'Artemis',
        schema: schemas.single,
        documents: documents.toList(),
        outputDir: outputDir,
        scalars: scalars,
        extra: const {'unknown_enum_fallback': 'true'},
      ),
      notes);
}

Migration _fromGraphqlCodegen(Map<Object?, Object?> options,
    List<String> Function(String glob) schemaFiles) {
  final notes = <String>[];
  final scopes = [
    for (final s in (options['scopes'] as List?) ?? const []) '$s'
  ];
  if (scopes.length > 1) {
    throw MigrationException('The options have ${scopes.length} scopes '
        '(${scopes.join(', ')}), one schema each, and flutter_graphql_codegen '
        'reads one schema per package. Move each scope to a package of its '
        'own, each with its own graphql_codegen.yaml.');
  }
  // graphql_codegen reads .graphql, .gql and .graphqls files; operations
  // here must be .graphql files.
  final assets =
      '${options['assetsPath'] ?? 'lib/**{.graphql,.gql,.graphqls}'}';
  final documentGlob = assets.replaceAll(RegExp(r'\{\.[\w.,]+\}$'), '.graphql');
  if (documentGlob != assets || assets.endsWith('.gql')) {
    notes.add('Only .graphql files are read as documents: rename any .gql '
        'operation files.');
  }
  final schemas = schemaFiles(assets);
  final String schema;
  if (schemas.length == 1) {
    schema = schemas.single;
  } else {
    schema = schemas.isEmpty ? 'lib/schema.graphql' : schemas.first;
    notes.add(schemas.isEmpty
        ? 'No schema file found in $assets; set schema_url to it.'
        : 'The schema is split across ${schemas.join(', ')}; schema_url '
            'takes one file, so merge them into $schema.');
  }

  final output = options['outputDirectory'];
  final String outputDir;
  if (output case final Object dir when '$dir'.startsWith('/')) {
    outputDir = '$dir'.substring(1);
  } else {
    outputDir = 'lib/graphql/generated';
  }
  notes.add('The generated code goes to $outputDir/ as one file per '
      'operation, instead of a .graphql.dart next to each document; import '
      '$outputDir/index.dart instead.');
  notes.add('Names change: Query\$GetUser\$user becomes GetUser_User, '
      'Variables\$Query\$GetUser GetUserVariables, client.query\$GetUser(...) '
      'client.getUser(...) or client.getUserData(...), Input\$X and Enum\$X '
      'are X. See README, What you get.');

  final clients = [
    for (final c in (options['clients'] as List?) ?? const []) '$c',
  ];
  final flutter = clients.contains('graphql_flutter');
  if (flutter) {
    notes.add('Query\$GetUser\$Widget becomes GetUserQuery and '
        'useQuery\$GetUser useGetUserQuery (see README, Flutter widgets and '
        'hooks).');
  }

  for (final (key, text) in const [
    (
      'addTypenameExcludedPaths',
      '__typename is added to every selection but '
          'the root; addTypenameExcludedPaths has no equivalent.'
    ),
    ('namingSeparator', 'namingSeparator has no equivalent: names use _.'),
    (
      'extraKeywords',
      'extraKeywords is not needed: fields named like Dart '
          'keywords or types are renamed for you (see README, Names that '
          'aren\'t valid Dart).'
    ),
    ('generatedFileHeader', 'generatedFileHeader has no equivalent.'),
    (
      'disableCopyWithGeneration',
      'disableCopyWithGeneration has no '
          'equivalent: result classes always have copyWith.'
    ),
    (
      'allowMissingNullableKeysInFromJson',
      'allowMissingNullableKeysInFromJson '
          'is not needed: a missing nullable field parses as null.'
    ),
  ]) {
    if (options.containsKey(key)) notes.add(text);
  }
  if (options['addTypename'] == false) {
    notes.add('addTypename: false has no equivalent: __typename is always '
        'added (the cache and unions need it).');
  }

  final scalars = <String, Map<String, String>>{};
  if (options['scalars'] case final Map<Object?, Object?> map) {
    for (final MapEntry(:key, :value) in map.entries) {
      if (value is! Map || value['type'] == null) continue;
      final entry = <String, String>{'type': '${value['type']}'};
      if (value['import'] case final Object import) {
        entry['import'] = '$import';
      }
      final fromJson = value['fromJsonFunctionName'];
      final toJson = value['toJsonFunctionName'];
      if (fromJson != null && toJson != null) {
        entry
          ..['from_json'] = '$fromJson'
          ..['to_json'] = '$toJson';
        if (!entry.containsKey('import')) {
          notes.add('Scalar $key: add the import that exports $fromJson and '
              '$toJson.');
          entry['import'] = 'package:<your_package>/<file>.dart';
        }
      }
      scalars['$key'] = entry;
    }
  }

  final enums = <String, Map<String, String>>{};
  if (options['enums'] case final Map<Object?, Object?> map) {
    for (final MapEntry(:key, :value) in map.entries) {
      if (value is! Map) continue;
      final entry = <String, String>{};
      if (value['fallbackEnumValue'] case final Object fallback) {
        entry['fallback'] = '$fallback';
      }
      if (value['type'] case final Object type) {
        entry
          ..['type'] = '$type'
          ..['import'] =
              '${value['import'] ?? 'package:<your_package>/<file>.dart'}'
          ..['from_json'] = '${value['fromJsonFunctionName'] ?? 'fromJson'}'
          ..['to_json'] = '${value['toJsonFunctionName'] ?? 'toJson'}';
        entry.remove('fallback');
      }
      if (entry.isNotEmpty) enums['$key'] = entry;
    }
  }

  return Migration(
      'graphql_codegen',
      _write(
        from: 'graphql_codegen',
        schema: schema,
        documents: [documentGlob],
        outputDir: outputDir,
        scalars: scalars,
        enums: enums,
        extra: {
          // graphql_codegen adds $unknown to every enum.
          'unknown_enum_fallback': 'true',
          if (flutter) 'flutter_widgets': 'true',
          if (flutter) 'flutter_hooks': 'true',
        },
      ),
      notes);
}

String _write({
  required String from,
  required String schema,
  required List<String> documents,
  required String outputDir,
  Map<String, Map<String, String>> scalars = const {},
  Map<String, Map<String, String>> enums = const {},
  Map<String, String> extra = const {},
}) {
  String q(String v) => RegExp(r'^[\w./-]+$').hasMatch(v) && v != 'true'
      ? v
      : "'${v.replaceAll("'", "''")}'";
  final out = StringBuffer()
    ..writeln('# Written by flutter_graphql_codegen:migrate from the $from '
        'options in build.yaml.')
    ..writeln('schema_url: ${q(schema)}')
    ..writeln('output_dir: ${q(outputDir)}')
    ..writeln('document_paths:');
  for (final d in documents) {
    out.writeln('  - ${q(d)}');
  }
  out.writeln('strict_nullability: true');
  extra.forEach((k, v) => out.writeln('$k: $v'));
  void section(String name, Map<String, Map<String, String>> entries) {
    if (entries.isEmpty) return;
    out.writeln('$name:');
    entries.forEach((key, entry) {
      if (name == 'scalar_mapping' && entry.length == 1) {
        out.writeln('  $key: ${q(entry['type']!)}');
        return;
      }
      out.writeln('  $key:');
      entry.forEach((k, v) => out.writeln('    $k: ${q(v)}'));
    });
  }

  section('scalar_mapping', scalars);
  section('enums', enums);
  return out.toString();
}

/// The files matching [glob] under [root] that define schema types.
List<String> _localSchemaFiles(String root, String glob) {
  final files = <String>[];
  for (final entity in Glob(glob).listSync(root: root)) {
    final file = io.File(entity.path);
    if (!file.existsSync()) continue;
    final DocumentNode doc;
    try {
      doc = gql_lang.parseString(file.readAsStringSync());
    } catch (_) {
      continue;
    }
    if (doc.definitions.any((d) => d is TypeSystemDefinitionNode)) {
      files.add(p.posix.joinAll(p.split(p.relative(entity.path, from: root))));
    }
  }
  return files..sort();
}

/// Runs the command with [args]; returns the process exit code.
Future<int> runMigrate(
  List<String> args, {
  StringSink? stdout,
  StringSink? stderr,
  String root = '.',
}) async {
  final out = stdout ?? io.stdout;
  final err = stderr ?? io.stderr;
  final parser = ArgParser()
    ..addOption('build-yaml',
        defaultsTo: 'build.yaml', help: 'build.yaml with the old options.')
    ..addOption('output',
        defaultsTo: 'graphql_codegen.yaml', help: 'Config file to write.')
    ..addOption('from',
        allowed: ['artemis', 'graphql_codegen'],
        help: 'Generator to migrate from, when build.yaml has both.')
    ..addFlag('force',
        negatable: false, help: 'Overwrite an existing output file.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  void usage(String message) {
    err
      ..writeln(message)
      ..writeln()
      ..writeln('Usage: dart run flutter_graphql_codegen:migrate [options]')
      ..writeln(parser.usage);
  }

  final ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (e) {
    usage(e.message);
    return _usageError;
  }
  if (options['help'] as bool) {
    out
      ..writeln('Writes graphql_codegen.yaml from the build.yaml options of '
          'Artemis or graphql_codegen.')
      ..writeln()
      ..writeln('Usage: dart run flutter_graphql_codegen:migrate [options]')
      ..writeln(parser.usage);
    return 0;
  }

  final buildFile = io.File(p.join(root, options['build-yaml'] as String));
  if (!buildFile.existsSync()) {
    usage('${buildFile.path} not found');
    return _usageError;
  }
  final target = io.File(p.join(root, options['output'] as String));
  if (target.existsSync() && !(options['force'] as bool)) {
    err.writeln('${target.path} exists; pass --force to overwrite it');
    return 1;
  }

  var text = buildFile.readAsStringSync();
  final Migration migration;
  try {
    if (options['from'] case final String from) {
      text = _onlyBuilder(text, from);
    }
    migration = migrateBuildYaml(text, root: root);
  } on MigrationException catch (e) {
    err.writeln(e.message);
    return 1;
  }

  target.writeAsStringSync(migration.config);
  final name = migration.from;
  out
    ..writeln('Wrote ${target.path} from the $name options.')
    ..writeln()
    ..writeln('Next:')
    ..writeln('  - remove $name from dev_dependencies and its builder from '
        '${buildFile.path}')
    ..writeln('  - add flutter_graphql_codegen to dev_dependencies')
    ..writeln('  - dart run build_runner build --delete-conflicting-outputs');
  if (migration.notes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Check by hand:');
    for (final note in migration.notes) {
      out.writeln('  - $note');
    }
  }
  return 0;
}

/// [buildYaml] reduced to the builder of [from], so a build.yaml with both
/// generators can be migrated.
String _onlyBuilder(String buildYaml, String from) {
  final doc = loadYaml(buildYaml);
  if (doc case {'targets': final Map<Object?, Object?> targets}) {
    for (final target in targets.values) {
      if (target case {'builders': final Map<Object?, Object?> builders}) {
        for (final MapEntry(:key, :value) in builders.entries) {
          if ('$key'.split(RegExp('[:|]')).first != from) continue;
          final options = value is Map ? value['options'] : null;
          return _yamlOf({
            'targets': {
              r'$default': {
                'builders': {
                  from: {'options': options ?? {}}
                },
              },
            },
          });
        }
      }
    }
  }
  throw MigrationException('build.yaml has no options for $from');
}

/// JSON is valid YAML, which is all [migrateBuildYaml] needs.
String _yamlOf(Object? value) => switch (value) {
      Map() =>
        '{${value.entries.map((e) => '${_yamlOf('${e.key}')}: ${_yamlOf(e.value)}').join(', ')}}',
      List() => '[${value.map(_yamlOf).join(', ')}]',
      String() => '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"',
      null => 'null',
      _ => '$value',
    };
