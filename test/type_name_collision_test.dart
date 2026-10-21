import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

// Schema types named like identifiers the generated code uses (dart:core,
// json_annotation, built-in helpers) get a trailing underscore in Dart.
const _schema = r'''
scalar Object
type Map { key: String! }
type Decimal { amount: String! }
type User { id: ID! }
union Set = Map | User
enum Future { NOW LATER }
input Stream { from: Future }
type Query {
  map: Map
  maps(filter: Stream): [Map!]!
  obj: Object
  objs: [Object!]!
  set: Set
  when: Future
  user: User
}
''';

void main() {
  late String types;

  setUpAll(() {
    CodegenConfigContext.reset();
    // Covers the json_serializable classes of `result_types: schema`.
    CodegenConfigContext.resultTypes = 'schema';
    types = TypeGenerator.generateTypesFile(_schema);
  });

  test('object, input, enum and union types are escaped', () {
    expect(types, contains('class Map_ implements Set_ {'));
    expect(types, contains('factory Map_.fromJson('));
    expect(types, contains('class Decimal_ {'));
    expect(types, contains('abstract class Set_ {'));
    expect(types, contains('class UnknownSet implements Set_ {'));
    expect(types, contains('enum Future_ {'));
    expect(types, contains('class Future_Converter '));
    expect(types, contains('class Stream_ {'));
  });

  test('fields refer to the escaped names', () {
    expect(types, contains('  Map_? map;'));
    expect(types, contains('  Set_? set;'));
    expect(types, contains('  @Future_Converter()\n  Future_? when;'));
    expect(types, contains('  @Future_Converter()\n  Future_? from;'));
  });

  test('custom scalar wrappers are escaped', () {
    expect(types, contains('class Object_ {'));
    expect(types, contains('class Object_Converter '));
    expect(types, contains('  @_NullableObject_Converter()\n  Object_? obj;'));
    expect(types, contains('  @Object_Converter()\n  List<Object_>'));
  });

  test('__typename dispatch and possibleTypes keep the GraphQL names', () {
    expect(types, contains("case 'Map':\n        return Map_.fromJson(json);"));
    expect(types, contains("'Set': {'Map', 'User'},"));
  });

  test('ordinary names are left alone', () {
    expect(types, contains('class User implements Set_ {'));
  });

  test('built-in scalars are not escaped', () {
    final out = TypeGenerator.generateTypesFile('''
scalar Decimal
scalar Long
type Price { value: Decimal! cents: Long }
type Query { price: Price }
''');
    expect(out, contains('class Decimal {'));
    expect(out, contains('  @SafeDecimalConverter()\n  Decimal value;'));
    expect(out, contains('  @_NullableLongConverter()\n  Long? cents;'));
    expect(out, isNot(contains('Decimal_')));
  });

  test('operation files use the escaped names', () {
    CodegenConfigContext.resultTypes = 'schema';
    addTearDown(() => CodegenConfigContext.resultTypes = 'operation');
    final code = GraphQLCodeGenerator.generateOperationFile(
        _schema,
        r'query GetMap($f: Stream) { maps(filter: $f) { key } when }',
        'GetMap',
        'query',
        types);
    expect(code, contains('final Stream_? f;'));
    expect(code, contains('Map_.fromJson('));
    expect(code, contains('const Future_Converter().fromJson('));
  });

  test('operation classes use the escaped names of types.dart', () {
    final code = GraphQLCodeGenerator.generateOperationFile(
        _schema,
        r'query GetMap($f: Stream) { maps(filter: $f) { key } when }',
        'GetMap',
        'query',
        types);
    expect(code, contains('final Stream_? f;'));
    expect(code, contains('GetMap_Maps.fromJson('));
    expect(code, contains('const Future_Converter().fromJson('));
    expect(code, contains('final Future_? when;'));
  });

  test('fragments named like types of types.dart get a trailing _', () {
    final fragments = {
      for (final d in gql_lang
          .parseString(
              'fragment Future on Map { key }\nfragment Enum on Map { key }\n'
              'fragment Bits on Map { key }')
          .definitions
          .whereType<FragmentDefinitionNode>())
        d.name.value: d,
    };
    final code =
        GraphQLCodeGenerator.generateFragmentsFile(_schema, fragments)!;
    // The enum Future is already Future_ in Dart.
    expect(code, contains('abstract interface class Future__ {'));
    expect(code, contains('abstract interface class Enum_ {'));
    expect(code, contains('class Future__Data implements Future__ {'));
    expect(code, contains('abstract interface class Bits {'));
  });
}
