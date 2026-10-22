// Problems found by running generated code against public GraphQL APIs.
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

const _schema = r'''
scalar Duration

enum Sort { NEWEST OLDEST }

input Filter { name: String tags: [String!] ids: [ID!]! }

type Item { id: ID! name: String! parts: [String!]! timeout: Duration }

type Query {
  items(filter: Filter, first: Int, after: String, sort: Sort): [Item!]!
}
''';

const _document = r'''
query Items(
  $filter: Filter = {name: "it's", tags: ["a"], ids: []}
  $first: Int = 3
  $sort: Sort = NEWEST
  $full: Boolean = false
  $after: String
) {
  items(filter: $filter, first: $first, after: $after, sort: $sort) {
    id
    parts @include(if: $full)
  }
}
''';

String _op() {
  final types = TypeGenerator.generateTypesFile(_schema);
  return GraphQLCodeGenerator.generateOperationFile(
      _schema, _document, 'Items', 'query', types);
}

void main() {
  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
  });
  tearDown(CodegenConfigContext.reset);

  group('variables with a default value', () {
    // The normalized cache doesn't apply defaults, so a left-out variable
    // used by @include made it expect fields the server didn't send.
    test('are sent with their default when not given', () {
      // An explicit null (withNulls, copyWith) still replaces the default.
      final code = _op();
      expect(code, contains("'first': first ?? (_firstIsNull ? null : 3),"));
      expect(code,
          contains("'sort': sort == null ? (_sortIsNull ? null : 'NEWEST') :"));
      expect(code, contains("'full': full ?? (_fullIsNull ? null : false),"));
      expect(
          code,
          contains("'filter': filter == null ? (_filterIsNull ? null : "
              "<String, dynamic>{'name': 'it\\'s', 'tags': <dynamic>['a'], "
              "'ids': <dynamic>[]})"));
    });

    test('without a default are still left out when null', () {
      expect(_op(), contains("if (after != null) 'after': after else"));
    });

    test('with include_null_inputs too', () {
      CodegenConfigContext.includeNullInputs = true;
      final code = _op();
      expect(code, contains("'full': full ?? (_fullIsNull ? null : false),"));
      expect(code, contains("'after': after,"));
    });
  });

  group('nullable input lists', () {
    // `[]` sent for a filter list means "none of these".
    test('default to null in operation mode', () {
      final types = TypeGenerator.generateTypesFile(_schema);
      expect(types, contains('    this.tags,'));
      expect(types, contains('    this.ids = const [],'));
    });

    test('default to null in schema mode', () {
      CodegenConfigContext.resultTypes = 'schema';
      final types = TypeGenerator.generateTypesFile(_schema);
      final filter = types.substring(types.indexOf('class Filter '));
      final ctor = filter.substring(0, filter.indexOf('});'));
      expect(ctor, contains('    this.tags,'));
      expect(ctor, contains('    this.ids = const [],'));
      // Result lists keep their empty default.
      final item = types.substring(types.indexOf('class Item '));
      expect(item.substring(0, item.indexOf('});')),
          contains('    this.parts = const [],'));
    });
  });

  test('a schema scalar named Duration does not hide dart:core Duration', () {
    final types = TypeGenerator.generateTypesFile(_schema);
    expect(types, contains('class Duration_ {'));
    expect(types, isNot(contains('class Duration {')));
    expect(_op(), contains('Duration? pollInterval'));
  });
}
