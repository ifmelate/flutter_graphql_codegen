import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:test/test.dart';

import 'support/masking_fixture.dart';

/// The declaration of class [name] in [code], up to the next top-level one.
String _class(String code, String name) {
  final start = code.indexOf(RegExp('^class $name ', multiLine: true));
  expect(start, isNot(-1), reason: 'class $name');
  final end = code.indexOf(RegExp(r'^\S', multiLine: true), start + 1);
  return code.substring(start, end == -1 ? code.length : end);
}

const _config = '''
schema_url: schema.graphql
document_paths: [lib/**.graphql]
''';

void main() {
  group('fragment_masking', () {
    final masked = generateMasked();
    final plain = generateMasked(masking: false);

    test('a spread becomes one member with the fragment data', () {
      final me = _class(masked['Me.g.dart']!, 'Me_Me');
      expect(me, contains('final UserCard userCard;'));
      expect(me, contains('userCard: UserCardData.fromJson(json),'));
      expect(me, isNot(contains('implements')));
      // The fragment's fields stay in the fragment.
      expect(me, isNot(contains(' name')));
      expect(me, isNot(contains('avatar')));
    });

    test('without it, the class implements the fragment', () {
      final me = _class(plain['Me.g.dart']!, 'Me_Me');
      expect(me, contains('implements UserCard'));
      expect(me, contains('final String name;'));
      expect(me, isNot(contains('_mergeJson')));
      expect(plain['fragments.dart'], isNot(contains('_mergeJson')));
    });

    test('fragments mask the fragments they spread', () {
      final data = _class(masked['fragments.dart']!, 'UserCardData');
      expect(data, contains('implements UserCard'));
      expect(data, contains('final AvatarBits avatarBits;'));
      expect(data, isNot(contains('avatar:')));
      expect(masked['fragments.dart'],
          contains('Map<String, dynamic> _mergeJson('));
    });

    test('a conditional spread is not masked', () {
      final code = masked['Conditional.g.dart']!;
      expect(code, contains('final String? avatar;'));
      expect(code, isNot(contains('avatarBits')));
    });

    test('a fragment-only operation keeps a result class', () {
      final code = masked['MeOnly.g.dart']!;
      expect(code, contains('MeOnlyResult parseMeOnlyData('));
      expect(code, contains('final RootBits rootBits;'));
    });

    test('is read from the config and ignored for schema result types', () {
      expect(
          GraphQLCodegenConfig.fromYaml('${_config}fragment_masking: true')
              .fragmentMasking,
          isTrue);
      final schema = GraphQLCodegenConfig.fromYaml(
          '${_config}result_types: schema\nfragment_masking: true');
      expect(schema.fragmentMasking, isFalse);
      expect(schema.warnings.join(), contains('fragment_masking'));
    });
  });
}
