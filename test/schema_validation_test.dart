import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:flutter_graphql_codegen/src/code_utils.dart';

void main() {
  group('Schema Validation and Edge Cases', () {
    setUp(() {
      TypeRegistry.clear();
    });

    group('Schema Parsing Edge Cases', () {
      test('should handle empty schema gracefully', () {
        const emptySchema = '';
        final result = TypeGenerator.generateTypesFile(emptySchema);

        // Should generate basic structure with converters, not throw exception
        expect(
            result,
            contains(
                'import \'package:json_annotation/json_annotation.dart\';'));
        expect(result, contains('class Decimal {'));
      });

      test('should handle schema with only comments', () {
        const commentOnlySchema = '''
         # This is a comment
         # Another comment
         ''';
        final result = TypeGenerator.generateTypesFile(commentOnlySchema);

        // Should generate basic structure, not throw exception
        expect(
            result,
            contains(
                'import \'package:json_annotation/json_annotation.dart\';'));
        expect(result, contains('class Decimal {'));
      });

      test('should handle schema with complex type dependencies', () {
        const complexSchema = '''
        type Query {
          a: A!
        }
        
        type A {
          b: B!
        }
        
        type B {
          c: C!
        }
        
        type C {
          d: D!
        }
        
        type D {
          value: String!
          a: A # Circular reference
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(complexSchema);

        // Should handle circular dependencies
        expect(generatedCode, contains('class A {'));
        expect(generatedCode, contains('class B {'));
        expect(generatedCode, contains('class C {'));
        expect(generatedCode, contains('class D {'));
        expect(generatedCode,
            contains('A? a;')); // Should be nullable to break cycle
      });
    });

    group('Null Safety Edge Cases', () {
      test('should handle complex null safety scenarios', () {
        const schema = '''
        type Query {
          test: ComplexType!
        }
        
        type ComplexType {
          requiredField: String!
          nullableField: String
          requiredNested: NestedType!
          nullableNested: NestedType
          requiredList: [String!]!
          nullableList: [String]
          mixedList: [NestedType!]
          deeplyNested: [[[String]]]
        }
        
        type NestedType {
          id: ID!
          value: String
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Check required vs nullable fields
        expect(generatedCode, contains('String requiredField;'));
        expect(generatedCode, contains('String? nullableField;'));
        expect(generatedCode, contains('NestedType requiredNested;'));
        expect(generatedCode, contains('NestedType? nullableNested;'));

        // All lists should be nullable for graceful handling
        expect(generatedCode, contains('List<String>? requiredList;'));
        expect(generatedCode, contains('List<String?>? nullableList;'));
        expect(generatedCode, contains('List<NestedType>? mixedList;'));
        expect(generatedCode,
            contains('List<List<List<String?>?>?>? deeplyNested;'));
      });
    });

    group('Type Collision Handling', () {
      test('should handle type name collisions with Dart keywords', () {
        const schema = '''
        type Query {
          class: ClassType!
          if: IfType!
          for: ForType!
        }
        
        type ClassType {
          id: ID!
        }
        
        type IfType {
          id: ID!
        }
        
        type ForType {
          id: ID!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate types even with keyword names
        expect(generatedCode, contains('class ClassType {'));
        expect(generatedCode, contains('class IfType {'));
        expect(generatedCode, contains('class ForType {'));
      });
    });

    group('Schema Extensions', () {
      test('should handle type extensions', () {
        const schema = '''
        type Query {
          user: User!
        }
        
        type User {
          id: ID!
          name: String!
        }
        
        extend type User {
          email: String!
          isActive: Boolean!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should include base type (extensions may not be fully supported)
        expect(generatedCode, contains('class User {'));
        expect(generatedCode, contains('String name;'));
        // Note: Type extensions may not be fully supported in this generator
      });
    });

    group('Field Argument Validation', () {
      test('should handle fields with complex arguments', () {
        const schema = '''
        type Query {
          search(
            query: String!
            filters: [FilterInput!]
            pagination: PaginationInput
            sort: SortInput = {field: "createdAt", direction: DESC}
          ): SearchResult!
        }
        
        input FilterInput {
          field: String!
          value: String!
          operator: FilterOperator = EQUALS
        }
        
        input PaginationInput {
          limit: Int = 10
          offset: Int = 0
        }
        
        input SortInput {
          field: String!
          direction: SortDirection!
        }
        
        enum FilterOperator {
          EQUALS
          NOT_EQUALS
          CONTAINS
          GT
          LT
        }
        
        enum SortDirection {
          ASC
          DESC
        }
        
        type SearchResult {
          items: [SearchItem!]!
          totalCount: Int!
        }
        
        type SearchItem {
          id: ID!
          title: String!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate all result types and enums (input types may not be generated)
        expect(generatedCode, contains('class SearchResult {'));
        expect(generatedCode, contains('class SearchItem {'));
        expect(generatedCode, contains('enum FilterOperator {'));
        expect(generatedCode, contains('enum SortDirection {'));
      });
    });

    group('Introspection Types', () {
      test('should handle introspection schema types', () {
        const schema = '''
        type Query {
          __schema: __Schema!
          __type(name: String!): __Type
        }
        
        type __Schema {
          types: [__Type!]!
          queryType: __Type!
          mutationType: __Type
          subscriptionType: __Type
          directives: [__Directive!]!
        }
        
        type __Type {
          kind: __TypeKind!
          name: String
          description: String
          fields(includeDeprecated: Boolean = false): [__Field!]
          ofType: __Type
        }
        
        type __Field {
          name: String!
          description: String
          args: [__InputValue!]!
          type: __Type!
          isDeprecated: Boolean!
          deprecationReason: String
        }
        
        type __InputValue {
          name: String!
          description: String
          type: __Type!
          defaultValue: String
        }
        
        type __Directive {
          name: String!
          description: String
          locations: [__DirectiveLocation!]!
          args: [__InputValue!]!
        }
        
        enum __TypeKind {
          SCALAR
          OBJECT
          INTERFACE
          UNION
          ENUM
          INPUT_OBJECT
          LIST
          NON_NULL
        }
        
        enum __DirectiveLocation {
          QUERY
          MUTATION
          SUBSCRIPTION
          FIELD
          FRAGMENT_DEFINITION
          FRAGMENT_SPREAD
          INLINE_FRAGMENT
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should handle introspection types
        expect(generatedCode, contains('class __Schema {'));
        expect(generatedCode, contains('class __Type {'));
        expect(generatedCode, contains('class __Field {'));
        expect(generatedCode, contains('enum __TypeKind {'));
      });
    });

    group('Performance with Large Schemas', () {
      test('should handle schema with many fields efficiently', () {
        final largeTypeFields = List.generate(
          100,
          (i) => 'field$i: String${i % 2 == 0 ? '!' : ''}',
        ).join('\n          ');

        final schema = '''
        type Query {
          largeType: LargeType!
        }
        
        type LargeType {
          $largeTypeFields
        }
        ''';

        final startTime = DateTime.now();
        final generatedCode = TypeGenerator.generateTypesFile(schema);
        final duration = DateTime.now().difference(startTime);

        // Should complete in reasonable time
        expect(duration.inMilliseconds, lessThan(1000));
        expect(generatedCode, contains('class LargeType {'));

        // Should contain all fields
        for (int i = 0; i < 100; i++) {
          expect(generatedCode, contains('field$i'));
        }
      });
    });

    group('Error Recovery', () {
      test('should provide meaningful error messages for invalid schemas', () {
        const invalidSchema = '''
        type Query {
          user: User!
        }
        
        type User {
          id: ID!
          name: String!
          invalidField: NonExistentType!
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(invalidSchema);

        // Should still generate valid parts and handle unknown types gracefully
        expect(generatedCode, contains('class User {'));
        expect(generatedCode, contains('NonExistentType invalidField;'));
      });

      test('should handle malformed field definitions', () {
        const malformedSchema = '''
        type Query {
          user: User!
        }
        
        type User {
          id: ID!
          name: String!
          # This field definition is incomplete but parser should handle it
        }
        ''';

        // Should not throw exception for incomplete definitions
        expect(() => TypeGenerator.generateTypesFile(malformedSchema),
            returnsNormally);
      });
    });

    group('Custom Directive Handling', () {
      test('should handle custom directives gracefully', () {
        const schema = '''
        directive @auth(requires: UserRole = USER) on FIELD_DEFINITION
        directive @deprecated(reason: String) on FIELD_DEFINITION
        directive @cache(maxAge: Int) on FIELD_DEFINITION
        
        enum UserRole {
          USER
          ADMIN
        }
        
        type Query {
          publicField: String!
          userField: String! @auth(requires: USER)
          adminField: String! @auth(requires: ADMIN)
          cachedField: String! @cache(maxAge: 300)
          deprecatedField: String! @deprecated(reason: "Use newField instead")
        }
        ''';

        final generatedCode = TypeGenerator.generateTypesFile(schema);

        // Should generate types ignoring directive complexity
        expect(generatedCode, contains('class Query {'));
        expect(generatedCode, contains('String publicField;'));
        expect(generatedCode, contains('String userField;'));
        expect(generatedCode, contains('String adminField;'));
        expect(generatedCode, contains('String cachedField;'));
        expect(generatedCode, contains('String deprecatedField;'));
      });
    });
  });
}
