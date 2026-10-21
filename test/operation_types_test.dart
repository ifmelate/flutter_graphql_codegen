import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

const _schema = r'''
interface Node { id: ID! }
type User implements Node {
  id: ID!
  "Display name."
  name: String!
  email: String
  friends: [User!]!
  best: User
}
type Post implements Node { id: ID! title: String! }
type Ad { id: ID! }
union SearchResult = User | Post | Ad
type Query {
  me: User!
  node(id: ID!): Node
  search: [SearchResult!]!
  version: String
}
''';

/// Generates the operation file of [name] in [document] (strict
/// nullability, operation result types).
String _op(String document, String name, {String fragments = ''}) {
  final all = DocumentUtils.collectFragments(
      [gql_lang.parseString('$document\n$fragments')]);
  final types = TypeGenerator.generateTypesFile(_schema);
  return GraphQLCodeGenerator.generateOperationFile(
      _schema, document, name, 'query', types,
      fragments: all);
}

String? _fragments(String document) =>
    GraphQLCodeGenerator.generateFragmentsFile(_schema,
        DocumentUtils.collectFragments([gql_lang.parseString(document)]));

void main() {
  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
  });
  tearDown(CodegenConfigContext.reset);

  group('classes', () {
    test('are named after the path of response keys', () {
      final code = _op('query GetMe { me { id friends { id } } }', 'GetMe');
      expect(code, contains('GetMe_Me parseGetMeData('));
      expect(code, contains('class GetMe_Me {'));
      expect(code, contains('final List<GetMe_Me_Friends> friends;'));
      expect(code, contains('class GetMe_Me_Friends {'));
      expect(code, isNot(contains('GetMeResult')));
    });

    test('several root fields get a result class without typename', () {
      final code = _op('query Both { me { id } version }', 'Both');
      expect(code, contains('BothResult parseBothData('));
      final result = code.substring(code.indexOf('class BothResult {'));
      expect(result.substring(0, result.indexOf('\n}')),
          isNot(contains('typename')));
    });

    test('hold exactly the selected fields', () {
      final code = _op('query GetMe { me { id } }', 'GetMe');
      expect(code, contains('final String id;'));
      expect(code, contains('final String typename;'));
      expect(code, isNot(contains(' name')));
    });

    test('merge fields selected more than once', () {
      final code = _op(
          'query M { me { best { id } best { name } ... on User { email } } }',
          'M');
      expect(code, contains('final M_Me_Best? best;'));
      expect('final M_Me_Best? best;'.allMatches(code), hasLength(1));
      expect(code, contains('final String name;'));
      expect(code, contains('final String? email;'));
    });

    test('@skip and @include make fields nullable', () {
      final code = _op(
          r'query C($x: Boolean!) { me { name @include(if: $x) '
              r'... on User @skip(if: $x) { id } } }',
          'C');
      expect(code, contains('final String? name;'));
      expect(code, contains('final String? id;'));
    });

    test('a field also selected unconditionally stays non-null', () {
      final code =
          _op(r'query C($x: Boolean!) { me { id id @skip(if: $x) } }', 'C');
      expect(code, contains('final String id;'));
    });

    test('subfields of a conditional field depend only on it', () {
      final code = _op(
          r'query C($x: Boolean!) { me { best @include(if: $x) { id } } }',
          'C');
      expect(code, contains('final C_Me_Best? best;'));
      final best = code.substring(code.indexOf('class C_Me_Best {'));
      expect(best, contains('final String id;'));
    });

    test('legacy nullability makes every level nullable', () {
      CodegenConfigContext.strictNullability = false;
      final code = _op('query GetMe { me { id friends { id } } }', 'GetMe');
      expect(code, contains('GetMe_Me? parseGetMeData('));
      expect(code, contains('final List<GetMe_Me_Friends?>? friends;'));
      expect(code, contains('final String? id;'));
      expect(code, contains('final String typename;'));
    });

    test('name clashes get a numeric suffix', () {
      final code = _op('query A { user: me { id } User: me { name } }', 'A');
      expect(code, contains('class A_User {'));
      expect(code, contains('class A_User_2 {'));
    });

    test('a field named typename does not clash with __typename', () {
      final code = _op('query A { me { typename: name } }', 'A');
      expect(code, contains('final String typename;'));
      expect(code, contains('final String typename_;'));
      expect(
          code,
          contains("typename_: const SafeStringConverter()"
              ".fromJson(json['typename'])"));
    });

    test('carry schema descriptions', () {
      final code = _op('query A { me { name } }', 'A');
      expect(code, contains('  /// Display name.\n  final String name;'));
    });

    test('have toJson, ==, hashCode and a typed copyWith', () {
      final code = _op('query A { me { id email } }', 'A');
      expect(code, contains("'__typename': typename,"));
      expect(code, contains('bool operator ==(Object other) =>'));
      expect(code, contains('int get hashCode => Object.hashAll(['));
      expect(code, contains('A_Me_CopyWith get copyWith => _A_Me_CopyWith('));
      expect(
          code,
          contains('A_Me call({\n    String? typename,\n    String? id,\n'
              '    String? email,\n  });'));
      expect(
          code,
          contains('email: identical(email, _undefined) '
              '? _value.email : email as String?,'));
      expect('const _undefined = Object();'.allMatches(code), hasLength(1));
    });

    test('unknown fields are dynamic with validate_documents: false', () {
      CodegenConfigContext.validateDocuments = false;
      final code = _op('query A { me { nope } }', 'A');
      expect(code, contains('final dynamic nope;'));
    });

    test('unknown fields are reported', () {
      expect(
          () => _op('query A { me { nope } }', 'A'),
          throwsA(
              isA<CodegenException>().having((e) => e.code, 'code', 'BLD103')));
    });
  });

  group('abstract types', () {
    test('become a sealed class with variants and _Other', () {
      final code = _op(
          'query S { search { ... on User { name } ... on Node { id } } }',
          'S');
      expect(code, contains('sealed class S_Search {'));
      expect(code, contains("'Post' => S_Search_OnPost.fromJson(json),"));
      expect(code, contains("'User' => S_Search_OnUser.fromJson(json),"));
      expect(code, contains('_ => S_Search_Other.fromJson(json),'));
      expect(code, contains('class S_Search_OnUser implements S_Search {'));
      expect(code, contains('class S_Search_Other implements S_Search {'));
      // Ad has no fields of its own here.
      expect(code, isNot(contains('S_Search_OnAd')));
    });

    test('common fields are getters of the sealed class', () {
      final code =
          _op('query N { node(id: "1") { id ... on User { name } } }', 'N');
      final base = code.substring(code.indexOf('sealed class N_Node {'));
      expect(
          base.substring(0, base.indexOf('\n}')),
          allOf(contains('String get id;'), contains('String get typename;'),
              isNot(contains('get name'))));
    });

    test('variants have their own nested classes', () {
      final code = _op(
          'query N { node(id: "1") { ... on User { best { id } } '
              '... on Node { id } } }',
          'N');
      expect(code, contains('class N_Node_OnUser_Best {'));
    });
  });

  group('fragments', () {
    const bits = 'fragment UserBits on User { id name friends { id } }';

    test('classes implement the fragment interface and its nested ones', () {
      final code =
          _op('query A { me { ...UserBits email } }', 'A', fragments: bits);
      expect(code, contains("import 'fragments.dart';"));
      expect(code, contains('class A_Me implements UserBits {'));
      expect(
          code, contains('class A_Me_Friends implements UserBits_Friends {'));
      expect(code, contains('  @override\n  final String name;'));
    });

    test('a conditional spread is not implemented', () {
      final code = _op(
          r'query A($x: Boolean!) { me { ...UserBits @include(if: $x) } }', 'A',
          fragments: bits);
      expect(code, contains('class A_Me {'));
      expect(code, contains('final String? name;'));
      expect(code, isNot(contains("import 'fragments.dart';")));
    });

    test('fragments.dart has documents, interfaces and data classes', () {
      final code = _fragments('$bits\n'
          'fragment NodeBits on Node { id ... on User { ...UserBits } }')!;
      expect(code, contains('final userBitsFragment = graphql.gql('));
      expect(code, contains("const String userBitsFragmentName = 'UserBits';"));
      expect(code, contains('abstract interface class UserBits {'));
      expect(code, contains('abstract interface class UserBits_Friends {'));
      expect(code, contains('class UserBitsData implements UserBits {'));
      expect(code, contains('abstract interface class NodeBits {'));
      expect(
          code,
          contains('abstract interface class NodeBits_OnUser '
              'implements NodeBits, UserBits {'));
      expect(code, contains('sealed class NodeBitsData implements NodeBits {'));
      expect(
          code,
          contains('class NodeBitsData_OnUser '
              'implements NodeBitsData, NodeBits_OnUser {'));
      // The NodeBits document includes the fragment it uses.
      final nodeDoc = code.substring(code.indexOf('nodeBitsFragment ='));
      expect(nodeDoc.substring(0, nodeDoc.indexOf('""")')),
          contains('fragment UserBits on User'));
    });

    test('no fragments, no fragments.dart', () {
      expect(_fragments('query A { version }'), isNull);
    });

    test('fragments generating the same name are reported', () {
      expect(
          () => _fragments('fragment A on User { best { id } }\n'
              'fragment A_Best on User { id }'),
          throwsA(
              isA<CodegenException>().having((e) => e.code, 'code', 'BLD102')));
    });

    test('fragments get typed cache methods on GraphQLClient', () {
      final code = _fragments(bits)!;
      expect(
          code,
          contains('extension UserBitsFragmentExtension '
              'on graphql.GraphQLClient {'));
      expect(code, contains('  UserBitsData? readUserBitsFragment(\n'));
      expect(code, contains('  void writeUserBitsFragment(\n'));
      expect(code, contains('    UserBits data, {\n'));
      expect(code, contains('document: userBitsFragment,'));
      expect(code, contains('fragmentName: userBitsFragmentName,'));
      // Object type: __typename defaults to it on read and write.
      expect(
          RegExp(RegExp.escape("idFields: {'__typename': 'User', ...idFields}"))
              .allMatches(code),
          hasLength(2));
      expect(code, contains('data: data.toJson(),'));
      expect(code, contains('variables: variables ?? const {},'));
      expect(code, isNot(contains('ArgumentError')));
    });

    test('fragments on abstract types need __typename on read', () {
      final code = _fragments('fragment NodeBits on Node { id }')!;
      expect(code, contains('  NodeBitsData? readNodeBitsFragment(\n'));
      expect(code, contains("if (!idFields.containsKey('__typename')) {"));
      expect(code, contains('throw ArgumentError.value('));
      expect(code,
          contains("idFields: {'__typename': data.typename, ...idFields},"));
    });

    test('fragment cache methods are named after the GraphQL name', () {
      final code = _fragments('fragment userBits on User { id }')!;
      expect(code, contains('extension UserBitsFragmentExtension'));
      expect(code, contains('readUserBitsFragment('));
      expect(code, contains('writeUserBitsFragment('));
    });

    test('fragments on introspection types are skipped', () {
      const fullType = 'fragment FullType on __Type { name kind '
          'fields { name } ...TypeRef }\n'
          'fragment TypeRef on __Type { name ofType { name } }';
      final code = _fragments('$fullType\n$bits')!;
      expect(code, isNot(contains('FullType')));
      expect(code, isNot(contains('TypeRef')));
      expect(code, contains('abstract interface class UserBits {'));
      // Only introspection fragments: no fragments.dart at all.
      expect(_fragments(fullType), isNull);
      // Operations using them keep their raw JSON result.
      final op = _op('query Introspect { __schema { types { ...FullType } } }',
          'Introspect',
          fragments: fullType);
      expect(op, contains('Map<String, dynamic>? parseIntrospectData('));
      expect(op, contains('fragment FullType on __Type'));
      expect(op, isNot(contains("import 'fragments.dart';")));
    });

    test('fragments on the root type have no typename', () {
      final code = _fragments('fragment Root on Query { version }')!;
      final root =
          code.substring(code.indexOf('abstract interface class Root'));
      expect(
          root.substring(0, root.indexOf('\n}')), isNot(contains('typename')));
    });
  });

  test('output is deterministic', () {
    const document = 'query S { search { ... on User { name best { id } } '
        '...P } }';
    const fragments = 'fragment P on Post { id title }';
    expect(_op(document, 'S', fragments: fragments),
        _op(document, 'S', fragments: fragments));
    expect(_fragments(fragments), _fragments(fragments));
  });

  test('result_types: schema keeps the schema classes', () {
    CodegenConfigContext.resultTypes = 'schema';
    final code = _op('query GetMe { me { id } }', 'GetMe');
    expect(code, contains('User parseGetMeData('));
    expect(code, isNot(contains('GetMe_Me')));
  });
}
