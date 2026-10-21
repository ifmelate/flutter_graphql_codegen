import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

void main() {
  group('JSON Field Naming Tests', () {
    test(
        'should preserve camelCase field names using fieldRename: FieldRename.none',
        () {
      const schema = '''
        type BalanceDTO {
          value: Decimal!
          balanceLevel: BalanceLevelEnum!
        }
        
        enum BalanceLevelEnum {
          HIGH
          MIDDLE
          VERY_LOW
          LOW
        }
        
        scalar Decimal
      ''';

      final typesCode = TypeGenerator.generateTypesFile(schema);

      // The generated code should use fieldRename: FieldRename.none to preserve original field names
      expect(typesCode, contains('fieldRename: FieldRename.none'));

      // Should contain the BalanceDTO class
      expect(typesCode, contains('class BalanceDTO'));

      // Should contain the balanceLevel field (camelCase preserved)
      expect(typesCode, contains('BalanceLevelEnum balanceLevel;'));

      // Should have proper enum converter
      expect(typesCode, contains('@BalanceLevelEnumConverter()'));

      // Should have proper decimal converter
      expect(typesCode, contains('@SafeDecimalConverter()'));

      print('✅ Generated types code includes fieldRename: FieldRename.none');
      print('✅ BalanceDTO class correctly generated');
      print('✅ balanceLevel field preserved in camelCase');
    });

    test('should generate enum converter with correct naming', () {
      const schema = '''
        enum BalanceLevelEnum {
          HIGH
          MIDDLE
          VERY_LOW
          LOW
        }
      ''';

      final typesCode = TypeGenerator.generateTypesFile(schema);

      // Should generate the enum
      expect(typesCode, contains('enum BalanceLevelEnum'));
      expect(typesCode, contains('HIGH'));
      expect(typesCode, contains('MIDDLE'));
      expect(typesCode, contains('VERY_LOW'));
      expect(typesCode, contains('LOW'));

      // Should generate the converter class
      expect(typesCode, contains('class BalanceLevelEnumConverter'));
      expect(typesCode, contains('BalanceLevelEnum fromJson'));
      expect(typesCode, contains('String toJson'));

      print('✅ Enum and converter correctly generated');
    });

    test('should handle complex types with multiple camelCase fields', () {
      const schema = '''
        type ComplexDTO {
          simpleField: String!
          camelCaseField: String!
          anotherCamelCaseField: Int!
          yetAnotherField: Boolean!
        }
      ''';

      final typesCode = TypeGenerator.generateTypesFile(schema);

      // Should preserve all camelCase field names
      expect(typesCode, contains('String simpleField;'));
      expect(typesCode, contains('String camelCaseField;'));
      expect(typesCode, contains('@SafeIntConverter()'));
      expect(typesCode, contains('int anotherCamelCaseField;'));
      expect(typesCode, contains('@SafeBoolConverter()'));
      expect(typesCode, contains('bool yetAnotherField;'));

      // Should use fieldRename: FieldRename.none
      expect(typesCode, contains('fieldRename: FieldRename.none'));

      print('✅ Multiple camelCase fields preserved correctly');
    });
  });
}
