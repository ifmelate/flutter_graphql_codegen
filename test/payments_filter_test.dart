import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';

void main() {
  group('Payments Real World Test', () {
    test('should correctly handle PaymentsInput with LocalDate fields', () {
      const schema = '''
        scalar LocalDate
        scalar DateTime  
        scalar Decimal

        enum PeriodFilterEnum {
          ALL_TIME
          LAST_YEAR
          CUSTOM_PERIOD
        }

        input PaymentsInput {
          filterType: PeriodFilterEnum!
          dateFrom: LocalDate
          dateTo: LocalDate
        }

        type Payment {
          id: Int!
          value: Decimal!
          userId: Int!
          createdDate: DateTime!
        }

        type PaymentsResult {
          operations: [Payment!]!
          totalCount: Int!
        }

        type Query {
          payments(input: PaymentsInput!): PaymentsResult
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      print('Generated types:');
      print(generatedTypes);

      // Check LocalDateConverter is generated
      expect(generatedTypes, contains('LocalDateConverter'));

      // Check PaymentsInput class uses LocalDateConverter
      expect(generatedTypes, contains('class PaymentsInput'));
      expect(generatedTypes, contains('@_NullableLocalDateConverter()'));

      // Specifically check for dateFrom and dateTo fields with LocalDateConverter
      final paymentsInputRegex = RegExp(
        r'class PaymentsInput[\s\S]*?}[\s\S]*?}',
        multiLine: true,
      );

      final match = paymentsInputRegex.firstMatch(generatedTypes);
      expect(match, isNotNull);

      final paymentsInputCode = match!.group(0)!;
      print('PaymentsInput code:');
      print(paymentsInputCode);

      // Check that dateFrom and dateTo use LocalDateConverter, not DateTimeConverter
      expect(paymentsInputCode, contains('dateFrom'));
      expect(paymentsInputCode, contains('dateTo'));

      // Use more specific regex to find the converter for dateFrom/dateTo
      // Look for the annotation immediately before the field
      final dateFromRegex = RegExp(
          r"@JsonKey\(name: 'dateFrom'\)\s+@(\w+Converter)\(\)\s+DateTime\?\s+dateFrom");
      final dateToRegex = RegExp(
          r"@JsonKey\(name: 'dateTo'\)\s+@(\w+Converter)\(\)\s+DateTime\?\s+dateTo");

      final dateFromMatch = dateFromRegex.firstMatch(paymentsInputCode);
      final dateToMatch = dateToRegex.firstMatch(paymentsInputCode);

      expect(dateFromMatch, isNotNull,
          reason: 'dateFrom field should have a converter');
      expect(dateToMatch, isNotNull,
          reason: 'dateTo field should have a converter');

      final dateFromConverter = dateFromMatch!.group(1)!;
      final dateToConverter = dateToMatch!.group(1)!;

      print('dateFrom converter: $dateFromConverter');
      print('dateTo converter: $dateToConverter');

      // Both should use LocalDateConverter, not DateTimeConverter
      expect(dateFromConverter, equals('_NullableLocalDateConverter'));
      expect(dateToConverter, equals('_NullableLocalDateConverter'));
    });
  });
}
