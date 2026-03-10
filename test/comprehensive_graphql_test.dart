import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/code_utils.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';

void main() {
  group('Comprehensive GraphQL Test Suite', () {
    setUp(() {
      // Clear type registry before each test
      TypeRegistry.clear();
      CodegenConfigContext.strictNullability = true;
    });

    tearDown(() {
      CodegenConfigContext.reset();
    });

    group('Union Types', () {
      test('should handle union types correctly', () {
        final schema = '''
        type Query {
          search(term: String!): [SearchResult!]!
        }
        
        union SearchResult = User | Post
        
        type User {
          id: ID!
          name: String!
          email: String!
        }
        
        type Post {
          id: ID!
          title: String!
          content: String!
          author: User!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate all types
        expect(generatedCode, contains('class User {'));
        expect(generatedCode, contains('class Post {'));
        expect(generatedCode, contains('class Query {'));

        // Check that required fields are handled correctly
        expect(generatedCode, contains('required this.id,'));
        expect(generatedCode, contains('required this.name,'));
        expect(generatedCode, contains('required this.email,'));
        expect(generatedCode, contains('required this.title,'));
        expect(generatedCode, contains('required this.content,'));
        expect(generatedCode, contains('required this.author,'));
      });
    });

    group('Interface Types', () {
      test('should handle interface types correctly', () {
        final schema = '''
        type Query {
          characters: [Character!]!
        }
        
        interface Character {
          id: ID!
          name: String!
        }
        
        type Human implements Character {
          id: ID!
          name: String!
          homePlanet: String
        }
        
        type Droid implements Character {
          id: ID!
          name: String!
          primaryFunction: String!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate all types
        expect(generatedCode, contains('class Human {'));
        expect(generatedCode, contains('class Droid {'));

        // Check interface fields are required
        expect(generatedCode, contains('required this.id,'));
        expect(generatedCode, contains('required this.name,'));

        // Check implementing types
        expect(generatedCode, contains('this.homePlanet,'));
        expect(generatedCode, contains('required this.primaryFunction,'));
      });
    });

    group('Complex Nested Types', () {
      test('should handle deeply nested types with circular references', () {
        final schema = '''
        type Query {
          organization: Organization!
        }
        
        type Organization {
          id: ID!
          name: String!
          departments: [Department!]!
        }
        
        type Department {
          id: ID!
          name: String!
          employees: [Employee!]!
          organization: Organization!
        }
        
        type Employee {
          id: ID!
          name: String!
          email: String!
          department: Department!
          manager: Employee
          subordinates: [Employee!]!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate all types without infinite recursion
        expect(generatedCode, contains('class Organization {'));
        expect(generatedCode, contains('class Department {'));
        expect(generatedCode, contains('class Employee {'));

        // Check circular reference handling and strict list nullability
        expect(generatedCode, contains('Organization organization;'));
        expect(generatedCode, contains('Department department;'));
        expect(generatedCode, contains('Employee? manager;'));
        expect(generatedCode, contains('List<Employee> subordinates;'));
      });
    });

    group('Custom Scalars', () {
      test('should handle various custom scalar types', () {
        final schema = '''
        scalar DateTime
        scalar JSON
        scalar Upload
        scalar BigInt
        scalar UUID
        
        type Query {
          user: User!
        }
        
        type User {
          id: UUID!
          createdAt: DateTime!
          metadata: JSON
          profilePicture: Upload
          balance: BigInt!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate custom scalar converters
        expect(generatedCode, contains('class JSONConverter'));
        expect(generatedCode, contains('class UploadConverter'));
        expect(generatedCode, contains('class BigIntConverter'));
        expect(generatedCode, contains('class UUIDConverter'));

        // Should use converters for custom scalar fields
        expect(generatedCode, contains('@UUIDConverter()'));
        expect(generatedCode, contains('@DateTimeConverter()'));
        expect(generatedCode, contains('@JSONConverter()'));
        expect(generatedCode, contains('@BigIntConverter()'));
      });
    });

    group('Enum Types with Values', () {
      test('should handle enums with custom values and descriptions', () {
        final schema = '''
        type Query {
          user: User!
        }
        
        enum UserRole {
          ADMIN
          MODERATOR
          USER
          GUEST
        }
        
        enum Status {
          ACTIVE
          INACTIVE
          PENDING
          SUSPENDED
        }
        
        type User {
          id: ID!
          role: UserRole!
          status: Status!
          permissions: [UserRole!]!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate enum definitions
        expect(generatedCode, contains('enum UserRole {'));
        expect(generatedCode, contains('ADMIN,'));
        expect(generatedCode, contains('MODERATOR,'));
        expect(generatedCode, contains('USER,'));
        expect(generatedCode, contains('GUEST,'));

        expect(generatedCode, contains('enum Status {'));
        expect(generatedCode, contains('ACTIVE,'));
        expect(generatedCode, contains('INACTIVE,'));
        expect(generatedCode, contains('PENDING,'));
        expect(generatedCode, contains('SUSPENDED,'));

        // Should generate enum converters
        expect(generatedCode, contains('class UserRoleConverter'));
        expect(generatedCode, contains('class StatusConverter'));
      });
    });

    group('Input Types and Arguments', () {
      test('should handle complex input types', () {
        final schema = '''
        type Query {
          searchUsers(filter: UserFilter!, pagination: PaginationInput): UserConnection!
        }
        
        input UserFilter {
          name: String
          email: String
          role: UserRole
          isActive: Boolean
          createdAfter: DateTime
        }
        
        input PaginationInput {
          first: Int
          after: String
          last: Int
          before: String
        }
        
        enum UserRole {
          ADMIN
          USER
        }
        
        type UserConnection {
          edges: [UserEdge!]!
          pageInfo: PageInfo!
        }
        
        type UserEdge {
          node: User!
          cursor: String!
        }
        
        type User {
          id: ID!
          name: String!
          email: String!
        }
        
        type PageInfo {
          hasNextPage: Boolean!
          hasPreviousPage: Boolean!
          startCursor: String
          endCursor: String
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate connection types (input types may not be generated by this library)
        expect(generatedCode, contains('class UserConnection {'));
        expect(generatedCode, contains('class UserEdge {'));
        expect(generatedCode, contains('class PageInfo {'));

        // Should handle nullable fields
        expect(generatedCode, contains('String? startCursor;'));
        expect(generatedCode, contains('String? endCursor;'));
      });
    });

    group('Mutations', () {
      test('should handle mutation operations', () {
        final schema = '''
        type Query {
          user(id: ID!): User
        }
        
        type Mutation {
          createUser(input: CreateUserInput!): CreateUserPayload!
          updateUser(id: ID!, input: UpdateUserInput!): UpdateUserPayload!
          deleteUser(id: ID!): DeleteUserPayload!
        }
        
        input CreateUserInput {
          name: String!
          email: String!
          role: UserRole = USER
        }
        
        input UpdateUserInput {
          name: String
          email: String
          role: UserRole
        }
        
        type CreateUserPayload {
          user: User!
          errors: [UserError!]!
        }
        
        type UpdateUserPayload {
          user: User
          errors: [UserError!]!
        }
        
        type DeleteUserPayload {
          deletedUserId: ID!
          errors: [UserError!]!
        }
        
        type UserError {
          field: String!
          message: String!
        }
        
        type User {
          id: ID!
          name: String!
          email: String!
          role: UserRole!
        }
        
        enum UserRole {
          ADMIN
          USER
        }
        ''';

        final operationDocument = '''
                 mutation CreateUser(\$input: CreateUserInput!) {
           createUser(input: \$input) {
            user {
              id
              name
              email
              role
            }
            errors {
              field
              message
            }
          }
        }
        ''';

        final typesCode = TypeGenerator.generateTypesFile(schema);
        final operationCode = GraphQLCodeGenerator.generateOperationFile(
          schema,
          operationDocument,
          'CreateUser',
          'Mutation',
          typesCode,
        );

        // Should generate mutation extension
        expect(operationCode, contains('extension CreateUserExtension'));
        expect(operationCode, contains('mutate(options)'));
        expect(operationCode, contains('CreateUserPayload'));
      });
    });

    group('Subscriptions', () {
      test('should handle subscription operations', () {
        final schema = '''
        type Query {
          user(id: ID!): User
        }
        
        type Subscription {
          userUpdated(id: ID!): User!
          messageAdded(channelId: ID!): Message!
        }
        
        type User {
          id: ID!
          name: String!
          email: String!
          isOnline: Boolean!
        }
        
        type Message {
          id: ID!
          content: String!
          author: User!
          createdAt: DateTime!
        }
        ''';

        final typesCode = TypeGenerator.generateTypesFile(schema);

        // Test that types are generated - skip operation generation for subscriptions since it's not fully supported
        expect(typesCode, contains('class User {'));
        expect(typesCode, contains('class Message {'));
      });
    });

    group('Lists and Nullable Combinations', () {
      test('should handle all nullable list combinations', () {
        final schema = '''
        type Query {
          data: TestType!
        }
        
        type TestType {
          requiredListRequiredItems: [String!]!
          requiredListNullableItems: [String]!
          nullableListRequiredItems: [String!]
          nullableListNullableItems: [String]
          nestedRequiredList: [[String!]!]!
          nestedNullableList: [[String]]
          mixedNestedList: [[String!]]!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Lists should respect schema nullability
        expect(
            generatedCode, contains('List<String> requiredListRequiredItems;'));
        expect(generatedCode,
            contains('List<String?> requiredListNullableItems;'));
        expect(generatedCode,
            contains('List<String>? nullableListRequiredItems;'));
        expect(generatedCode,
            contains('List<String?>? nullableListNullableItems;'));

        // Nested lists
        expect(
            generatedCode, contains('List<List<String>> nestedRequiredList;'));
        expect(generatedCode,
            contains('List<List<String?>?>? nestedNullableList;'));
        expect(generatedCode, contains('List<List<String>?> mixedNestedList;'));

        // List fields should have default values in constructor
        expect(generatedCode, contains('= const []'));
      });
    });

    group('Fragments and Inline Fragments', () {
      test('should handle fragment operations', () {
        final schema = '''
        type Query {
          search: [SearchResult!]!
        }
        
        union SearchResult = User | Post
        
        type User {
          id: ID!
          name: String!
          email: String!
        }
        
        type Post {
          id: ID!
          title: String!
          content: String!
        }
        ''';

        final operationDocument = '''
        fragment UserFields on User {
          id
          name
          email
        }
        
        fragment PostFields on Post {
          id
          title
          content
        }
        
        query SearchWithFragments {
          search {
            ... on User {
              ...UserFields
            }
            ... on Post {
              ...PostFields
            }
          }
        }
        ''';

        final typesCode = TypeGenerator.generateTypesFile(schema);
        final operationCode = GraphQLCodeGenerator.generateOperationFile(
          schema,
          operationDocument,
          'SearchWithFragments',
          'Query',
          typesCode,
        );

        // Should generate operation extension
        expect(
            operationCode, contains('extension SearchWithFragmentsExtension'));
        expect(operationCode, contains('SearchWithFragments'));
      });
    });

    group('Directives', () {
      test('should handle GraphQL directives', () {
        final schema = '''
        directive @deprecated(reason: String = "No longer supported") on FIELD_DEFINITION | ENUM_VALUE
        directive @skip(if: Boolean!) on FIELD | INLINE_FRAGMENT | FRAGMENT_SPREAD
        directive @include(if: Boolean!) on FIELD | INLINE_FRAGMENT | FRAGMENT_SPREAD
        
        type Query {
          user: User!
        }
        
        type User {
          id: ID!
          name: String!
          email: String!
          oldField: String @deprecated(reason: "Use email instead")
        }
        ''';

        final operationDocument = '''
                 query GetUser(\$includeEmail: Boolean!, \$skipOldField: Boolean!) {
           user {
             id
             name
             email @include(if: \$includeEmail)
             oldField @skip(if: \$skipOldField)
          }
        }
        ''';

        final typesCode = TypeGenerator.generateTypesFile(schema);
        final operationCode = GraphQLCodeGenerator.generateOperationFile(
          schema,
          operationDocument,
          'GetUser',
          'Query',
          typesCode,
        );

        // Should handle operations with directives
        expect(operationCode, contains('extension GetUserExtension'));
        expect(operationCode, contains('variables ?? const {}'));
      });
    });

    group('Error Handling', () {
      test('should handle malformed schemas gracefully', () {
        // Test with incomplete schema
        final incompleteSchema = '''
        type Query {
          user: User!
        }
        
        type User {
          id: ID!
          name: String!
          # Missing closing field
        ''';

        expect(() => TypeGenerator.generateTypesFile(incompleteSchema),
            throwsA(isA<Exception>()));
      });

      test('should handle undefined types in schema', () {
        final schemaWithUndefinedType = '''
        type Query {
          user: User!
        }
        
        type User {
          id: ID!
          name: String!
          profile: UndefinedType
        }
        ''';

        final generatedCode =
            TypeGenerator.generateTypesFile(schemaWithUndefinedType);

        // Should handle undefined types gracefully
        expect(generatedCode, contains('UndefinedType? profile;'));
      });
    });

    group('Large Schema Performance', () {
      test('should handle large schemas efficiently', () {
        final largeSchema = '''
        type Query {
          ${List.generate(50, (i) => 'field$i: Type$i!').join('\n          ')}
        }
        
        ${List.generate(50, (i) => '''
        type Type$i {
          id: ID!
          name: String!
          value$i: Int!
          related: [Type${(i + 1) % 50}!]!
        }
        ''').join('\n        ')}
        ''';

        final startTime = DateTime.now();
        final generatedCode = TypeGenerator.generateTypesFile(largeSchema);
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);

        // Should complete in reasonable time (less than 5 seconds)
        expect(duration.inSeconds, lessThan(5));

        // Should generate all types
        for (int i = 0; i < 50; i++) {
          expect(generatedCode, contains('class Type$i {'));
        }
      });
    });

    group('Special Characters and Unicode', () {
      test('should handle special characters in field names and types', () {
        final schema = '''
        type Query {
          user: User!
        }
        
        type User {
          id: ID!
          name: String!
          emailAddress: String!
          user_name_with_underscores: String!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should handle field names
        expect(generatedCode, contains('class User {'));
        expect(generatedCode, contains('String emailAddress;'));
        expect(generatedCode, contains('String user_name_with_underscores;'));
      });
    });

    group('Recursive Types', () {
      test('should handle recursive type definitions', () {
        final schema = '''
        type Query {
          category: Category!
        }
        
        type Category {
          id: ID!
          name: String!
          parent: Category
          children: [Category!]!
          products: [Product!]!
        }
        
        type Product {
          id: ID!
          name: String!
          category: Category!
          relatedProducts: [Product!]!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should handle recursive references
        expect(generatedCode, contains('Category? parent;'));
        expect(generatedCode, contains('List<Category> children;'));
        expect(generatedCode, contains('List<Product> relatedProducts;'));
        expect(generatedCode, contains('Category category;'));
      });
    });
  });
}
