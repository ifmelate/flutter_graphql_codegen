// Several packages in one repository: `types_import` and `fragment_imports`.
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:flutter_graphql_codegen/src/builder.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _schema = r'''
type Query { user(id: ID!): User  version: String }
type User { id: ID! name: String  friend: User }
''';

const _typesUri = 'package:shared/graphql/generated/types.dart';
const _fragmentsUri = 'package:shared/graphql/generated/fragments.dart';
const _sharedFragments = 'fragment UserBits on User { id name }';

/// Runs [builder] on package `a` only, as build_runner does (the builder
/// applies to the root package); testBuilder runs it on every package with
/// assets.
class _RootPackageOnly implements Builder {
  _RootPackageOnly(this.builder);

  final Builder builder;

  @override
  Map<String, List<String>> get buildExtensions => builder.buildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.package == 'a') await builder.build(buildStep);
  }
}

const _import = FragmentImport(
  dart: _fragmentsUri,
  documents: 'package:shared/graphql/**.graphql',
);

void main() {
  late Directory outDir;
  late Directory sharedDir;
  late List<String> logs;

  setUp(() async {
    CodegenConfigContext.reset();
    outDir = await Directory.systemTemp.createTemp('fgc_packages_out_');
    sharedDir = await Directory.systemTemp.createTemp('fgc_packages_shared_');
    logs = [];
  });

  tearDown(() async {
    CodegenConfigContext.reset();
    await outDir.delete(recursive: true);
    await sharedDir.delete(recursive: true);
  });

  /// The fragments.dart the shared package generates for [documents].
  String sharedFragmentsDart(String documents) {
    final code = GraphQLCodeGenerator.generateFragmentsFile(
      _schema,
      DocumentUtils.collectFragments([gql_lang.parseString(documents)]),
    );
    return code!;
  }

  /// Builds the documents of package `a` ([assets]). [shared] are files of
  /// package `shared` (path in the package -> content); they are on disk too,
  /// where the builder lists them.
  Future<void> run(
    Map<String, String> assets, {
    Map<String, String> shared = const {},
    String schemaUrl = 'lib/schema.graphql',
    bool packageKnown = true,
  }) async {
    for (final MapEntry(key: path, value: content) in shared.entries) {
      final file = File(p.join(sharedDir.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }
    try {
      await testBuilder(
        _RootPackageOnly(GraphQLCodegenBuilder(
          GraphQLCodegenConfig(
            schemaUrl: schemaUrl,
            outputDir: outDir.path,
            documentPaths: ['lib/graphql/**.graphql'],
          ),
          packageRoots: packageKnown ? {'shared': sharedDir.path} : const {},
        )),
        {
          'a|lib/schema.graphql': _schema,
          ...assets,
          for (final MapEntry(key: path, value: content) in shared.entries)
            'shared|$path': content,
        },
        rootPackage: 'a',
        onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
      );
    } on CodegenException {
      // build_test 2.x rethrows builder errors (3.x only logs them).
    }
  }

  String? output(String name) {
    final file = File(p.join(outDir.path, name));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  Iterable<String> severe() => logs.where((l) => l.startsWith('SEVERE'));

  Map<String, String> sharedPackage({String fragments = _sharedFragments}) => {
        'lib/graphql/fragments.graphql': fragments,
        'lib/graphql/generated/fragments.dart': sharedFragmentsDart(fragments),
      };

  group('types_import', () {
    test('uses the types of another package instead of writing types.dart',
        () async {
      CodegenConfigContext.typesImport = _typesUri;
      await run({
        'a|lib/graphql/a.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { id } }',
        'a|lib/graphql/f.graphql': 'fragment Local on User { name }',
      });
      expect(severe(), isEmpty);
      expect(output('types.dart'), isNull);
      final op = output('get_user_graphql.g.dart')!;
      expect(op, contains("import '$_typesUri';"));
      expect(op, isNot(contains("import 'types.dart';")));
      expect(output('fragments.dart'), contains("import '$_typesUri';"));
      final index = output('index.dart')!;
      expect(index, contains("export '$_typesUri';"));
      expect(index, isNot(contains("export 'types.dart';")));
    });

    test('removes a types.dart generated before', () async {
      await run({'a|lib/graphql/a.graphql': 'query A { version }'});
      expect(output('types.dart'), isNotNull);
      CodegenConfigContext.typesImport = _typesUri;
      await run({'a|lib/graphql/a.graphql': 'query A { version }'});
      expect(output('types.dart'), isNull);
    });

    test('keeps a types.dart it did not generate', () async {
      File(p.join(outDir.path, 'types.dart')).writeAsStringSync('// mine\n');
      CodegenConfigContext.typesImport = _typesUri;
      await run({'a|lib/graphql/a.graphql': 'query A { version }'});
      expect(output('types.dart'), '// mine\n');
    });

    test('works with schema result types', () async {
      CodegenConfigContext.resultTypes = 'schema';
      CodegenConfigContext.typesImport = _typesUri;
      await run({
        'a|lib/graphql/a.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { id } }',
      });
      expect(severe(), isEmpty);
      expect(output('types.dart'), isNull);
      expect(
          output('get_user_graphql.g.dart'), contains("import '$_typesUri';"));
    });
  });

  group('fragment_imports', () {
    setUp(() {
      CodegenConfigContext.typesImport = _typesUri;
      CodegenConfigContext.fragmentImports = [_import];
    });

    test('operations implement imported fragment interfaces', () async {
      await run({
        'a|lib/graphql/a.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { ...UserBits } }',
        'a|lib/graphql/b.graphql': 'query GetVersion { version }',
      }, shared: sharedPackage());
      expect(severe(), isEmpty);
      final op = output('get_user_graphql.g.dart')!;
      expect(op, contains("import '$_fragmentsUri';"));
      expect(op, isNot(contains("import 'fragments.dart';")));
      expect(op, contains('class GetUser_User implements UserBits {'));
      // The document carries the imported fragment's definition.
      expect(op, contains('fragment UserBits on User'));
      expect(
          output('get_version_graphql.g.dart'), isNot(contains(_fragmentsUri)));
      // No local fragments: no fragments.dart.
      expect(output('fragments.dart'), isNull);
      final index = output('index.dart')!;
      expect(index, contains("export '$_fragmentsUri';"));
      expect(index, isNot(contains("export 'fragments.dart';")));
    });

    test(
        'local fragments.dart has only local fragments, which may spread '
        'imported ones', () async {
      await run({
        'a|lib/graphql/f.graphql':
            'fragment WithFriend on User { ...UserBits friend { ...UserBits } }',
        'a|lib/graphql/a.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { ...WithFriend } }',
      }, shared: sharedPackage());
      expect(severe(), isEmpty);
      final fragments = output('fragments.dart')!;
      expect(fragments, contains("import '$_fragmentsUri';"));
      expect(fragments,
          contains('abstract interface class WithFriend implements UserBits'));
      expect(fragments, isNot(contains('abstract interface class UserBits ')));
      expect(fragments, isNot(contains('class UserBitsData')));
      // Its document includes the imported definition.
      expect(fragments, contains('fragment UserBits on User'));
      final op = output('get_user_graphql.g.dart')!;
      expect(op, contains("import 'fragments.dart';"));
      expect(op, contains('fragment UserBits on User'));
      expect(op, contains('fragment WithFriend on User'));
      final index = output('index.dart')!;
      expect(index, contains("export 'fragments.dart';"));
      expect(index, contains("export '$_fragmentsUri';"));
    });

    test('nested interfaces of imported fragments are implemented', () async {
      const shared = 'fragment UserFriend on User { friend { id } }';
      await run({
        'a|lib/graphql/a.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { ...UserFriend } }',
      }, shared: sharedPackage(fragments: shared));
      expect(severe(), isEmpty);
      final op = output('get_user_graphql.g.dart')!;
      expect(op, contains('class GetUser_User implements UserFriend {'));
      expect(op,
          contains('class GetUser_User_Friend implements UserFriend_Friend {'));
    });

    test('a local fragment with the name of an imported one is reported',
        () async {
      await run({
        'a|lib/graphql/f.graphql': 'fragment UserBits on User { id }',
        'a|lib/graphql/a.graphql': 'query A { version }',
      }, shared: sharedPackage());
      expect(
          logs,
          contains(allOf(contains('BLD102'), contains('UserBits'),
              contains(_fragmentsUri))));
    });

    test('operation names clashing with imported declarations are reported',
        () async {
      await run({
        'a|lib/graphql/a.graphql': 'query UserBitsFragment { version }',
      }, shared: sharedPackage());
      expect(
          logs,
          contains(allOf(
            contains('BLD108'),
            contains('"UserBitsFragment"'),
            contains(_fragmentsUri),
          )));
    });

    test('warns when the imported library is not generated yet', () async {
      await run({
        'a|lib/graphql/a.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { ...UserBits } }',
      }, shared: {
        'lib/graphql/fragments.graphql': _sharedFragments
      });
      expect(severe(), isEmpty);
      expect(
          logs,
          contains(allOf(startsWith('WARNING'), contains(_fragmentsUri),
              contains('not found'))));
      expect(output('get_user_graphql.g.dart'),
          contains('class GetUser_User implements UserBits {'));
    });

    test('a package that is not a dependency is reported', () async {
      await run({'a|lib/graphql/a.graphql': 'query A { version }'},
          shared: sharedPackage(), packageKnown: false);
      expect(
          logs,
          contains(allOf(contains('CFG999'), contains('"shared"'),
              contains('not a dependency'))));
    });

    test('schema result types include imported fragment definitions', () async {
      CodegenConfigContext.resultTypes = 'schema';
      await run({
        'a|lib/graphql/a.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { ...UserBits } }',
      }, shared: sharedPackage());
      expect(severe(), isEmpty);
      final op = output('get_user_graphql.g.dart')!;
      expect(op, contains('fragment UserBits on User'));
      expect(op, isNot(contains(_fragmentsUri)));
      expect(output('index.dart'), isNot(contains(_fragmentsUri)));
    });
  });

  test('schema_url may be a package: URI, read through the build step',
      () async {
    await run(
      {'a|lib/graphql/a.graphql': 'query A { version }'},
      shared: {'lib/graphql/schema.graphql': _schema},
      schemaUrl: 'package:shared/graphql/schema.graphql',
    );
    expect(severe(), isEmpty);
    expect(output('a_graphql.g.dart'), isNotNull);
  });

  test('a package: schema_url that cannot be read is reported', () async {
    await run(
      {'a|lib/graphql/a.graphql': 'query A { version }'},
      schemaUrl: 'package:shared/graphql/missing.graphql',
    );
    expect(logs, contains(allOf(contains('SCH404'), contains('missing'))));
  });

  group('config', () {
    GraphQLCodegenConfig parse(String extra) => GraphQLCodegenConfig.fromYaml(
        'schema_url: s.graphql\ndocument_paths: [a.graphql]\n$extra');
    final invalid = throwsA(isA<CodegenException>()
        .having((e) => e.code, 'code', CodegenErrorCodes.cfgInvalid));

    test('parses types_import and fragment_imports', () {
      final config = parse('''
types_import: $_typesUri
fragment_imports:
  - dart: $_fragmentsUri
    documents: "package:shared/graphql/**.graphql"
''');
      expect(config.typesImport, _typesUri);
      expect(config.fragmentImports.single.dart, _fragmentsUri);
      expect(config.fragmentImports.single.documents,
          'package:shared/graphql/**.graphql');
    });

    for (final bad in [
      'lib/graphql/types.dart',
      'package:shared',
      'package:shared/',
      'package:Shared/types.dart',
      'package:shared/../types.dart',
      'package:shared/types.graphql',
      'package:shared/*.dart',
    ]) {
      test('rejects types_import "$bad"', () {
        expect(() => parse('types_import: "$bad"'), invalid);
      });
    }

    for (final (dart, documents) in [
      ('lib/fragments.dart', 'package:shared/**.graphql'),
      (_fragmentsUri, 'lib/graphql/**.graphql'),
      (_fragmentsUri, 'package:shared//x.graphql'),
      ('package:shared/fragments', 'package:shared/**.graphql'),
    ]) {
      test('rejects fragment_imports {dart: $dart, documents: $documents}', () {
        expect(
            () => parse('fragment_imports:\n'
                '  - {dart: "$dart", documents: "$documents"}'),
            invalid);
      });
    }

    test('rejects fragment_imports entries without documents', () {
      expect(() => parse('fragment_imports:\n  - {dart: $_fragmentsUri}'),
          invalid);
    });
  });
}
