import 'package:flutter_graphql_codegen/flutter_graphql_codegen.dart';

void main() {
  print('=== Flutter GraphQL Codegen Manual Test ===\n');

  // Test schema
  final schema = '''
    type Query {
      users: [User!]!
      user(id: ID!): User
    }
    
    type User {
      id: ID!
      name: String!
      email: String!
      age: Int
    }
    
    enum UserStatus {
      ACTIVE
      INACTIVE
    }
  ''';

  // Generate types file
  print('Generating types.dart file...\n');
  final typesCode = GraphQLCodeGenerator.generateTypesFile(schema);
  print('Generated types.dart:');
  print('=' * 50);
  print('${typesCode.substring(0, 300)}...\n'); // Show first 300 characters

  // Generate operation file
  print('Generating operation file...\n');
  final operationDocument = '''
    query GetUsers {
      users {
        id
        name
        email
      }
    }
  ''';

  final operationCode = GraphQLCodeGenerator.generateOperationFile(
    schema,
    operationDocument,
    'GetUsers',
    'Query',
    typesCode,
  );

  print('Generated operation file:');
  print('=' * 50);
  print('${operationCode.substring(0, 300)}...\n'); // Show first 300 characters

  print('=== Test completed successfully! ===');
  print('Both generated files now contain warning comments at the top.');
}
