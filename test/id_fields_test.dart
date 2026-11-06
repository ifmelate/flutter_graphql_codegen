// add_id_fields: `id` is selected on every object the cache can normalize.
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/id_fields.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

import 'support/id_fields_fixture.dart';

final _ids = IdFields(gql_lang.parseString(idSchema));

/// [operation] (the named operation of the fixture documents) after
/// `add_id_fields`, printed on one line.
String _rewritten(String operation) {
  for (final doc in idDocuments.map(gql_lang.parseString)) {
    for (final op in doc.definitions.whereType<OperationDefinitionNode>()) {
      if (op.name?.value == operation) return _flat(_ids.operation(op));
    }
  }
  throw ArgumentError(operation);
}

String _flat(Node node) =>
    gql_lang.printNode(node).replaceAll(RegExp(r'\s+'), ' ');

/// The document [code] embeds, on one line.
String _document(String code) {
  final match =
      RegExp(r'graphql\.gql\(r?"""(.*?)"""\)', dotAll: true).firstMatch(code);
  expect(match, isNotNull, reason: 'document in the generated code');
  return match!.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
}

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
  setUp(CodegenConfigContext.reset);
  tearDown(CodegenConfigContext.reset);

  group('IdFields', () {
    test('adds id to objects and nested objects, not to the root', () {
      expect(_rewritten('Me'),
          'query Me { me { id name friends { id name } ...UserName } }');
    });

    test('adds id to fragments', () {
      final fragment = gql_lang
          .parseString('fragment UserName on User { name }')
          .definitions
          .single as FragmentDefinitionNode;
      expect(_flat(_ids.fragment(fragment)),
          'fragment UserName on User { id name }');
    });

    test('leaves a selection that has id alone', () {
      expect(_rewritten('MeWithId'), 'query MeWithId { me { id name } }');
    });

    test('adds id next to an aliased id', () {
      expect(_rewritten('AliasedId'),
          'query AliasedId { me { id userId: id name } }');
    });

    test('skips a set where another field is aliased id', () {
      expect(_rewritten('Aliased'), 'query Aliased { me { id: name } }');
    });

    test('in a union, adds id to the members that have it', () {
      expect(
          _rewritten('Search'),
          'query Search { search { ... on User { id name } '
          '... on Post { id title } ... on Tag { name } } }');
    });

    test('on an interface with id, adds it once, not in inline fragments', () {
      expect(_rewritten('GetNode'),
          r'query GetNode($id: ID!) { node(id: $id) { id ... on User { name } } }');
    });

    test('on an interface without id, adds it to the inline fragments', () {
      expect(
          _rewritten('GetNamed'),
          'query GetNamed { named { name ... on User { id friends '
          '{ id name } } } }');
    });

    test('skips types without id and ids that need arguments', () {
      expect(_rewritten('NoIds'),
          'query NoIds { tags { name } comments { text } }');
    });

    test('takes an id of a custom scalar', () {
      expect(_rewritten('Orders'), 'query Orders { orders { id total } }');
    });

    test('adds id to mutation results', () {
      expect(
          _rewritten('Rename'),
          r'mutation Rename($id: ID!, $name: String!) '
          r'{ rename(id: $id, name: $name) { id name } }');
    });
  });

  group('keeps documents valid', () {
    const schema = r'''
interface Node { id: ID! }
type User implements Node { id: ID! name: String! friends: [User!]! }
type Post implements Node { id: ID! title: String! }
type Legacy { id: Int! title: String! }
type Draft { id: ID title: String! }
union Hit = User | Post
union Mixed = Post | Legacy | Draft
type Query { me: User! search: [Hit!]! mixed: [Mixed!]! node: Node }
''';

    /// [text] with `id` added to its operation and fragments, on one line.
    String rewrite(String text) {
      final doc = gql_lang.parseString(text);
      final ids = IdFields(
          gql_lang.parseString(schema), DocumentUtils.collectFragments([doc]));
      return [
        for (final d in doc.definitions)
          _flat(d is OperationDefinitionNode
              ? ids.operation(d)
              : ids.fragment(d as FragmentDefinitionNode)),
      ].join(' ');
    }

    test('an id alias in a spread fragment keeps id off the object', () {
      const text = 'query B { me { ...G } } fragment G on User { id: name }';
      expect(rewrite(text), text);
    });

    test('an id alias in an inline fragment keeps id off the object', () {
      const text = 'query C { me { ... on User { id: name } } }';
      expect(rewrite(text), text);
    });

    test('a fragment that gets id, spread next to an id alias, fails', () {
      expect(
          () => rewrite(
              'query A { me { id: name ...F } } fragment F on User { name }'),
          throwsA(isA<CodegenException>()
              .having((e) => e.code, 'code', 'BLD109')
              .having((e) => e.message, 'message', contains('"F"'))));
    });

    test('types whose union siblings have another id type get none', () {
      // Post shares Mixed with Legacy (Int!) and Draft (ID).
      const text = 'query D { mixed { ... on Post { title } '
          '... on Legacy { title } ... on Draft { title } } }';
      expect(rewrite(text), text);
      expect(
          rewrite('query E { search { ... on User { name } '
              '... on Post { title } } }'),
          'query E { search { ... on User { id name } '
          '... on Post { title } } }');
    });

    test('a fragment gets the same fields wherever it is spread', () {
      expect(
          rewrite('query N { node { ... on User { name } ...P } } '
              'fragment P on Post { title }'),
          'query N { node { id ... on User { name } ...P } } '
          'fragment P on Post { title }');
    });
  });

  group('generated code', () {
    final withIds = generateIds();
    final without = generateIds(addIds: false);

    test('the document and the result class select id', () {
      final code = withIds['UserName.g.dart']!;
      expect(
          _document(code), contains('user(id: \$id) { id name __typename }'));
      expect(_class(code, 'UserName_User'), contains('final String id;'));
    });

    test('fragments select id too', () {
      final code = withIds['fragments.dart']!;
      expect(_document(code), contains('fragment UserName on User { id name'));
      expect(code, contains('String get id;'));
    });

    test('nothing changes when off (the default)', () {
      expect(_document(without['UserName.g.dart']!),
          contains('user(id: \$id) { name __typename }'));
      expect(_class(without['UserName.g.dart']!, 'UserName_User'),
          isNot(contains('this.id')));
      expect(withIds['MeWithId.g.dart'], without['MeWithId.g.dart']);
    });

    test('persisted document ids hash the document with id', () {
      CodegenConfigContext.persistedDocumentsAlgorithm = 'sha256';
      CodegenConfigContext.addIdFields = true;
      final doc = idDocuments[2];
      final types = GraphQLCodeGenerator.generateTypesFile(idSchema);
      final on = GraphQLCodeGenerator.generateOperationFile(
          idSchema, doc, 'UserName', 'query', types);
      CodegenConfigContext.addIdFields = false;
      final off = GraphQLCodeGenerator.generateOperationFile(
          idSchema, doc, 'UserName', 'query', types);
      String id(String code) =>
          RegExp(r"userNameDocumentId = '(\w+)'").firstMatch(code)!.group(1)!;
      expect(id(on), isNot(id(off)));
    });

    test('prune_types keeps a custom scalar used only by an added id', () {
      final docs = ['query Orders { orders { total } }'];
      expect(GraphQLCodeGenerator.usedTypes(idSchema, docs),
          isNot(contains('Uuid')));
      CodegenConfigContext.addIdFields = true;
      expect(GraphQLCodeGenerator.usedTypes(idSchema, docs), contains('Uuid'));
    });
  });

  test('is read from the config, off by default', () {
    expect(GraphQLCodegenConfig.fromYaml(_config).addIdFields, isFalse);
    final config =
        GraphQLCodegenConfig.fromYaml('${_config}add_id_fields: true');
    expect(config.addIdFields, isTrue);
    expect(config.warnings, isEmpty);
  });
}
