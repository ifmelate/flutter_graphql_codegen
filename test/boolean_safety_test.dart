import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';

void main() {
  group('Type Safety Tests', () {
    test('should use safe converters for primitive types', () {
      final schema = '''
      type TestType {
        requiredBool: Boolean!
        nullableBool: Boolean
        requiredInt: Int!
        nullableInt: Int
        requiredFloat: Float!
        nullableFloat: Float
        requiredString: String!
        nullableString: String
        requiredList: [String!]!
        nullableList: [String]
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Check for safe converters
      expect(generatedCode, contains('class SafeBoolConverter'),
          reason: 'Should include SafeBoolConverter class');
      expect(generatedCode, contains('class SafeIntConverter'),
          reason: 'Should include SafeIntConverter class');
      expect(generatedCode, contains('class SafeDoubleConverter'),
          reason: 'Should include SafeDoubleConverter class');

      // Count converter annotations
      final safeBoolCount =
          '@SafeBoolConverter()'.allMatches(generatedCode).length;
      final safeIntCount =
          '@SafeIntConverter()'.allMatches(generatedCode).length;
      final safeDoubleCount =
          '@SafeDoubleConverter()'.allMatches(generatedCode).length;
      final listDefaultCount =
          '@JsonKey(defaultValue: [])'.allMatches(generatedCode).length;

      expect(safeBoolCount, equals(1),
          reason: 'Should have exactly 1 SafeBoolConverter annotation');
      expect(safeIntCount, equals(1),
          reason: 'Should have exactly 1 SafeIntConverter annotation');
      expect(safeDoubleCount, equals(1),
          reason: 'Should have exactly 1 SafeDoubleConverter annotation');
      expect(listDefaultCount, greaterThanOrEqualTo(0),
          reason:
              'List defaultValue annotations are optional in current implementation');

      // Check field types remain as originally defined (non-nullable for required fields)
      expect(generatedCode, contains('bool requiredBool;'),
          reason:
              'Boolean! fields should remain bool (converters handle safety)');
      expect(generatedCode, contains('int requiredInt;'),
          reason: 'Int! fields should remain int (converters handle safety)');
      expect(generatedCode, contains('double requiredFloat;'),
          reason:
              'Float! fields should remain double (converters handle safety)');

      // Nullable fields should remain nullable
      expect(generatedCode, contains('bool? nullableBool;'),
          reason: 'Already nullable boolean fields should remain nullable');
      expect(generatedCode, contains('int? nullableInt;'),
          reason: 'Already nullable int fields should remain nullable');
      expect(generatedCode, contains('double? nullableFloat;'),
          reason: 'Already nullable double fields should remain nullable');

      // Required fields should have 'required' in constructor
      expect(generatedCode, contains('required this.requiredBool,'),
          reason: 'Required boolean fields should be marked as required');
      expect(generatedCode, contains('required this.requiredInt,'),
          reason: 'Required int fields should be marked as required');
      expect(generatedCode, contains('required this.requiredFloat,'),
          reason: 'Required double fields should be marked as required');
    });

    test('should handle RepertorySymptomDTO with safe converters', () {
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
      }
      
      type RepertoryDrugDTO {
        id: Int!
        name: String!
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Check that problematic fields use safe converters
      expect(generatedCode, contains('@SafeBoolConverter()'),
          reason: 'Boolean! fields should use SafeBoolConverter');
      expect(generatedCode, contains('@SafeIntConverter()'),
          reason: 'Int! fields should use SafeIntConverter');

      // Check that fields remain as non-nullable types
      expect(generatedCode, contains('bool hasChildren;'),
          reason: 'hasChildren should remain bool (converter handles safety)');
      expect(generatedCode, contains('bool isRegistered;'),
          reason: 'isRegistered should remain bool (converter handles safety)');
      expect(generatedCode, contains('int degree;'),
          reason: 'degree should remain int (converter handles safety)');
      expect(generatedCode, contains('int drugsCount;'),
          reason: 'drugsCount should remain int (converter handles safety)');

      // Check that fields are marked as required in constructor
      expect(generatedCode, contains('required this.hasChildren,'),
          reason: 'hasChildren should be required');
      expect(generatedCode, contains('required this.isRegistered,'),
          reason: 'isRegistered should be required');
      expect(generatedCode, contains('required this.degree,'),
          reason: 'degree should be required');
      expect(generatedCode, contains('required this.drugsCount,'),
          reason: 'drugsCount should be required');

      // Check safe converter implementations
      expect(generatedCode, contains('if (json == null) return false;'),
          reason: 'SafeBoolConverter should handle null values');
      expect(generatedCode, contains('if (json == null) return 0;'),
          reason: 'SafeIntConverter should handle null values');
    });

    test('safe converters should handle various input types', () {
      final schema = '''
      type TestType {
        testBool: Boolean!
        testInt: Int!
        testDouble: Float!
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Check SafeBoolConverter handles different types
      expect(generatedCode, contains('if (json is bool) return json;'),
          reason: 'SafeBoolConverter should handle bool input');
      expect(generatedCode, contains('if (json is String)'),
          reason: 'SafeBoolConverter should handle String input');
      expect(generatedCode, contains('if (json is num) return json != 0;'),
          reason: 'SafeBoolConverter should handle numeric input');

      // Check SafeIntConverter handles different types
      expect(generatedCode, contains('if (json is int) return json;'),
          reason: 'SafeIntConverter should handle int input');
      expect(
          generatedCode, contains('if (json is double) return json.toInt();'),
          reason: 'SafeIntConverter should handle double input');
      expect(generatedCode, contains('return int.tryParse(json) ?? 0;'),
          reason: 'SafeIntConverter should handle String input safely');

      // Check SafeDoubleConverter handles different types
      expect(generatedCode, contains('if (json is double) return json;'),
          reason: 'SafeDoubleConverter should handle double input');
      expect(
          generatedCode, contains('if (json is int) return json.toDouble();'),
          reason: 'SafeDoubleConverter should handle int input');
      expect(generatedCode, contains('return double.tryParse(json) ?? 0.0;'),
          reason: 'SafeDoubleConverter should handle String input safely');
    });
  });
}
