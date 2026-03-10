import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';

void main() {
  group('LocalDate Converter Tests', () {
    setUp(() {
      CodegenConfigContext.strictNullability = true;
    });

    tearDown(() {
      CodegenConfigContext.reset();
    });
    test('should generate LocalDateConverter for LocalDate scalar fields', () {
      const schema = '''
        scalar LocalDate

        input FinanceOperationsInput {
          filterType: DateFilterTypeEnum!
          dateFrom: LocalDate
          dateTo: LocalDate
        }

        type Query {
          financeOperations(input: FinanceOperationsInput!): FinanceOperationsResult
        }

        type FinanceOperationsResult {
          operations: [FinanceOperation!]!
          dateFrom: LocalDate
          dateTo: LocalDate
        }

        type FinanceOperation {
          value: Decimal!
          userId: Int!
          createdDate: DateTime!
        }

        enum DateFilterTypeEnum {
          ALL_TIME
          LAST_YEAR
          CUSTOM_PERIOD
        }

        scalar DateTime
        scalar Decimal
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // Check that LocalDateConverter class is generated
      expect(
          generatedTypes,
          contains(
              'class LocalDateConverter implements JsonConverter<DateTime, dynamic>'));

      // Check that LocalDateConverter toJson method returns date-only format
      expect(
          generatedTypes,
          contains(
              'String toJson(DateTime object) => object.toIso8601String().split(\'T\').first;'));

      // Check that FinanceOperationsInput uses LocalDateConverter for dateFrom and dateTo
      expect(generatedTypes, contains('@LocalDateConverter()'));

      // Check that helper functions for LocalDate lists are generated
      expect(generatedTypes, contains('_localDateListFromJson'));
      expect(generatedTypes, contains('_localDateListToJson'));

      // Verify the content contains FinanceOperationsInput class
      expect(generatedTypes, contains('class FinanceOperationsInput'));
    });

    test('should distinguish between DateTime and LocalDate converters', () {
      const schema = '''
        scalar DateTime
        scalar LocalDate

        type TestType {
          fullDateTime: DateTime!
          dateOnly: LocalDate!
        }

        input TestInput {
          fullDateTime: DateTime!
          dateOnly: LocalDate!
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // Check that both converters are generated
      expect(
          generatedTypes,
          contains(
              'class DateTimeConverter implements JsonConverter<DateTime, dynamic>'));
      expect(
          generatedTypes,
          contains(
              'class LocalDateConverter implements JsonConverter<DateTime, dynamic>'));

      // Check that DateTimeConverter returns full ISO string with UTC conversion
      expect(
          generatedTypes, contains('return object.toUtc().toIso8601String();'));

      // Check that LocalDateConverter returns date-only format
      expect(
          generatedTypes,
          contains(
              'String toJson(DateTime object) => object.toIso8601String().split(\'T\').first;'));

      // Verify that proper converters are applied to fields
      final lines = generatedTypes.split('\n');
      var foundDateTimeConverter = false;
      var foundLocalDateConverter = false;

      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('@DateTimeConverter()')) {
          foundDateTimeConverter = true;
        }
        if (lines[i].contains('@LocalDateConverter()')) {
          foundLocalDateConverter = true;
        }
      }

      expect(foundDateTimeConverter, isTrue,
          reason: 'DateTimeConverter should be used for DateTime fields');
      expect(foundLocalDateConverter, isTrue,
          reason: 'LocalDateConverter should be used for LocalDate fields');
    });

    test('should handle list of LocalDate correctly', () {
      const schema = '''
        scalar LocalDate

        type TestType {
          dates: [LocalDate!]!
          optionalDates: [LocalDate]
        }

        input TestInput {
          dates: [LocalDate!]!
          optionalDates: [LocalDate]
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // Check that helper functions for LocalDate lists are generated
      expect(
          generatedTypes,
          contains(
              'List<DateTime>? _localDateListFromJson(List<dynamic>? json)'));
      expect(generatedTypes,
          contains('List<String>? _localDateListToJson(List<DateTime>? list)'));

      // Check that helper function returns date-only format
      expect(
          generatedTypes,
          contains(
              'return list.map((item) => item.toIso8601String().split(\'T\').first).toList();'));

      // Check that list fields use proper JsonKey annotations
      expect(
          generatedTypes,
          contains(
              'fromJson: _localDateListFromJson, toJson: _localDateListToJson'));
    });

    test('should generate correct Dart types for LocalDate', () {
      const schema = '''
        scalar LocalDate

        type TestType {
          requiredDate: LocalDate!
          optionalDate: LocalDate
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // LocalDate should be mapped to DateTime in Dart
      expect(generatedTypes, contains('DateTime requiredDate;'));
      expect(generatedTypes, contains('DateTime? optionalDate;'));
    });

    test('should handle complex input with mixed date types', () {
      const schema = '''
        scalar DateTime
        scalar LocalDate

        input ComplexInput {
          filterType: DateFilterTypeEnum!
          dateFrom: LocalDate
          dateTo: LocalDate
          createdAt: DateTime!
          updatedAt: DateTime
          timestamps: [DateTime!]!
          dates: [LocalDate]
        }

        enum DateFilterTypeEnum {
          ALL_TIME
          CUSTOM_PERIOD
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // Verify class is generated
      expect(generatedTypes, contains('class ComplexInput'));

      // Check proper field types
      expect(generatedTypes, contains('DateTime? dateFrom;'));
      expect(generatedTypes, contains('DateTime? dateTo;'));
      expect(generatedTypes, contains('DateTime createdAt;'));
      expect(generatedTypes, contains('DateTime? updatedAt;'));
      expect(generatedTypes, contains('List<DateTime> timestamps;'));
      expect(generatedTypes, contains('List<DateTime?>? dates;'));

      // Check that proper converters are applied
      final dateTimeConverterCount =
          '@DateTimeConverter()'.allMatches(generatedTypes).length;
      final localDateConverterCount =
          '@LocalDateConverter()'.allMatches(generatedTypes).length;

      expect(dateTimeConverterCount, greaterThan(0),
          reason: 'Should have DateTime converters');
      expect(localDateConverterCount, greaterThan(0),
          reason: 'Should have LocalDate converters');
    });
  });
}
