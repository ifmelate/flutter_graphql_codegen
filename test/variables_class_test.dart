// Variables classes: value equality, typed copyWith and explicit nulls.
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/formatting.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const _schema = r'''
input Patch { name: String }
type User { id: ID! }
type Query {
  users(patch: Patch, first: Int, tags: [String!], id: ID!, limit: Int!): [User!]!
}
''';

const _document = r'''
query Users($patch: Patch, $first: Int = 10, $tags: [String!], $id: ID!, $limit: Int! = 3) {
  users(patch: $patch, first: $first, tags: $tags, id: $id, limit: $limit) { id }
}
''';

String _op([String document = _document, String name = 'Users']) {
  final types = GraphQLCodeGenerator.generateTypesFile(_schema);
  return GraphQLCodeGenerator.generateOperationFile(
      _schema, document, name, 'query', types);
}

void main() {
  late String code;

  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
    code = _op();
  });
  tearDown(CodegenConfigContext.reset);

  test('the const constructor is unchanged, flags start false', () {
    expect(code, contains('  const UsersVariables({\n    this.patch,\n'));
    expect(code, contains('    required this.id,\n'));
    expect(code, contains('  }) : _patchIsNull = false,'));
  });

  test('flags only for variables of a nullable GraphQL type', () {
    expect(code, contains('  final bool _patchIsNull;'));
    expect(code, contains('  final bool _firstIsNull;'));
    expect(code, contains('  final bool _tagsIsNull;'));
    expect(code, isNot(contains('_limitIsNull')), reason: r'$limit: Int!');
    expect(code, isNot(contains('_idIsNull')));
  });

  test('withNulls is a const factory with the typed variables', () {
    expect(code, contains('  const factory UsersVariables.withNulls({'));
    expect(code, contains('    Patch? patch,\n'));
    expect(code, contains('    required String id,\n'));
    expect(code, contains('  }) = UsersVariables._withNulls;'));
  });

  test('toJson sends an explicit null, leaves out absent variables', () {
    expect(
        code,
        contains("        if (first != null) 'first': first "
            "else if (_firstIsNull) 'first': null,"));
    expect(code, contains("        if (limit != null) 'limit': limit,"));
  });

  test('== and hashCode, deep for lists, with the flags', () {
    expect(code, contains('  bool operator ==(Object other) =>'));
    expect(code, contains('graphqlDeepEquals(tags, other.tags)'));
    expect(code, contains('          _firstIsNull == other._firstIsNull'));
    expect(code, contains('        graphqlDeepHash(tags),'));
    expect(code, contains('        _firstIsNull,\n'));
  });

  test('typed copyWith', () {
    expect(
        code,
        contains('  UsersVariables_CopyWith get copyWith => '
            '_UsersVariables_CopyWith(this);'));
    expect(code, contains('abstract class UsersVariables_CopyWith {'));
    expect(code, contains('    String? id,\n'));
    expect(
        code,
        contains('first: identical(first, _undefined) ? (_value._firstIsNull '
            '? null : _value.first ?? _undefined) : first,'));
    expect(code,
        contains('id: identical(id, _undefined) ? _value.id : id as String,'));
    expect(
        code,
        contains('limit: identical(limit, _undefined) ? '
            '_value.limit : limit as int?,'));
  });

  test('_undefined is declared once, also next to result classes', () {
    expect('const _undefined = Object();'.allMatches(code), hasLength(1));
    CodegenConfigContext.resultTypes = 'schema';
    final schemaMode = _op();
    expect('const _undefined = Object();'.allMatches(schemaMode), hasLength(1));
    expect(schemaMode, contains('UsersVariables.withNulls'));
  });

  test('include_null_inputs: only variables with a default get a flag', () {
    CodegenConfigContext.includeNullInputs = true;
    final out = _op();
    expect(out, contains('  final bool _firstIsNull;'));
    expect(out, isNot(contains('_patchIsNull')));
    expect(out, contains("        'patch': patch == null ? null : "));
  });

  test('include_null_inputs without defaults: withNulls is the constructor',
      () {
    CodegenConfigContext.includeNullInputs = true;
    final out = _op(
        r'query U($first: Int) { users(first: $first, id: "1", '
            'limit: 1) { id } }',
        'U');
    expect(out, isNot(contains('IsNull')));
    expect(out, contains('  }) = UVariables;'));
    expect(out, contains('UVariables_CopyWith get copyWith'));
  });

  test('only non-null variables: no withNulls, copyWith remains', () {
    final out =
        _op(r'query U($id: ID!) { users(id: $id, limit: 1) { id } }', 'U');
    expect(out, isNot(contains('withNulls')));
    expect(out, contains('UVariables_CopyWith get copyWith'));
    expect(out, contains('          id == other.id;'));
  });

  test('dart format accepts the code for Dart 3.0 packages', () {
    final version = Version(3, 0, 0);
    expect(() => formatGeneratedCode(code, languageVersion: version),
        returnsNormally);
    final types = GraphQLCodeGenerator.generateTypesFile(_schema);
    expect(() => formatGeneratedCode(types, languageVersion: version),
        returnsNormally);
  });

  test('variables named copyWith, identical or other', () {
    const schema = r'''
type Query { a(copyWith: Int, identical: Int, other: Int): Int }
''';
    final types = GraphQLCodeGenerator.generateTypesFile(schema);
    final out = GraphQLCodeGenerator.generateOperationFile(
        schema,
        r'query A($copyWith: Int, $identical: Int, $other: Int) '
            r'{ a(copyWith: $copyWith, identical: $identical, other: $other) }',
        'A',
        'query',
        types);
    expect(out, isNot(contains('AVariables_CopyWith')));
    expect(out, isNot(contains('withNulls')));
    expect(out, contains('  bool operator ==(Object other_) =>'));
    expect(out, isNot(contains('identical(this, other_)')));
  });
}
