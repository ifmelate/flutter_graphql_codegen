import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

const _schema = r'''
interface Node { id: ID! }
type User implements Node { id: ID! name: String! }
type Post implements Node { id: ID! title: String! }
type PageInfo { hasNextPage: Boolean! endCursor: String }
type UserConnection {
  edges: [UserEdge]
  nodes: [User]
  pageInfo: PageInfo!
}
type UserEdge { cursor: String! node: User }
type NodeConnection { edges: [NodeEdge!]! }
type NodeEdge { node: Node! }
type TagConnection { edges: [TagEdge!]! }
type TagEdge { node: String! }
type Query {
  users(first: Int): UserConnection!
  search: NodeConnection!
  tags: TagConnection!
}
''';

/// The operation file of [name] in [document] (plus [fragments]).
String _op(String document, String name, {String fragments = ''}) {
  final all = DocumentUtils.collectFragments(
      [gql_lang.parseString('$document\n$fragments')]);
  final types = TypeGenerator.generateTypesFile(_schema);
  return GraphQLCodeGenerator.generateOperationFile(
      _schema, document, name, 'query', types,
      fragments: all);
}

String _fragments(String document) =>
    GraphQLCodeGenerator.generateFragmentsFile(_schema,
        DocumentUtils.collectFragments([gql_lang.parseString(document)]))!;

/// The declaration of class (or interface) [name] in [code].
String _class(String code, String name) {
  final start = code.indexOf(RegExp('class $name[ {]'));
  expect(start, isNot(-1), reason: '$name not declared');
  final end = code.indexOf('\n}', start);
  return code.substring(start, end);
}

void main() {
  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
  });
  tearDown(CodegenConfigContext.reset);

  test('edges { node } gives a nodes getter skipping null edges and nodes', () {
    final code = _op(
        'query Users { users { edges { cursor node { id name } } } }', 'Users');
    final users = _class(code, 'Users_Users');
    expect(users, contains('List<Users_Users_Edges_Node> get nodes => ['));
    expect(users,
        contains('for (final edge in edges ?? const []) if (edge?.node case'));
    // Not a field: not in the constructor, toJson, == or copyWith.
    expect(users, isNot(contains('this.nodes')));
    expect(users, isNot(contains("'nodes'")));
    expect(code, isNot(contains('Object? nodes')));
  });

  test('non-null edges and nodes are not null-checked', () {
    final code =
        _op('query Search { search { edges { node { id } } } }', 'Search');
    final search = _class(code, 'Search_Search');
    expect(search, contains('List<Search_Search_Edges_Node> get nodes => ['));
    expect(search, contains('for (final edge in edges) edge.node,'));
  });

  test('an abstract node type gives a list of the sealed class', () {
    final code = _op(
        'query Search { search { edges { node { id ... on User { name } } } } }',
        'Search');
    expect(code, contains('sealed class Search_Search_Edges_Node {'));
    expect(_class(code, 'Search_Search'),
        contains('List<Search_Search_Edges_Node> get nodes'));
  });

  test('legacy nullability', () {
    CodegenConfigContext.strictNullability = false;
    final code =
        _op('query Search { search { edges { node { id } } } }', 'Search');
    expect(
        _class(code, 'Search_Search'),
        contains('for (final edge in edges ?? const []) '
            'if (edge?.node case final node?) node,'));
  });

  test('no getter when a selected field is named nodes', () {
    final code = _op(
        'query Users { users { edges { node { id } } nodes { id } } }',
        'Users');
    final users = _class(code, 'Users_Users');
    expect(users, isNot(contains('get nodes')));
    expect(users, contains('final List<Users_Users_Nodes?>? nodes;'));

    final aliased = _op(
        'query Users { users { edges { node { id } } nodes: pageInfo { '
            'hasNextPage } } }',
        'Users');
    expect(_class(aliased, 'Users_Users'), isNot(contains('get nodes')));
  });

  test('edges and node are matched by response key', () {
    for (final document in [
      'query Users { users { items: edges { node { id } } } }',
      'query Users { users { edges { item: node { id } } } }',
      'query Users { users { edges { cursor } } }',
    ]) {
      expect(_op(document, 'Users'), isNot(contains('get nodes')),
          reason: document);
    }
    // A scalar node is not a connection node.
    expect(_op('query Tags { tags { edges { node } } }', 'Tags'),
        isNot(contains('get nodes')));
  });

  test('fragment data classes get it, fragment interfaces do not', () {
    const fragment =
        'fragment UserList on UserConnection { edges { node { id } } }';
    final fragments = _fragments(fragment);
    expect(_class(fragments, 'UserList'), isNot(contains('get nodes')));
    final data = _class(fragments, 'UserListData');
    expect(data, contains('  List<UserListData_Edges_Node> get nodes => ['));
    expect(data, isNot(contains('@override\n  List<UserListData_Edges_Node>')));

    final code = _op(
        'query Users { users { ...UserList pageInfo { '
            'hasNextPage } } }',
        'Users',
        fragments: fragment);
    expect(_class(code, 'Users_Users'),
        contains('  List<Users_Users_Edges_Node> get nodes => ['));
  });

  test('a selected field named nodes keeps its name next to a fragment', () {
    // Interfaces don't declare `nodes`, so spreading a fragment with a
    // connection never renames a field of the operation.
    const fragment =
        'fragment UserList on UserConnection { edges { node { id } } }';
    final code = _op(
        'query Users { users { ...UserList nodes { id } } }', 'Users',
        fragments: fragment);
    final users = _class(code, 'Users_Users');
    expect(users, contains('final List<Users_Users_Nodes?>? nodes;'));
    expect(users, contains("'nodes': nodes"));
    expect(users, isNot(contains('get nodes =>')));
  });

  test('sealed classes declare it, their subclasses implement it', () {
    const schema = '''
interface Connection { edges: [Edge!]! }
type Edge { node: Item! }
type Item { id: ID! }
type ItemConnection implements Connection { edges: [Edge!]! total: Int! }
type OtherConnection implements Connection { edges: [Edge!]! }
type Query { list: Connection! }
''';
    final types = TypeGenerator.generateTypesFile(schema);
    final code = GraphQLCodeGenerator.generateOperationFile(
        schema,
        'query L { list { edges { node { id } } ... on ItemConnection { total } } }',
        'L',
        'query',
        types);
    expect(
        _class(code, 'L_List'), contains('List<L_List_Edges_Node> get nodes;'));
    expect(
        _class(code, 'L_List_OnItemConnection'),
        contains(
            '@override\n  List<L_List_OnItemConnection_Edges_Node> get nodes'));
    expect(_class(code, 'L_List_Other'),
        contains('@override\n  List<L_List_Other_Edges_Node> get nodes'));
  });
}
