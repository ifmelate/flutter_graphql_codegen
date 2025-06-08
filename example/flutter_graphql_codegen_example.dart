import 'package:flutter_graphql_codegen/flutter_graphql_codegen.dart';

/// Comprehensive example of using Flutter GraphQL Codegen
///
/// This example demonstrates:
/// 1. Basic schema and operation definition
/// 2. Code generation process
/// 3. Using generated types and client extensions
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

  // Example GraphQL operation
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
    // Generate types from schema
    final typesCode = TypeGenerator.generateTypesFile(schema);
    print('✅ Types generated successfully!');
    print(
        'Generated classes: User, Post, CreateUserInput, CreateUserPayload\n');

    print('2. Generating operation code...');

    // Generate operation code
    GraphQLCodeGenerator.generateOperationFile(
      schema,
      operation,
      'GetUser',
      'Query',
      typesCode,
    );
    print('✅ Operation code generated successfully!');
    print('Generated extension: GetUserExtension\n');

    print('3. Example usage in your Flutter app:');
    print('''
// Import the generated files
import 'lib/graphql/generated/types.dart';
import 'lib/graphql/generated/get_user.dart';

// Initialize GraphQL client
final client = GraphQLClient(
  link: HttpLink('https://your-api.com/graphql'),
  cache: GraphQLCache(),
);

// Use the generated extension
final result = await client.getUserQuery(
  variables: GetUserArguments(id: 'user-123'),
);

if (result.hasException) {
  print('Error: \${result.exception}');
} else {
  final user = result.parsedData?.user;
  print('User: \${user?.name} (\${user?.email})');
  print('Posts: \${user?.posts?.length ?? 0}');
}
''');

    print('\n4. Type-safe benefits:');
    print('   • Compile-time error checking');
    print('   • IntelliSense/auto-completion');
    print('   • Null safety with graceful defaults');
    print('   • Automatic JSON serialization');
    print('   • Custom scalar handling');
  } catch (e) {
    print('❌ Error generating code: $e');
  }

  print('\n=== Example completed! ===');
}
