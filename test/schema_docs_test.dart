import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

const _schema = r'''
"""
A person using the app.

Second paragraph.
"""
type User implements Node {
  "Stable identifier."
  id: ID!
  name: String
  nick: String @deprecated(reason: "Use `name`.")
  login: String @deprecated
}

"Anything with an id."
interface Node {
  "Stable identifier."
  id: ID!
}

"What users can see."
enum Role {
  "Full access."
  ADMIN
  GUEST @deprecated(reason: "Removed in v3")
}

"Search hits."
union Hit = User

"Filter for users."
input UserFilter {
  "Exact name."
  name: String
  old: String @deprecated(reason: "Ignored")
}

type Query { me: User }
''';

void main() {
  late String types;

  setUpAll(() {
    CodegenConfigContext.reset();
    types = TypeGenerator.generateTypesFile(_schema);
  });

  test('type descriptions become doc comments', () {
    expect(
        types,
        contains('/// A person using the app.\n'
            '///\n'
            '/// Second paragraph.\n'
            '@JsonSerializable('));
    expect(types, contains('/// Anything with an id.\nabstract class Node'));
    expect(types, contains('/// What users can see.\nenum Role {'));
    expect(types, contains('/// Search hits.\nabstract class Hit {'));
    expect(types, contains('/// Filter for users.\n@JsonSerializable('));
  });

  test('field and enum value descriptions become doc comments', () {
    expect(types, contains('  /// Stable identifier.\n  @override\n'));
    expect(types, contains('  /// Stable identifier.\n  String get id;'));
    expect(types, contains('  /// Exact name.\n'));
    expect(types, contains('  /// Full access.\n  ADMIN,'));
  });

  test('@deprecated is documented by default, without annotations', () {
    expect(types, isNot(contains('@Deprecated(')));
    expect(types, contains('  /// Deprecated: Use `name`.\n'));
    expect(types, contains('  /// Deprecated: No longer supported\n'));
    expect(
        types,
        contains('  /// Full access.\n  ADMIN,\n'
            '  /// Deprecated: Removed in v3\n  GUEST,'));
  });

  test('a deprecation follows the description in the doc comment', () {
    final out = TypeGenerator.generateTypesFile(r'''
type Query { "Old field." a: String @deprecated(reason: "Gone") }
''');
    expect(out, contains('  /// Old field.\n  ///\n  /// Deprecated: Gone\n'));
  });

  test('types.dart ignores uses of its own deprecated members', () {
    expect(types, contains('deprecated_member_use_from_same_package'));
  });

  group('with deprecated_annotations', () {
    setUp(() => CodegenConfigContext.deprecatedAnnotations = true);
    tearDown(CodegenConfigContext.reset);

    test('@deprecated becomes @Deprecated with the reason', () {
      final out = TypeGenerator.generateTypesFile(_schema);
      expect(out, contains("  @Deprecated('Use `name`.')\n"));
      expect(out, contains("  @Deprecated('No longer supported')\n"));
      expect(out, contains("  @Deprecated('Removed in v3')\n  GUEST,"));
      expect(out, contains("  @Deprecated('Ignored')\n"));
    });

    test('quotes in deprecation reasons are escaped', () {
      final out = TypeGenerator.generateTypesFile(r'''
type Query { a: String @deprecated(reason: "Don't use $a\\b") }
''');
      expect(out, contains(r"@Deprecated('Don\'t use \$a\\b')"));
    });
  });
}
