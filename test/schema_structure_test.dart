import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

Matcher _invalid(List<String> parts) => throwsA(isA<CodegenException>()
    .having((e) => e.code, 'code', CodegenErrorCodes.schemaInvalidStructure)
    .having((e) => e.message, 'message', allOf(parts.map(contains).toList())));

void main() {
  setUp(CodegenConfigContext.reset);

  test('empty types are reported together', () {
    expect(
      () => TypeGenerator.generateTypesFile('''
type Query { a: Int }
type Mutation {}
interface Node {}
input Filter {}
enum Empty
'''),
      _invalid([
        'Mutation: an object type needs at least one field',
        'Node: an interface needs at least one field',
        'Filter: an input type needs at least one field',
        'Empty: an enum needs at least one value',
      ]),
    );
  });

  test('a type that implements an interface twice is reported', () {
    expect(
      () => TypeGenerator.generateTypesFile('''
interface Node { id: ID! }
type User implements Node & Node { id: ID! }
type Query { user: User }
'''),
      _invalid(['User: implements Node more than once']),
    );
  });

  test('fields added by extensions count', () {
    expect(
      TypeGenerator.generateTypesFile('''
type Query
extend type Query { a: Int }
'''),
      contains('class Query'),
    );
  });
}
