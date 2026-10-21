import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/declarations.dart';
import 'package:flutter_graphql_codegen/src/formatting.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:test/test.dart';

const _schema = '''
type User { id: ID! name: String }
type Query { user(id: ID!): User users: [User!]! }
''';

String _op(String document, String name) {
  final types = GraphQLCodeGenerator.generateTypesFile(_schema);
  return GraphQLCodeGenerator.generateOperationFile(
      _schema, document, name, 'query', types);
}

void main() {
  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
  });
  tearDown(CodegenConfigContext.reset);

  test('lists the public top-level names of an operation file', () {
    final code =
        _op(r'query GetUser($id: ID!) { user(id: $id) { id } }', 'GetUser');
    expect(topLevelDeclarations(code).toSet(), {
      'getUserDocument', 'getUserOperationName', 'GetUserVariables', //
      'parseGetUserData', 'GetUser_User', 'GetUser_User_CopyWith',
      'getUserQueryOptions', 'getUserWatchQueryOptions',
      'GetUserExtension',
    });
  });

  test('ignores the embedded document and private names', () {
    final names =
        topLevelDeclarations(_op('query Users { users { id name } }', 'Users'));
    // `query Users {` starts at column 0 inside the document string.
    expect(names, isNot(contains('Users')));
    expect(names.where((n) => n.startsWith('_')), isEmpty);
  });

  test('finds the same names after dart format', () {
    // A long name makes the formatter wrap function signatures.
    const name = 'GetTheCurrentlySignedInUserWithAVeryLongOperationName';
    final code = _op('query $name { users { id name } }', name);
    final formatted = formatGeneratedCode(code);
    expect(formatted, contains('graphql.QueryOptions<\n'));
    expect(topLevelDeclarations(formatted), topLevelDeclarations(code));
  });
}
