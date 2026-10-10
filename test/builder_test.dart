import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:flutter_graphql_codegen/src/builder.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
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

  GraphQLCodegenBuilder builder() => GraphQLCodegenBuilder(
        GraphQLCodegenConfig(
          // Not present on disk: must be read through the BuildStep.
          schemaUrl: 'lib/schema.graphql',
          outputDir: outDir.path,
          documentPaths: ['lib/graphql/**.graphql'],
        ),
      );

  Future<void> run(Map<String, String> assets) => testBuilder(
        builder(),
        {'a|lib/schema.graphql': _schema, ...assets},
        rootPackage: 'a',
        onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
      );

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

  test('skips schema and fragment-only documents', () async {
    await run({
      'a|lib/graphql/fragments.graphql': 'fragment UserBits on User { id }',
    });
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    expect(output('types.dart'), isNull);
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
}
