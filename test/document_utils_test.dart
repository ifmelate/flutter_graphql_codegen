import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/naming.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

OperationDefinitionNode _op(String source) => gql_lang
    .parseString(source)
    .definitions
    .whereType<OperationDefinitionNode>()
    .single;

void main() {
  group('buildOperationDocument', () {
    test('adds __typename to nested selections but not the root', () {
      final doc = DocumentUtils.buildOperationDocument(
          _op('query Q { user { id posts { title } } }'), const {});
      final printed = gql_lang.printNode(doc);

      expect('__typename'.allMatches(printed).length, 2);
      expect(printed, startsWith('query Q {\n  user {'));
    });

    test('does not duplicate an existing __typename', () {
      final doc = DocumentUtils.buildOperationDocument(
          _op('query Q { user { __typename id } }'), const {});
      expect('__typename'.allMatches(gql_lang.printNode(doc)).length, 1);
    });

    test('keeps directives, aliases and arguments', () {
      final doc = DocumentUtils.buildOperationDocument(
          _op(r'query Q($s: Boolean!) { me: user(id: "1") @skip(if: $s) { id } }'),
          const {});
      final printed = gql_lang.printNode(doc);
      expect(printed, contains('me: user(id: "1") @skip(if: \$s)'));
    });

    test('includes only fragments used, transitively and sorted', () {
      final fragments = DocumentUtils.collectFragments([
        gql_lang.parseString('''
          fragment B on User { id ...A }
          fragment A on User { name }
          fragment Unused on User { id }
        '''),
      ]);
      final doc = DocumentUtils.buildOperationDocument(
          _op('query Q { user { ...B } }'), fragments);
      final names = doc.definitions
          .whereType<FragmentDefinitionNode>()
          .map((f) => f.name.value);
      expect(names, ['A', 'B']);
    });

    test('throws BLD101 for unknown fragments', () {
      expect(
        () => DocumentUtils.buildOperationDocument(
            _op('query Q { user { ...Missing } }'), const {}),
        throwsA(isA<CodegenException>().having(
            (e) => e.code, 'code', CodegenErrorCodes.buildMissingFragment)),
      );
    });
  });

  test('collectFragments rejects conflicting duplicates', () {
    expect(
      () => DocumentUtils.collectFragments([
        gql_lang.parseString('fragment F on User { id }'),
        gql_lang.parseString('fragment F on User { name }'),
      ]),
      throwsA(isA<CodegenException>().having(
          (e) => e.code, 'code', CodegenErrorCodes.buildDuplicateFragment)),
    );
  });

  test('mergeSchemaExtensions folds extensions into base types', () {
    final merged = DocumentUtils.mergeSchemaExtensions(gql_lang.parseString('''
      type Query { a: String }
      extend type Query { b: String }
      enum Color { RED }
      extend enum Color { BLUE }
      extend type Mutation { c: String }
    '''));

    final query = merged.definitions
        .whereType<ObjectTypeDefinitionNode>()
        .firstWhere((d) => d.name.value == 'Query');
    expect(query.fields.map((f) => f.name.value), ['a', 'b']);

    final color = merged.definitions.whereType<EnumTypeDefinitionNode>().single;
    expect(color.values.map((v) => v.name.value), ['RED', 'BLUE']);

    expect(
        merged.definitions
            .whereType<ObjectTypeDefinitionNode>()
            .any((d) => d.name.value == 'Mutation'),
        isTrue);
    expect(merged.definitions.whereType<TypeExtensionNode>(), isEmpty);
  });

  group('identifier escaping', () {
    test('escapes reserved words and clashing members', () {
      expect(dartFieldName('class'), 'class_');
      expect(dartFieldName('hashCode'), 'hashCode_');
      expect(dartFieldName('toJson'), 'toJson_');
      expect(dartFieldName('User', className: 'User'), 'User_');
      expect(dartFieldName('name'), 'name');
    });

    test('escapes enum values clashing with Enum members', () {
      expect(dartEnumValueName('default'), 'default_');
      expect(dartEnumValueName('values'), 'values_');
      expect(dartEnumValueName('name'), 'name_');
      expect(dartEnumValueName('ACTIVE'), 'ACTIVE');
    });
  });
}
