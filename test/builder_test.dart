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
      {List<String> warnings = const []}) async {
    try {
      await testBuilder(
        builder(warnings: warnings),
        {'a|lib/schema.graphql': _schema, ...assets},
        rootPackage: 'a',
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
}
