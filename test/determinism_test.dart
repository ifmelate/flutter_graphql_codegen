import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';

void main() {
  group('Deterministic generation', () {
    test('same schema produces identical output', () {
      const schema = '''
        enum E { B, A, C }
        type T { b: String, a: Int!, c: Float }
      ''';

      final a = TypeGenerator.generateTypesFile(schema);
      final b = TypeGenerator.generateTypesFile(schema);

      expect(a, equals(b));
    });

    test('enum values are sorted for stability', () {
      const schema = 'enum Status { PENDING, ACTIVE, DELETED }';
      final code = TypeGenerator.generateTypesFile(schema);
      final idx = code.indexOf('enum Status');
      final slice = code.substring(idx, idx + 120);
      expect(slice, contains('ACTIVE'));
      expect(slice, contains('DELETED'));
      expect(slice, contains('PENDING'));
      // Order check by index positions
      expect(slice.indexOf('ACTIVE') < slice.indexOf('DELETED'), isTrue);
      expect(slice.indexOf('DELETED') < slice.indexOf('PENDING'), isTrue);
    });
  });
}
