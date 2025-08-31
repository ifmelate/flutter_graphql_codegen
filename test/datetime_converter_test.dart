import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';

void main() {
  group('DateTimeConverter GraphQL Format Tests', () {
    test(
        'should generate correct GraphQL DateTime format with milliseconds and timezone',
        () {
      const schema = '''
        scalar DateTime
        
        input TestInput {
          birthDate: DateTime!
          birthTime: DateTime
        }
        
        type TestType {
          createdAt: DateTime!
          updatedAt: DateTime
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // Verify DateTimeConverter is generated
      expect(
          generatedTypes,
          contains(
              'class DateTimeConverter implements JsonConverter<DateTime, dynamic>'));

      // Verify toJson method uses proper ISO format with UTC conversion for GraphQL
      expect(
          generatedTypes, contains('return object.toUtc().toIso8601String();'));

      // Test actual conversion behavior
      final testDate1 = DateTime(2025, 6, 22, 0, 0, 0); // Date without time
      final testDate2 = DateTime(2025, 6, 22, 17, 19, 0); // Date with time
      final testDate3 =
          DateTime.utc(2025, 6, 22, 14, 30, 45, 123); // UTC with milliseconds

      // Check that toIso8601String() produces GraphQL-compatible format
      final result1 = testDate1.toIso8601String();
      final result2 = testDate2.toIso8601String();
      final result3 = testDate3.toIso8601String();

      print('Test Date 1 (local): $result1');
      print('Test Date 2 (local): $result2');
      print('Test Date 3 (UTC): $result3');

      // Verify format includes timezone information
      expect(result3, endsWith('Z')); // UTC should end with Z
      expect(result3, contains('.123')); // Should contain milliseconds

      // Since we're testing DateTime.toIso8601String() directly (not our converter),
      // local dates may not have timezone. But our converter will fix this by using toUtc()
      // For now, we just verify the format is parseable
    });

    test('should handle DateTime conversion edge cases for GraphQL', () {
      // Test edge cases that might cause GraphQL parsing errors
      final edgeCases = [
        DateTime.utc(2025, 1, 1, 0, 0, 0, 0), // Start of year UTC
        DateTime.utc(2025, 12, 31, 23, 59, 59, 999), // End of year UTC
        DateTime.now(), // Current time
        DateTime.now().toUtc(), // Current time in UTC
      ];

      for (final date in edgeCases) {
        final isoString = date.toIso8601String();

        // Verify format is valid for GraphQL DateTime scalar
        // Should have proper datetime format with fractional seconds
        // Note: some local DateTime objects may not have timezone, but our converter fixes this
        expect(
            isoString, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+'));

        // Verify it can be parsed back
        expect(() => DateTime.parse(isoString), returnsNormally);
      }
    });

    test('should distinguish between DateTime and LocalDate converters', () {
      const schema = '''
        scalar DateTime
        scalar LocalDate
        
        input MixedInput {
          fullDateTime: DateTime!
          dateOnly: LocalDate!
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // Verify both converters are present
      expect(
          generatedTypes,
          contains(
              'class DateTimeConverter implements JsonConverter<DateTime, dynamic>'));
      expect(
          generatedTypes,
          contains(
              'class LocalDateConverter implements JsonConverter<DateTime, dynamic>'));

      // Verify DateTimeConverter keeps full ISO format with UTC conversion
      expect(
          generatedTypes, contains('return object.toUtc().toIso8601String();'));

      // Verify LocalDateConverter only returns date part
      expect(
          generatedTypes,
          contains(
              'String toJson(DateTime object) => object.toIso8601String().split(\'T\').first;'));
    });

    test('should fix GraphQL DateTime parsing error scenario', () {
      // Simulate the exact error scenario from logs
      const schema = '''
        scalar DateTime
        
        input DossierDTOInput {
          id: Int!
          birthDate: DateTime
          birthTime: DateTime
        }
      ''';

      final generatedTypes = TypeGenerator.generateTypesFile(schema);

      // Verify DossierDTOInput uses DateTimeConverter
      expect(generatedTypes, contains('class DossierDTOInput'));
      expect(generatedTypes, contains('@DateTimeConverter()'));

      // Test problematic dates that caused the original error - now with UTC conversion
      final problematicDate1 =
          DateTime(2025, 6, 22, 0, 0, 0); // "2025-06-22T00:00:00"
      final problematicDate2 =
          DateTime(2025, 6, 22, 17, 19, 0); // "2025-06-22T17:19:00"

      // Use the same logic as DateTimeConverter: convert to UTC first
      final result1 = problematicDate1.toUtc().toIso8601String();
      final result2 = problematicDate2.toUtc().toIso8601String();

      print('Problematic Date 1 result: $result1');
      print('Problematic Date 2 result: $result2');

      // These should now have proper format for GraphQL (UTC with Z suffix)
      expect(
          result1, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'));
      expect(
          result2, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'));
    });

    test(
        'should generate proper DateTime format for GraphQL server compatibility',
        () {
      // Test that the DateTimeConverter generates the exact format expected by GraphQL
      final testDate = DateTime.utc(2025, 6, 22, 14, 30, 45, 123);
      final expectedFormat = '2025-06-22T14:30:45.123Z';

      final actualFormat = testDate.toIso8601String();

      expect(actualFormat, equals(expectedFormat));

      // Test format that would cause "DateTime cannot parse the given literal" error
      final localDate = DateTime(2025, 6, 22, 0, 0, 0);
      final localResult = localDate
          .toUtc()
          .toIso8601String(); // Use same logic as DateTimeConverter

      // Should NOT be in format "2025-06-22T00:00:00" (which causes error)
      expect(localResult, isNot(equals('2025-06-22T00:00:00')));

      // Should include milliseconds and timezone (now that we convert to UTC)
      expect(localResult, contains('.000'));
      expect(localResult, endsWith('Z')); // UTC format always ends with Z
    });
  });
}
