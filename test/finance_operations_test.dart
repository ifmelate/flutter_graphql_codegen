import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';

void main() {
  group('FinanceOperations Real World Test', () {
    test('should correctly handle FinanceOperationsInput with LocalDate fields',
        () {
      const schema = '''
        scalar LocalDate
        scalar DateTime  
        scalar Decimal

        enum DateFilterTypeEnum {
          ALL_TIME
          LAST_YEAR
          CUSTOM_PERIOD
        }

        input FinanceOperationsInput {
          filterType: DateFilterTypeEnum!
          dateFrom: LocalDate
          dateTo: LocalDate
        }

        type FinanceOperation {
          id: Int!
          value: Decimal!
          userId: Int!
          createdDate: DateTime!
        }

        type FinanceOperationsResult {
          operations: [FinanceOperation!]!
          totalCount: Int!
        }

        type Query {
          financeOperations(input: FinanceOperationsInput!): FinanceOperationsResult
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      print('Generated types:');
      print(generatedTypes);

      // Check LocalDateConverter is generated
      expect(generatedTypes, contains('LocalDateConverter'));

      // Check FinanceOperationsInput class uses LocalDateConverter
      expect(generatedTypes, contains('class FinanceOperationsInput'));
      expect(generatedTypes, contains('@LocalDateConverter()'));

      // Specifically check for dateFrom and dateTo fields with LocalDateConverter
      final financeInputRegex = RegExp(
        r'class FinanceOperationsInput[\s\S]*?}[\s\S]*?}',
        multiLine: true,
      );

      final match = financeInputRegex.firstMatch(generatedTypes);
      expect(match, isNotNull);

      final financeInputCode = match!.group(0)!;
      print('FinanceOperationsInput code:');
      print(financeInputCode);

      // Check that dateFrom and dateTo use LocalDateConverter, not DateTimeConverter
      expect(financeInputCode, contains('dateFrom'));
      expect(financeInputCode, contains('dateTo'));

      // Use more specific regex to find the converter for dateFrom/dateTo
      // Look for the annotation immediately before the field
      final dateFromRegex = RegExp(
          r"@JsonKey\(name: 'dateFrom'\)\s+@(\w+Converter)\(\)\s+DateTime\?\s+dateFrom");
      final dateToRegex = RegExp(
          r"@JsonKey\(name: 'dateTo'\)\s+@(\w+Converter)\(\)\s+DateTime\?\s+dateTo");

      final dateFromMatch = dateFromRegex.firstMatch(financeInputCode);
      final dateToMatch = dateToRegex.firstMatch(financeInputCode);

      expect(dateFromMatch, isNotNull,
          reason: 'dateFrom field should have a converter');
      expect(dateToMatch, isNotNull,
          reason: 'dateTo field should have a converter');

      final dateFromConverter = dateFromMatch!.group(1)!;
      final dateToConverter = dateToMatch!.group(1)!;

      print('dateFrom converter: $dateFromConverter');
      print('dateTo converter: $dateToConverter');

      // Both should use LocalDateConverter, not DateTimeConverter
      expect(dateFromConverter, equals('LocalDateConverter'));
      expect(dateToConverter, equals('LocalDateConverter'));
    });
  });
}
