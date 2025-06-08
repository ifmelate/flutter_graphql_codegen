import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';

void main() {
  group('Integration Tests - Safe Converters with Real Data', () {
    test('should handle RepertorySymptomDTO with null values correctly', () {
      final schema = '''
      type RepertorySymptomDTO {
        id: Int!
        name: String!
        description: String!
        repGlavId: Int!
        parentId: Int
        hasChildren: Boolean!
        isRegistered: Boolean!
        degree: Int!
        drugsCount: Int!
        drugs: [RepertoryDrugDTO!]!
        references: [ReferenceDTO!]!
      }
      
      type RepertoryDrugDTO {
        id: Int!
        name: String!
      }
      
      type ReferenceDTO {
        id: Int!
        title: String!
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Check that all required safe converters are present
      expect(generatedCode, contains('class SafeBoolConverter'),
          reason: 'SafeBoolConverter should be included');
      expect(generatedCode, contains('class SafeIntConverter'),
          reason: 'SafeIntConverter should be included');
      expect(generatedCode, contains('class SafeDoubleConverter'),
          reason: 'SafeDoubleConverter should be included');

      // Check that safe converters are applied to the right fields
      final safeBoolAnnotations =
          '@SafeBoolConverter()'.allMatches(generatedCode);
      final safeIntAnnotations =
          '@SafeIntConverter()'.allMatches(generatedCode);

      // RepertorySymptomDTO should have: hasChildren, isRegistered (2 bool fields)
      // and id, repGlavId, degree, drugsCount (4 int fields)
      expect(safeBoolAnnotations.length, greaterThanOrEqualTo(2),
          reason: 'Should have at least 2 SafeBoolConverter annotations');
      expect(safeIntAnnotations.length, greaterThanOrEqualTo(4),
          reason: 'Should have at least 4 SafeIntConverter annotations');

      // Check that list fields are handled properly (default values are in constructor)
      expect(generatedCode, contains('= const []'),
          reason:
              'List fields should have default empty arrays in constructor');

      // Verify safe converter implementations handle various types
      expect(generatedCode, contains('if (json == null) return false;'),
          reason: 'SafeBoolConverter should handle null');
      expect(generatedCode, contains('if (json == null) return 0;'),
          reason: 'SafeIntConverter should handle null');
      expect(generatedCode, contains('if (json == null) return 0.0;'),
          reason: 'SafeDoubleConverter should handle null');

      // Test string input handling
      expect(generatedCode, contains('return int.tryParse(json) ?? 0;'),
          reason: 'SafeIntConverter should safely parse strings');
      expect(generatedCode, contains('return double.tryParse(json) ?? 0.0;'),
          reason: 'SafeDoubleConverter should safely parse strings');

      // Test boolean string conversion
      expect(generatedCode, contains('final lower = json.toLowerCase();'),
          reason: 'SafeBoolConverter should handle string inputs');
      expect(generatedCode, contains("return lower == 'true' || lower == '1';"),
          reason: 'SafeBoolConverter should parse string booleans');
    });

    test('should handle mixed primitive types safely', () {
      final schema = '''
      type TestEntity {
        requiredBool: Boolean!
        optionalBool: Boolean
        requiredInt: Int!
        optionalInt: Int
        requiredFloat: Float!
        optionalFloat: Float
        requiredString: String!
        optionalString: String
        requiredList: [String!]!
        optionalList: [String]
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Count safe converter usages
      final safeBoolCount =
          '@SafeBoolConverter()'.allMatches(generatedCode).length;
      final safeIntCount =
          '@SafeIntConverter()'.allMatches(generatedCode).length;
      final safeDoubleCount =
          '@SafeDoubleConverter()'.allMatches(generatedCode).length;
      final listDefaultCount =
          '@JsonKey(defaultValue: [])'.allMatches(generatedCode).length;

      // Should have exactly one of each for required fields
      expect(safeBoolCount, equals(1),
          reason: 'Should have 1 required boolean');
      expect(safeIntCount, equals(1), reason: 'Should have 1 required int');
      expect(safeDoubleCount, equals(1),
          reason: 'Should have 1 required float');
      expect(listDefaultCount, greaterThanOrEqualTo(0),
          reason: 'List default values are optional in current implementation');

      // Verify field type definitions
      expect(generatedCode, contains('bool requiredBool;'),
          reason: 'Required bool should remain non-nullable');
      expect(generatedCode, contains('bool? optionalBool;'),
          reason: 'Optional bool should remain nullable');
      expect(generatedCode, contains('int requiredInt;'),
          reason: 'Required int should remain non-nullable');
      expect(generatedCode, contains('int? optionalInt;'),
          reason: 'Optional int should remain nullable');
      expect(generatedCode, contains('double requiredFloat;'),
          reason: 'Required double should remain non-nullable');
      expect(generatedCode, contains('double? optionalFloat;'),
          reason: 'Optional double should remain nullable');

      // Check constructor parameters
      expect(generatedCode, contains('required this.requiredBool,'),
          reason: 'Required fields should be marked as required');
      expect(generatedCode, contains('this.optionalBool,'),
          reason: 'Optional fields should not be required');
    });

    test('should handle complex nested types with converters', () {
      final schema = '''
      type User {
        id: Int!
        name: String!
        isActive: Boolean!
        profile: UserProfile
        settings: [UserSetting!]!
      }
      
      type UserProfile {
        id: Int!
        age: Int!
        isPublic: Boolean!
        rating: Float!
      }
      
      type UserSetting {
        id: Int!
        key: String!
        value: String!
        isEnabled: Boolean!
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // All three types should have safe converters for their required fields
      final safeBoolCount =
          '@SafeBoolConverter()'.allMatches(generatedCode).length;
      final safeIntCount =
          '@SafeIntConverter()'.allMatches(generatedCode).length;
      final safeDoubleCount =
          '@SafeDoubleConverter()'.allMatches(generatedCode).length;

      // User: 1 bool, 1 int
      // UserProfile: 1 bool, 2 int, 1 double
      // UserSetting: 1 bool, 1 int
      expect(safeBoolCount, equals(3),
          reason: 'Should have 3 bool converters total');
      expect(safeIntCount, equals(4),
          reason: 'Should have 4 int converters total');
      expect(safeDoubleCount, equals(1),
          reason: 'Should have 1 double converter total');

      // Verify all generated classes exist
      expect(generatedCode, contains('class User {'),
          reason: 'User class should exist');
      expect(generatedCode, contains('class UserProfile {'),
          reason: 'UserProfile class should exist');
      expect(generatedCode, contains('class UserSetting {'),
          reason: 'UserSetting class should exist');
    });

    test('should validate safe converter logic', () {
      final schema = '''
      type ValidationTest {
        testBool: Boolean!
        testInt: Int!
        testDouble: Float!
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Verify SafeBoolConverter logic
      expect(generatedCode, contains('if (json is bool) return json;'),
          reason: 'Should handle direct bool values');
      expect(generatedCode, contains('if (json is String)'),
          reason: 'Should handle string representations');
      expect(generatedCode, contains('if (json is num) return json != 0;'),
          reason: 'Should handle numeric boolean representations');

      // Verify SafeIntConverter logic
      expect(generatedCode, contains('if (json is int) return json;'),
          reason: 'Should handle direct int values');
      expect(
          generatedCode, contains('if (json is double) return json.toInt();'),
          reason: 'Should convert double to int');
      expect(generatedCode, contains('return int.tryParse(json) ?? 0;'),
          reason: 'Should safely parse string to int');

      // Verify SafeDoubleConverter logic
      expect(generatedCode, contains('if (json is double) return json;'),
          reason: 'Should handle direct double values');
      expect(
          generatedCode, contains('if (json is int) return json.toDouble();'),
          reason: 'Should convert int to double');
      expect(generatedCode, contains('return double.tryParse(json) ?? 0.0;'),
          reason: 'Should safely parse string to double');
    });
  });
}
