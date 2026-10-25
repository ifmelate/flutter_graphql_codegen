// prune_types: types.dart declares only what operations and fragments use.
import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:flutter_graphql_codegen/src/builder.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _schema = r'''
scalar Money
scalar Unused
scalar Stamp

enum Role { ADMIN USER }
enum Sort { NEWEST OLDEST }
enum Level { LOW HIGH }
enum Lonely { A B }

input Page { first: Int after: String sort: Sort }
input Filter { name: String page: Page levels: [Level!] }
input Forgotten { lonely: Lonely }

interface Node { id: ID! }
interface Named { name: String }
union Hit = User | Post
union Nobody = User

type User implements Node & Named {
  id: ID! name: String role: Role! balance: Money created: Stamp
}
type Post implements Node { id: ID! title: String }

type Query {
  users(filter: Filter): [User!]!
  search: [Hit!]!
  node(id: ID!): Node
  forgotten(input: Forgotten): Boolean
}
''';

const _documents = [
  r'''
query Users($filter: Filter) { users(filter: $filter) { id role ...Money } }
''',
  r'''
fragment Money on User { balance }
query Search { search { ... on Post { title } ... on Named { name } } }
''',
];

void main() {
  setUp(CodegenConfigContext.reset);
  tearDown(CodegenConfigContext.reset);

  group('usedTypes', () {
    final used = GraphQLCodeGenerator.usedTypes(_schema, _documents);

    test('has enums and scalars of selected fields, also in fragments', () {
      expect(used, containsAll(['Role', 'Money']));
    });

    test('has variable types with everything their fields reach', () {
      expect(used, containsAll(['Filter', 'Page', 'Sort', 'Level']));
    });

    test('has abstract types that are selected or used as a condition', () {
      expect(used, containsAll(['Hit', 'Named']));
    });

    test('leaves out what no operation or fragment uses', () {
      expect(
          used,
          isNot(anyOf(contains('Unused'), contains('Stamp'), contains('Lonely'),
              contains('Forgotten'), contains('Nobody'), contains('Node'))));
    });
  });

  group('generateTypesFile(only:)', () {
    late String types;
    setUp(() {
      types = GraphQLCodeGenerator.generateTypesFile(_schema,
          only: GraphQLCodeGenerator.usedTypes(_schema, _documents));
    });

    test('declares the used types', () {
      expect(types, contains('enum Role {'));
      expect(types, contains('class RoleConverter '));
      expect(types, contains('class Filter {'));
      expect(types, contains('class Page {'));
      expect(types, contains('enum Sort {'));
      expect(types, contains('class Money {'));
      expect(types, contains("'Hit': {'Post', 'User'},"));
    });

    test('leaves out the unused ones', () {
      expect(types, isNot(contains('Lonely')));
      expect(types, isNot(contains('class Forgotten')));
      expect(types, isNot(contains('class Unused')));
      expect(types, isNot(contains('class Stamp')));
      expect(types, isNot(contains("'Nobody'")));
      expect(types, isNot(contains("'Node'")));
    });

    test('keeps the built-in helpers', () {
      expect(types, contains('class SafeIntConverter '));
      expect(types, contains('bool graphqlDeepEquals('));
    });

    test('is ignored with result_types: schema', () {
      CodegenConfigContext.resultTypes = 'schema';
      final schemaTypes =
          GraphQLCodeGenerator.generateTypesFile(_schema, only: const {});
      expect(schemaTypes, contains('enum Lonely {'));
      expect(schemaTypes, contains('class Forgotten {'));
    });
  });

  group('config', () {
    GraphQLCodegenConfig parse(String extra) => GraphQLCodegenConfig.fromYaml(
        'schema_url: s.graphql\ndocument_paths: [a.graphql]\n$extra');

    test('prune_types is off by default', () {
      expect(parse('').pruneTypes, isFalse);
      expect(parse('prune_types: true').pruneTypes, isTrue);
      expect(parse('prune_types: true').warnings, isEmpty);
    });

    test('warns where it has no effect', () {
      expect(parse('prune_types: true\nresult_types: schema').warnings,
          [contains('only applies to result_types: operation')]);
      expect(
          parse('prune_types: true\n'
                  'types_import: package:shared/types.dart')
              .warnings,
          [contains('writes no types.dart')]);
    });
  });

  group('builder', () {
    late Directory outDir;
    setUp(() async {
      outDir = await Directory.systemTemp.createTemp('fgc_prune_');
    });
    tearDown(() async => outDir.delete(recursive: true));

    Future<String> build(Map<String, String> documents) async {
      CodegenConfigContext.pruneTypes = true;
      final logs = <String>[];
      try {
        await testBuilder(
          GraphQLCodegenBuilder(GraphQLCodegenConfig(
            schemaUrl: 'lib/schema.graphql',
            outputDir: outDir.path,
            documentPaths: ['lib/graphql/**.graphql'],
            pruneTypes: true,
          )),
          {'a|lib/schema.graphql': _schema, ...documents},
          rootPackage: 'a',
          onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
        );
      } on CodegenException {
        // Logged as SEVERE; checked below.
      }
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
      return File(p.join(outDir.path, 'types.dart')).readAsStringSync();
    }

    test('types.dart covers the operations of every document', () async {
      final types = await build({
        'a|lib/graphql/users.graphql': _documents[0],
        'a|lib/graphql/search.graphql': _documents[1],
      });
      // From users.graphql.
      expect(types, contains('class Filter {'));
      expect(types, contains('enum Role {'));
      // From the fragment in search.graphql, spread in users.graphql.
      expect(types, contains('class Money {'));
      // From search.graphql.
      expect(types, contains("'Hit': {"));
      expect(types, isNot(contains('Lonely')));
    });

    test('a new operation adds its types', () async {
      final types = await build({
        'a|lib/graphql/users.graphql': _documents[0],
        'a|lib/graphql/search.graphql': _documents[1],
        'a|lib/graphql/forgotten.graphql':
            r'query Forgotten($input: Forgotten) { forgotten(input: $input) }',
      });
      expect(types, contains('class Forgotten {'));
      expect(types, contains('enum Lonely {'));
    });
  });
}
