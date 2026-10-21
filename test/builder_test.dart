import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:dart_style/dart_style.dart';
import 'package:flutter_graphql_codegen/src/builder.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _schema = r'''
type Query { user(id: ID!): User  version: String }
type Mutation { rename(id: ID!, name: String!): User }
type User { id: ID! name: String }
''';

void main() {
  late Directory outDir;
  late List<String> logs;

  setUp(() async {
    CodegenConfigContext.reset();
    outDir = await Directory.systemTemp.createTemp('fgc_builder_');
    logs = [];
  });

  tearDown(() async {
    CodegenConfigContext.reset();
    await outDir.delete(recursive: true);
  });

  GraphQLCodegenBuilder builder({List<String> warnings = const []}) =>
      GraphQLCodegenBuilder(
        GraphQLCodegenConfig(
          // Not present on disk: must be read through the BuildStep.
          schemaUrl: 'lib/schema.graphql',
          outputDir: outDir.path,
          documentPaths: ['lib/graphql/**.graphql'],
          warnings: warnings,
        ),
      );

  Future<void> run(Map<String, String> assets,
      {List<String> warnings = const [], Set<String>? generateFor}) async {
    try {
      await testBuilder(
        builder(warnings: warnings),
        {'a|lib/schema.graphql': _schema, ...assets},
        rootPackage: 'a',
        generateFor: generateFor,
        onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
      );
    } on CodegenException {
      // build_test 2.x rethrows builder errors (3.x only logs them); the
      // builder logs them as SEVERE before throwing either way.
    }
  }

  String? output(String name) {
    final file = File(p.join(outDir.path, name));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  test('generates every operation of a document, using external fragments',
      () async {
    CodegenConfigContext.resultTypes = 'schema';
    await run({
      'a|lib/graphql/fragments.graphql':
          'fragment UserBits on User { id name }',
      'a|lib/graphql/get_schema_info.graphql': r'''
query GetUser($id: ID!) { user(id: $id) { ...UserBits } }
mutation Rename($id: ID!, $name: String!) { rename(id: $id, name: $name) { id } }
query GetVersion { version }
''',
    });

    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    expect(output('types.dart'), contains('class User {'));

    final getUser = output('get_user_graphql.g.dart');
    expect(getUser, isNotNull);
    expect(getUser, contains('fragment UserBits on User'));
    expect(getUser, isNot(contains('mutation Rename')));
    expect(
        output('rename_graphql.g.dart'), contains('graphql.MutationOptions'));
    // Previously any path containing "schema.graphql" was skipped.
    expect(output('get_version_graphql.g.dart'), isNotNull);

    final index = output('index.dart')!;
    expect(index, contains("export 'get_user_graphql.g.dart';"));
    expect(index, contains("export 'rename_graphql.g.dart';"));
  });

  test('operation result types: types.dart keeps inputs, no result classes',
      () async {
    await run({
      'a|lib/schema.graphql': '$_schema\ninput UserFilter { name: String }',
      'a|lib/graphql/a.graphql': 'query GetVersion { version }',
    });
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    final types = output('types.dart')!;
    expect(types, isNot(contains('class User ')));
    expect(types, contains('class UserFilter {'));
    expect(types, isNot(contains('@JsonSerializable')));
    expect(types, isNot(contains('types.g.dart')));
  });

  test('writes dart-formatted files', () async {
    await run({
      'a|lib/graphql/a.graphql': r'''
query GetUser($id: ID!) { user(id: $id) { id name } }
''',
    });
    final formatter =
        DartFormatter(languageVersion: DartFormatter.latestLanguageVersion);
    for (final name in [
      'types.dart',
      'get_user_graphql.g.dart',
      'index.dart',
    ]) {
      final code = output(name)!;
      expect(formatter.format(code), code, reason: '$name is not formatted');
    }
  });

  test('skips schema and fragment-only documents', () async {
    CodegenConfigContext.resultTypes = 'schema';
    await run({
      'a|lib/graphql/fragments.graphql': 'fragment UserBits on User { id }',
    });
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    expect(output('types.dart'), isNull);
    expect(output('fragments.dart'), isNull);
  });

  test('schema result types write no fragments.dart', () async {
    CodegenConfigContext.resultTypes = 'schema';
    await run({
      'a|lib/graphql/fragments.graphql': 'fragment UserBits on User { id }',
      'a|lib/graphql/a.graphql':
          r'query GetUser($id: ID!) { user(id: $id) { ...UserBits } }',
    });
    expect(output('get_user_graphql.g.dart'), isNot(contains('fragments')));
    expect(output('fragments.dart'), isNull);
    expect(output('index.dart'), isNot(contains('fragments.dart')));
  });

  test('fragment-only documents write fragments.dart', () async {
    await run({
      'a|lib/graphql/fragments.graphql': 'fragment UserBits on User { id }',
    });
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    final fragments = output('fragments.dart')!;
    expect(fragments, contains('abstract interface class UserBits {'));
    expect(fragments, contains('class UserBitsData implements UserBits {'));
    expect(fragments, contains('final userBitsFragment = graphql.gql('));
    expect(output('index.dart'), contains("export 'fragments.dart';"));
  });

  test('fragments.dart follows fragment changes, operations import it',
      () async {
    const operation =
        r'query GetUser($id: ID!) { user(id: $id) { ...UserBits } }';
    const other = 'query GetVersion { version }';
    await run({
      'a|lib/graphql/fragments.graphql': 'fragment UserBits on User { id }',
      'a|lib/graphql/a.graphql': operation,
      'a|lib/graphql/b.graphql': other,
    });
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    final getUser = output('get_user_graphql.g.dart')!;
    expect(getUser, contains("import 'fragments.dart';"));
    expect(getUser, contains('class GetUser_User implements UserBits {'));
    expect(output('get_version_graphql.g.dart'),
        isNot(contains("import 'fragments.dart';")));
    expect(output('index.dart'), contains("export 'fragments.dart';"));

    await run({
      'a|lib/graphql/fragments.graphql':
          'fragment UserBits on User { id name }',
      'a|lib/graphql/a.graphql': operation,
      'a|lib/graphql/b.graphql': other,
    });
    expect(output('fragments.dart'), contains('String? get name;'));
    expect(output('get_user_graphql.g.dart'), contains('final String? name;'));
  });

  test('warns about anonymous operations', () async {
    await run({'a|lib/graphql/anon.graphql': '{ version }'});
    expect(logs, contains(contains('Skipping anonymous query')));
  });

  test('reports unknown fragments with an error code', () async {
    await run({
      'a|lib/graphql/broken.graphql':
          'query Broken { user(id: 1) { ...Nope } }',
    });
    expect(logs, contains(allOf(contains('BLD101'), contains('Nope'))));
  });

  test('reports unknown root fields with an error code', () async {
    await run({'a|lib/graphql/broken.graphql': 'query Broken { nope }'});
    expect(logs, contains(allOf(contains('BLD103'), contains('nope'))));
  });

  test('index.dart import hint uses the package URI of output_dir', () {
    expect(GraphQLCodegenBuilder.packageImportOf('app', 'lib/graphql/gen'),
        'package:app/graphql/gen/index.dart');
    expect(GraphQLCodegenBuilder.packageImportOf('app', './lib/gen/'),
        'package:app/gen/index.dart');
    expect(GraphQLCodegenBuilder.packageImportOf('app', 'generated'), isNull);
  });

  test('index.dart has no made-up usage example', () async {
    await run({'a|lib/graphql/a.graphql': 'query A { version }'});
    final index = output('index.dart')!;
    expect(index, isNot(contains('your_app')));
    expect(index, isNot(contains('getUserProfile')));
  });

  test('logs config warnings', () async {
    await run({
      'a|lib/graphql/a.graphql': 'query A { version }',
      'a|lib/graphql/b.graphql': 'query B { version }',
    }, warnings: [
      'Unknown option "x"'
    ]);
    // Only presence is checked: how often build_test hands a record to onLog
    // differs between environments (CI delivered it once per input).
    expect(logs,
        contains(allOf(startsWith('WARNING'), contains('Unknown option "x"'))));
  });

  group('duplicate operations', () {
    Matcher duplicateError(String name) =>
        contains(allOf(contains('BLD104'), contains(name)));

    test('in two documents are reported with both paths', () async {
      await run({
        'a|lib/graphql/a.graphql': 'query GetVersion { version }',
        'a|lib/graphql/b.graphql': 'query GetVersion { version }',
      });
      expect(
          logs,
          contains(allOf(
            contains('BLD104'),
            contains('lib/graphql/a.graphql'),
            contains('lib/graphql/b.graphql'),
          )));
    });

    test('in one document are reported', () async {
      await run({
        'a|lib/graphql/a.graphql':
            'query GetVersion { version }\nquery GetVersion { version }',
      });
      expect(logs, duplicateError('GetVersion'));
    });

    test('whose names map to the same file are reported', () async {
      await run({
        'a|lib/graphql/a.graphql': 'query GetVersion { version }',
        'a|lib/graphql/b.graphql': 'query getVersion { version }',
      });
      expect(logs, duplicateError('get_version_graphql.g.dart'));
    });

    test('are not reported when a document is regenerated', () async {
      await run({'a|lib/graphql/a.graphql': 'query GetVersion { version }'});
      await run({'a|lib/graphql/a.graphql': 'query GetVersion { version }'});
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    });

    test('are not reported when an operation moved to another document',
        () async {
      await run({'a|lib/graphql/a.graphql': 'query GetVersion { version }'});
      await run({
        'a|lib/graphql/a.graphql': 'query Other { version }',
        'a|lib/graphql/b.graphql': 'query GetVersion { version }',
      });
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    });
  });

  group('names declared by two files', () {
    const schema = '''
type User { id: ID! }
type Thing { c: User }
type Query { b: Thing c: User version: String }
''';
    // Operation A_B field c and operation A path b.c are both A_B_C.
    const ab = 'query A_B { c { id } }';
    const a = 'query A { b { c { id } } }';
    bool severe(String l) => l.startsWith('SEVERE');

    test('in two documents are reported with both operations', () async {
      await run({
        'a|lib/schema.graphql': schema,
        'a|lib/graphql/a.graphql': a,
        'a|lib/graphql/b.graphql': ab,
      });
      expect(
          logs,
          contains(allOf(
            contains('BLD108'),
            contains('"A"'),
            contains('"A_B"'),
            contains('"A_B_C"'),
            contains('lib/graphql/a.graphql'),
            contains('lib/graphql/b.graphql'),
          )));
    });

    test('in one document are reported', () async {
      await run({
        'a|lib/schema.graphql': schema,
        'a|lib/graphql/a.graphql': '$a\n$ab',
      });
      expect(
          logs,
          contains(allOf(
              contains('BLD108'), contains('"A_B_C"'), contains('"A_B"'))));
    });

    test('are found in files of an earlier build', () async {
      await run({'a|lib/schema.graphql': schema, 'a|lib/graphql/a.graphql': a});
      expect(logs.where(severe), isEmpty);
      // A new builder, as in the next `build_runner build`, that only
      // builds b.graphql: A's file is only on disk.
      await run({
        'a|lib/schema.graphql': schema,
        'a|lib/graphql/a.graphql': a,
        'a|lib/graphql/b.graphql': ab,
      }, generateFor: {
        'a|lib/graphql/b.graphql'
      });
      expect(logs, contains(allOf(contains('BLD108'), contains('"A_B_C"'))));
    });

    test('of an operation no longer defined are not reported', () async {
      await run({'a|lib/schema.graphql': schema, 'a|lib/graphql/a.graphql': a});
      // A's file stays on disk (a.graphql is not rebuilt here), but A is
      // gone from a.graphql.
      await run({
        'a|lib/schema.graphql': schema,
        'a|lib/graphql/a.graphql': 'query Other { version }',
        'a|lib/graphql/b.graphql': ab,
      }, generateFor: {
        'a|lib/graphql/b.graphql'
      });
      expect(logs.where(severe), isEmpty);
      final generated = outDir
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .where((code) => code.contains('// Operation: A_B (query)'));
      expect(generated.single, contains('class A_B_C {'));
    });

    test('by an operation and fragments.dart are reported', () async {
      await run({
        'a|lib/graphql/fragments.graphql': 'fragment UserBits on User { id }',
        'a|lib/graphql/a.graphql': 'query UserBitsFragment { version }',
      });
      expect(
          logs,
          contains(allOf(
            contains('BLD108'),
            contains('"UserBitsFragment"'),
            contains('"UserBitsFragmentExtension"'),
            contains('fragments.dart'),
          )));
    });

    test('of Flutter widgets are reported', () async {
      CodegenConfigContext.flutterWidgets = true;
      // Both get the widget GetVersionQuery.
      await run({
        'a|lib/graphql/a.graphql': 'query GetVersion { version }',
        'a|lib/graphql/b.graphql': 'query GetVersionQuery { version }',
      });
      expect(logs,
          contains(allOf(contains('BLD108'), contains('"GetVersionQuery"'))));
    });
  });

  group('flutter_widgets and flutter_hooks', () {
    test('add widgets and hooks to the operation files', () async {
      CodegenConfigContext.flutterWidgets = true;
      CodegenConfigContext.flutterHooks = true;
      await run({
        'a|lib/graphql/a.graphql': r'''
query GetUser($id: ID!) { user(id: $id) { id } }
mutation Rename($id: ID!, $name: String!) { rename(id: $id, name: $name) { id } }
''',
      });
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
      final getUser = output('get_user_graphql.g.dart')!;
      expect(getUser,
          contains("import 'package:flutter/widgets.dart' as widgets;"));
      expect(getUser,
          contains('class GetUserQuery extends widgets.StatelessWidget {'));
      expect(getUser, contains('useGetUserQuery('));
      final rename = output('rename_graphql.g.dart')!;
      expect(rename,
          contains('class RenameMutation extends widgets.StatelessWidget {'));
      expect(rename, contains('useRenameMutation('));
    });

    test('are off by default', () async {
      await run({'a|lib/graphql/a.graphql': 'query GetVersion { version }'});
      expect(output('get_version_graphql.g.dart'),
          isNot(contains('graphql_flutter')));
    });
  });
}
