// End-to-end checks of `nodes` getters on Relay-style connections and of
// `group_operations: directory`: the generated code must pass `dart analyze`
// and work against a GraphQLClient with a fake link.
//
// Slow (creates a package and runs build_runner); skip locally with
// `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:flutter_graphql_codegen/src/builder.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/compile_harness.dart';

const _connectionsSchema = r'''
interface Node { id: ID! }
type User implements Node { id: ID! name: String! }
type Post implements Node { id: ID! title: String! }
type PageInfo { hasNextPage: Boolean! }
type UserConnection { edges: [UserEdge] nodes: [User] pageInfo: PageInfo! }
type UserEdge { cursor: String! node: User }
type NodeConnection { edges: [NodeEdge!]! }
type NodeEdge { node: Node! }
type Query { users(first: Int): UserConnection! search: NodeConnection! }
''';

const _connectionsDocuments = [
  'fragment UserList on UserConnection { edges { node { id name } } }',
  r'''
query Users($first: Int) {
  users(first: $first) { edges { cursor node { id name } } pageInfo { hasNextPage } }
}
query UsersList { users { ...UserList } }
query Search {
  search { edges { node { id ... on User { name } ... on Post { title } } } }
}
query Both { users { edges { node { id } } nodes { id } } }
''',
];

/// Operation files and fragments.dart of [documents] in `lib/<dir>/`.
Map<String, String> _generate(String dir, String schema, List<String> documents,
    {required bool strict}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = strict;
  try {
    final types = TypeGenerator.generateTypesFile(schema);
    final files = <String, String>{'lib/$dir/types.dart': types};
    final fragments =
        DocumentUtils.collectFragments(documents.map(gql_lang.parseString));
    final code = GraphQLCodeGenerator.generateFragmentsFile(schema, fragments);
    if (code != null) files['lib/$dir/fragments.dart'] = code;
    for (final doc in documents) {
      for (final op in gql_lang
          .parseString(doc)
          .definitions
          .whereType<OperationDefinitionNode>()) {
        final name = op.name!.value;
        files['lib/$dir/$name.g.dart'] =
            GraphQLCodeGenerator.generateOperationFile(
                schema, doc, name, op.type.name, types,
                fragments: fragments);
      }
    }
    return files;
  } finally {
    CodegenConfigContext.reset();
  }
}

String _connectionsMain(String dir, {required bool legacy}) {
  // Legacy nullability makes every level nullable.
  final bang = legacy ? '!' : '';
  return '''
import 'package:fgc_compile_check/$dir/Both.g.dart';
import 'package:fgc_compile_check/$dir/Search.g.dart';
import 'package:fgc_compile_check/$dir/Users.g.dart';
import 'package:fgc_compile_check/$dir/UsersList.g.dart';
import 'package:fgc_compile_check/$dir/fragments.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: \$message');
}

/// Works for the connection of any operation spreading the fragment; the
/// interface has edges, not `nodes`.
List<String> names(UserList list) => [
      for (final e in list.edges ?? const <UserList_Edges?>[])
        if (e?.node case final u?) u.name$bang,
    ];

void main() {
  const ann = {'__typename': 'User', 'id': '1', 'name': 'Ann'};
  const bob = {'__typename': 'User', 'id': '2', 'name': 'Bob'};
  final edges = [
    {'__typename': 'UserEdge', 'cursor': 'a', 'node': ann},
    null,
    {'__typename': 'UserEdge', 'cursor': 'b', 'node': null},
    {'__typename': 'UserEdge', 'cursor': 'c', 'node': bob},
  ];
  final users = parseUsersData({
    'users': {
      '__typename': 'UserConnection',
      'edges': edges,
      'pageInfo': {'__typename': 'PageInfo', 'hasNextPage': false},
    },
  })$bang;
  final List<Users_Users_Edges_Node> nodes = users.nodes;
  check(nodes.map((n) => n.id).join(',') == '1,2',
      'null edges and nodes are left out');
  check(users.edges!.length == 4, 'edges are kept');
  check(!users.toJson().containsKey('nodes'), 'nodes is not serialized');
  check(Users_Users.fromJson(users.toJson()) == users, 'round trip');

  final empty = parseUsersData({
    'users': {
      '__typename': 'UserConnection',
      'edges': null,
      'pageInfo': {'__typename': 'PageInfo', 'hasNextPage': false},
    },
  })$bang;
  check(empty.nodes.isEmpty, 'no edges, no nodes');

  // Fragment interface and data class.
  final list = parseUsersListData({
    'users': {'__typename': 'UserConnection', 'edges': edges},
  })$bang;
  check(names(list).join(',') == 'Ann,Bob', 'edges through the fragment');
  check(list.nodes.map((u) => u.name).join(',') == 'Ann,Bob',
      'nodes of the operation class');
  final data = UserListData.fromJson(list.toJson());
  check(data.nodes.map((u) => u.name).join(',') == 'Ann,Bob',
      'nodes of the data class');

  // An interface as node type: a list of the sealed class.
  final search = parseSearchData({
    'search': {
      '__typename': 'NodeConnection',
      'edges': [
        {'__typename': 'NodeEdge', 'node': ann},
        {
          '__typename': 'NodeEdge',
          'node': {'__typename': 'Post', 'id': 'p', 'title': 'Hi'},
        },
        {
          '__typename': 'NodeEdge',
          'node': {'__typename': 'Robot', 'id': 'r'},
        },
      ],
    },
  })$bang;
  final labels = [
    for (final node in search.nodes)
      switch (node) {
        Search_Search_Edges_Node_OnUser(:final name) => 'user \$name',
        Search_Search_Edges_Node_OnPost(:final title) => 'post \$title',
        Search_Search_Edges_Node_Other(:final id) => 'other \$id',
      },
  ];
  check(labels.join(',') == 'user Ann,post Hi,other r', 'sealed nodes');

  // A selected `nodes` field wins.
  final both = parseBothData({
    'users': {
      '__typename': 'UserConnection',
      'edges': [],
      'nodes': [
        {'__typename': 'User', 'id': '3'},
      ],
    },
  })$bang;
  check(both.nodes!.single!.id == '3', 'selected nodes field');
  print('CONNECTIONS OK');
}
''';
}

const _groupsSchema = r'''
type Query { user(id: ID!): User  version: String  users: [User!]! }
type Mutation { rename(id: ID!, name: String!): User }
type Subscription { renamed: User }
type User { id: ID! name: String }
''';

const _groupsDocuments = {
  'lib/graphql/users/get_user.graphql': r'''
query GetUser($id: ID!) { user(id: $id) { id name } }
mutation Rename($id: ID!, $name: String!) { rename(id: $id, name: $name) { id name } }
''',
  'lib/graphql/users/admin/renamed.graphql':
      'subscription Renamed { renamed { id name } }',
  'lib/graphql/query/version.graphql': 'query GetVersion { version }',
  // `client.account()` is this operation's method, so the group of
  // account/ becomes `client.account_`.
  'lib/graphql/list/users.graphql': 'query Account { users { id } }',
  'lib/graphql/account/version.graphql': 'query AccountVersion { version }',
  'lib/graphql/root.graphql': 'query RootVersion { version }',
};

/// Runs the builder with `group_operations: directory` on [_groupsDocuments]
/// and returns the generated files under `lib/<dir>/`.
Future<Map<String, String>> _buildGroups(String dir,
    {required String resultTypes}) async {
  final out = await Directory.systemTemp.createTemp('fgc_groups_compile_');
  final errors = <String>[];
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = true;
  CodegenConfigContext.resultTypes = resultTypes;
  CodegenConfigContext.groupOperations = 'directory';
  try {
    await testBuilder(
      GraphQLCodegenBuilder(GraphQLCodegenConfig(
        schemaUrl: 'lib/schema.graphql',
        outputDir: out.path,
        documentPaths: ['lib/graphql/**.graphql'],
        strictNullability: true,
        resultTypes: resultTypes,
        groupOperations: 'directory',
      )),
      {
        'a|lib/schema.graphql': _groupsSchema,
        for (final MapEntry(:key, :value) in _groupsDocuments.entries)
          'a|$key': value,
      },
      rootPackage: 'a',
      onLog: (r) {
        if (r.level.name == 'SEVERE') errors.add(r.message);
      },
    );
    expect(errors, isEmpty);
    return {
      for (final file in out.listSync().whereType<File>())
        'lib/$dir/${p.basename(file.path)}': file.readAsStringSync(),
    };
  } finally {
    CodegenConfigContext.reset();
    await out.delete(recursive: true);
  }
}

String _groupsMain(String dir, {required bool schemaTypes}) => '''
// The group files export their operation files.
import 'package:fgc_compile_check/$dir/account_operations.dart';
import 'package:fgc_compile_check/$dir/list_operations.dart';
import 'package:fgc_compile_check/$dir/query_operations.dart';
import 'package:fgc_compile_check/$dir/users_admin_operations.dart';
import 'package:fgc_compile_check/$dir/users_operations.dart';
// Root documents are only reachable through index.dart (or their files).
import 'package:fgc_compile_check/$dir/index.dart' show RootVersionExtension;
import 'package:graphql/client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: \$message');
}

const ann = {'__typename': 'User', 'id': '1', 'name': 'Ann'};

class FakeLink extends Link {
  final requests = <String>[];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final name = request.operation.operationName!;
    requests.add(name);
    final data = switch (name) {
      'GetUser' => {'user': ann},
      'Rename' => {
          'rename': {...ann, 'name': request.variables['name']},
        },
      'Renamed' => {
          'renamed': {...ann, 'name': 'Zed'},
        },
      'GetVersion' || 'RootVersion' || 'AccountVersion' => {'version': '1.0'},
      'Account' => {
          'users': [ann],
        },
      _ => throw StateError(name),
    };
    final root = switch (name) {
      'Rename' => 'Mutation',
      'Renamed' => 'Subscription',
      _ => 'Query',
    };
    yield Response(data: {'__typename': root, ...data}, response: const {});
  }
}

Future<void> main() async {
  final link = FakeLink();
  final client = GraphQLClient(
    link: link,
    cache: GraphQLCache(),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.networkOnly),
    ),
  );

  final UsersOperations users = client.users;
  check(identical(users.client, client), 'wraps the client');
  final user = await client.users.getUserData(
      const GetUserVariables(id: '1').toJson());
  check(user?.name == 'Ann', 'grouped query');
  final raw = await client.users.getUser({'id': '1'});
  check(raw.data?['user']?['name'] == 'Ann', 'grouped raw query');

  // Cache helpers delegate too.
  const vars = GetUserVariables(id: '1');
  check(client.users.readGetUser(vars)?.name == 'Ann', 'grouped read');
  ${schemaTypes ? "client.users.writeGetUser(vars, {'__typename': 'Query', 'user': {...ann, 'name': 'Ann 2'}});" : "client.users.writeGetUser(vars, user!.copyWith(name: 'Ann 2'));"}
  check(client.readGetUser(vars)?.name == 'Ann 2', 'grouped write');
  check(client.users.evictGetUser(vars), 'grouped evict');
  check(client.readGetUser(vars) == null, 'evicted');

  final renamed = await client.users.renameData(
      const RenameVariables(id: '1', name: 'Bea').toJson());
  check(renamed?.name == 'Bea', 'grouped mutation');

  final event = await client.usersAdmin.renamedData().first;
  check(event?.name == 'Zed', 'nested directory, subscription');

  // `query` is a GraphQLClient member, `account` an operation's method.
  check(await client.query_.getVersionData() == '1.0', 'escaped getter');
  check(await client.account_.accountVersionData() == '1.0',
      'getter named like an operation method');
  check((await client.list.accountData()).single.id == '1', 'list group');
  check((await client.account()).data != null, 'flat method kept');

  // Flat methods stay available.
  check(await client.getVersionData() == '1.0', 'flat method');
  check(await client.rootVersionData() == '1.0', 'root operation');
  check(link.requests.contains('Renamed'), 'subscription sent');
  print('GROUPS OK');
}
''';

void main() {
  test('connections and operation groups compile and work', () async {
    final files = {
      ..._generate('conn', _connectionsSchema, _connectionsDocuments,
          strict: true),
      ..._generate('conn_legacy', _connectionsSchema, _connectionsDocuments,
          strict: false),
      'bin/conn.dart': _connectionsMain('conn', legacy: false),
      'bin/conn_legacy.dart': _connectionsMain('conn_legacy', legacy: true),
      ...await _buildGroups('groups', resultTypes: 'operation'),
      ...await _buildGroups('groups_schema', resultTypes: 'schema'),
      'bin/groups.dart': _groupsMain('groups', schemaTypes: false),
      'bin/groups_schema.dart': _groupsMain('groups_schema', schemaTypes: true),
    };
    expect(files['lib/groups/users_operations.dart'], isNotNull);

    final result = await compileGenerated(files, runScripts: [
      'bin/conn.dart',
      'bin/conn_legacy.dart',
      'bin/groups.dart',
      'bin/groups_schema.dart',
    ]);
    expect(result.errors, isEmpty, reason: result.log);
  });
}
