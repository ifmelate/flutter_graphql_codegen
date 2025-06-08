import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

void main() {
  group('JSON Field Naming Tests', () {
    test(
        'should preserve camelCase field names using fieldRename: FieldRename.none',
        () {
      const schema = '''
        type AccountAmountDTO {
          value: Decimal!
          accountValueType: AccountValueTypeEnum!
        }
        
        enum AccountValueTypeEnum {
          HIGH
          MIDDLE
          PRE_LOW
          LOW
        }
        
        scalar Decimal
      ''';

      final typesCode = TypeGenerator.generateTypesFile(schema);

      // The generated code should use fieldRename: FieldRename.none to preserve original field names
      expect(typesCode, contains('fieldRename: FieldRename.none'));

      // Should contain the AccountAmountDTO class
      expect(typesCode, contains('class AccountAmountDTO'));

      // Should contain the accountValueType field (camelCase preserved)
      expect(typesCode, contains('AccountValueTypeEnum accountValueType;'));

      // Should have proper enum converter
      expect(typesCode, contains('@AccountValueTypeEnumConverter()'));

      // Should have proper decimal converter
      expect(typesCode, contains('@SafeDecimalConverter()'));

      print('✅ Generated types code includes fieldRename: FieldRename.none');
      print('✅ AccountAmountDTO class correctly generated');
      print('✅ accountValueType field preserved in camelCase');
    });

    test('should generate enum converter with correct naming', () {
      const schema = '''
        enum AccountValueTypeEnum {
          HIGH
          MIDDLE
          PRE_LOW
          LOW
        }
      ''';

      final typesCode = TypeGenerator.generateTypesFile(schema);

      // Should generate the enum
      expect(typesCode, contains('enum AccountValueTypeEnum'));
      expect(typesCode, contains('HIGH'));
      expect(typesCode, contains('MIDDLE'));
      expect(typesCode, contains('PRE_LOW'));
      expect(typesCode, contains('LOW'));

      // Should generate the converter class
      expect(typesCode, contains('class AccountValueTypeEnumConverter'));
      expect(typesCode, contains('AccountValueTypeEnum fromJson'));
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
