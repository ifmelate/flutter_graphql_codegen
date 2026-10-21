import 'package:flutter_graphql_codegen/flutter_graphql_codegen.dart';

/// Example of using Flutter GraphQL Codegen
///
/// This example demonstrates:
/// 1. Basic schema and operation definition
/// 2. Code generation process
/// 3. Using the generated result classes and client extensions
///
/// In a project you don't call the generator yourself: `build_runner` does it
/// (see the README). This shows what it produces.
void main() async {
  print('=== Flutter GraphQL Codegen Example ===\n');

  // Example GraphQL schema
  const schema = '''
  type Query {
    user(id: ID!): User
    users: [User!]!
  }

  type Mutation {
    createUser(input: CreateUserInput!): CreateUserPayload!
  }

  type User {
    id: ID!
    name: String!
    email: String!
    isActive: Boolean!
    createdAt: DateTime!
    posts: [Post!]!
  }

  type Post {
    id: ID!
    title: String!
    content: String!
    author: User!
  }

  input CreateUserInput {
    name: String!
    email: String!
    isActive: Boolean = true
  }

  type CreateUserPayload {
    user: User
    errors: [String!]!
  }

  scalar DateTime
  ''';

  // Example GraphQL operation. Only the selected fields end up in the result
  // classes: `Post.author` isn't selected, so `GetUser_User_Posts` has no
  // `author`.
  const operation = '''
  query GetUser(\$id: ID!) {
    user(id: \$id) {
      id
      name
      email
      isActive
      createdAt
      posts {
        id
        title
        content
      }
    }
  }
  ''';

  print('1. Generating types from GraphQL schema...');

  try {
    // types.dart: enums, input types and scalar converters. Result classes
    // are generated per operation (`result_types: operation`, the default).
    final typesCode = TypeGenerator.generateTypesFile(schema);
    print('✅ Types generated successfully!');
    print('Generated input classes: ${_classNames(typesCode).join(', ')}\n');

    print('2. Generating operation code...');

    final operationCode = GraphQLCodeGenerator.generateOperationFile(
      schema,
      operation,
      'GetUser',
      'query',
      typesCode,
    );
    print('✅ Operation code generated successfully!');
    final classes = _classNames(operationCode);
    print('Generated variables class: '
        '${classes.where((c) => c.endsWith('Variables')).join(', ')}');
    print('Generated result classes: '
        '${classes.where((c) => !c.endsWith('Variables')).join(', ')}');
    print('Generated extension: GetUserExtension\n');

    print('3. Example usage in your Flutter app:');
    print('''
// Import the generated files
import 'package:your_app/graphql/generated/index.dart';

// Initialize GraphQL client
final client = GraphQLClient(
  link: HttpLink('https://your-api.com/graphql'),
  cache: GraphQLCache(possibleTypes: possibleTypes),
);

// Typed data (a GetUser_User); throws OperationException on GraphQL or
// network errors
final user = await client.getUserData(
  GetUserVariables(id: 'user-123').toJson(),
);
print('User: \${user?.name} (\${user?.email})');
print('Posts: \${user?.posts?.length ?? 0}');

// Immutable results: copyWith, value equality, and typed cache writes
const variables = GetUserVariables(id: 'user-123');
if (user != null) {
  client.writeGetUser(variables, user.copyWith(name: 'New name'));
}
final cached = client.readGetUser(variables);

// Raw QueryResult when you need it
final result = await client.getUser({'id': 'user-123'});
''');

    print('\n4. Type-safe benefits:');
    print('   • Result classes with exactly the fields your query selects');
    print('   • Compile-time error checking');
    print('   • IntelliSense/auto-completion');
    print('   • Null safety with graceful defaults');
    print('   • JSON serialization, ==, hashCode and copyWith');
    print('   • Sealed classes for interfaces and unions');
    print('   • Custom scalar handling');
  } catch (e) {
    print('❌ Error generating code: $e');
  }

  print('\n=== Example completed! ===');
}

/// Public classes declared in generated [code], without the copyWith helpers.
List<String> _classNames(String code) => RegExp(r'^class (\w+)',
        multiLine: true)
    .allMatches(code)
    .map((m) => m.group(1)!)
    .where((name) => !name.endsWith('_CopyWith') && !name.endsWith('Converter'))
    .where((name) => !const {'Decimal', 'Long', 'Byte'}.contains(name))
    .toList();
