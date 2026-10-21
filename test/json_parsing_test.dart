import 'package:test/test.dart';

void main() {
  group('JSON Parsing Tests for Generated Types', () {
    test('should handle null boolean fields gracefully', () {
      // Simulate the actual JSON that causes the error
      final problematicJson = {
        'id': 390008,
        'name': 'category',
        'description': 'category description',
        'sectionId': 10,
        'parentId': 1007,
        'hasChildren': null, // This causes the error
        'isFeatured': false,
        'rank': 0,
        'productsCount': 1,
      };

      // This should not throw an error but currently does
      expect(() {
        // Simulating what happens in _$CategoryDTOFromJson
        final hasChildren = problematicJson['hasChildren'] as bool;
        print('hasChildren: $hasChildren');
      }, throwsA(isA<TypeError>()));

      // Proper handling should be:
      final hasChildrenSafe = problematicJson['hasChildren'] as bool? ?? false;
      expect(hasChildrenSafe, equals(false));
    });

    test('should handle valid boolean fields correctly', () {
      final validJson = {
        'id': 390008,
        'name': 'category',
        'description': 'category description',
        'sectionId': 10,
        'parentId': 1007,
        'hasChildren': true,
        'isFeatured': false,
        'rank': 0,
        'productsCount': 1,
      };

      // This should work fine
      final hasChildren = validJson['hasChildren'] as bool;
      final isFeatured = validJson['isFeatured'] as bool;

      expect(hasChildren, equals(true));
      expect(isFeatured, equals(false));
    });
  });
}
