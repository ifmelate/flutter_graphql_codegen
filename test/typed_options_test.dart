import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

const _schema = r'''
type User { id: ID! name: String }
type Query { user(id: ID!): User  users(first: Int): [User!]!  version: String }
type Mutation { rename(id: ID!, name: String!): User }
type Subscription { userChanged: User! }
''';

String _generate(String document, String name, String type) {
  final types = TypeGenerator.generateTypesFile(_schema);
  return GraphQLCodeGenerator.generateOperationFile(
      _schema, document, name, type, types);
}

void main() {
  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
  });
  tearDown(CodegenConfigContext.reset);

  group('queries', () {
    late String code;
    setUp(() => code = _generate(
        r'query GetUser($id: ID!) { user(id: $id) { id name } }',
        'GetUser',
        'query'));

    test('get typed QueryOptions with required variables', () {
      expect(
          code,
          contains('graphql.QueryOptions<User?> getUserQueryOptions(\n'
              '  GetUserVariables variables, {\n'));
      expect(code, contains('  graphql.FetchPolicy? fetchPolicy,\n'));
      expect(code, contains('  Duration? pollInterval,\n'));
      expect(code, contains('    variables: variables.toJson(),\n'));
      expect(code, contains('    parserFn: parseGetUserData,\n'));
    });

    test('get typed WatchQueryOptions', () {
      expect(
          code,
          contains(
              'graphql.WatchQueryOptions<User?> getUserWatchQueryOptions(\n'
              '  GetUserVariables variables, {\n'));
      expect(code, contains('  bool fetchResults = false,\n'));
    });

    test('get typed cache helpers', () {
      expect(
          code,
          contains('  User? readGetUser(GetUserVariables variables, '
              '{bool optimistic = true}) {\n'));
      expect(
          code,
          contains('  void writeGetUser(GetUserVariables variables, '
              'Map<String, dynamic> data, {bool broadcast = true}) {\n'));
    });
  });

  test('optional variables become an optional named parameter', () {
    final code = _generate(
        r'query Users($first: Int) { users(first: $first) { id } }',
        'Users',
        'query');
    expect(
        code,
        contains('graphql.QueryOptions<List<User>> usersQueryOptions({\n'
            '  UsersVariables? variables,\n'));
    expect(code, contains('    variables: variables?.toJson() ?? const {},\n'));
    expect(
        code,
        contains('  List<User>? readUsers('
            '{UsersVariables? variables, bool optimistic = true}) {\n'));
  });

  test('operations without variables take no variables parameter', () {
    final code = _generate('query Version { version }', 'Version', 'query');
    expect(
        code,
        contains('graphql.QueryOptions<String?> versionQueryOptions({\n'
            '  graphql.FetchPolicy? fetchPolicy,\n'));
    expect(code, contains('    variables: const {},\n'));
  });

  test('mutations get typed MutationOptions and no cache helpers', () {
    final code = _generate(
        r'mutation Rename($id: ID!, $name: String!) '
            r'{ rename(id: $id, name: $name) { id } }',
        'Rename',
        'mutation');
    expect(
        code,
        contains('graphql.MutationOptions<User?> renameMutationOptions(\n'
            '  RenameVariables variables, {\n'));
    expect(code, contains('  graphql.OnMutationUpdate<User?>? update,\n'));
    expect(code, isNot(contains('readRename')));
  });

  test('subscriptions get typed SubscriptionOptions', () {
    final code = _generate('subscription UserChanged { userChanged { id } }',
        'UserChanged', 'subscription');
    expect(
        code,
        contains('graphql.SubscriptionOptions<User> '
            'userChangedSubscriptionOptions({\n'));
  });
}
