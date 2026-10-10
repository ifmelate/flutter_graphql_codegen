// Verifies generated code end to end: it must survive json_serializable,
// pass `dart analyze` without errors and behave correctly at runtime.
//
// Slow (creates a package and runs build_runner); skip locally with
// `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/compile_harness.dart';

/// Generates types.dart + one file per operation into `lib/<dir>/`.
Map<String, String> _generate(
  String dir,
  String schema,
  List<String> documents, {
  required bool strict,
}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = strict;
  try {
    final types = TypeGenerator.generateTypesFile(schema);
    final files = <String, String>{'lib/$dir/types.dart': types};
    final fragments =
        DocumentUtils.collectFragments(documents.map(gql_lang.parseString));
    for (final doc in documents) {
      final ops = gql_lang
          .parseString(doc)
          .definitions
          .whereType<OperationDefinitionNode>();
      for (final op in ops) {
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

const _smokeSchema = r'''
scalar JSON
scalar DateTime

interface Node { id: ID! }

type User implements Node {
  id: ID!
  name: String!
  role: Role!
  meta: JSON
  class: String
}

type Post implements Node { id: ID! title: String! }

union SearchResult = User | Post

enum Role { ADMIN default }

input UserFilter { role: Role, since: DateTime, tags: [String!] }

type Query {
  node(id: ID!): Node
  search(q: String!): [SearchResult!]!
  me: User!
  users(filter: UserFilter, first: Int = 10): [User!]!
}

type Mutation { rename(id: ID!, name: String!): User }

type Subscription { userChanged: User! }

extend type Query { version: String! }
''';

const _smokeDocuments = [
  r'''
query Search($q: String!) {
  search(q: $q) {
    ... on User { id name role meta class }
    ... on Post { id title }
  }
}
''',
  r'''
query Combined($id: ID!) {
  me { ...UserBits }
  node(id: $id) { id ...UserBits }
  version
}
''',
  r'''
fragment UserBits on User { id name role }
''',
  r'''
query Users($filter: UserFilter, $first: Int) { users(filter: $filter, first: $first) { ...UserBits } }
mutation Rename($id: ID!, $name: String!) { renamed: rename(id: $id, name: $name) { ...UserBits } }
subscription UserChanged { userChanged { ...UserBits } }
''',
];

const _smokeMain = r'''
import 'dart:async';

import 'package:fgc_compile_check/smoke/Combined.g.dart';
import 'package:fgc_compile_check/smoke/Rename.g.dart';
import 'package:fgc_compile_check/smoke/Search.g.dart';
import 'package:fgc_compile_check/smoke/UserChanged.g.dart';
import 'package:fgc_compile_check/smoke/Users.g.dart';
import 'package:fgc_compile_check/smoke/types.dart';
import 'package:graphql/client.dart';

final requests = <Request>[];

class FakeLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests.add(request);
    final data = responses[request.operation.operationName];
    if (data == null) {
      yield Response(
        errors: const [GraphQLError(message: 'boom')],
        response: const {},
      );
      return;
    }
    yield Response(data: data, response: const {});
  }
}

const user = {
  '__typename': 'User', 'id': '1', 'name': 'Ann', 'role': 'default',
};

final responses = <String, Map<String, dynamic>>{
  'Search': {
    'search': [
      {...user, 'meta': {'a': 1}, 'class': 'x'},
      {'__typename': 'Post', 'id': '2', 'title': 'Hello'},
      {'__typename': 'Ad', 'id': '3'},
    ],
  },
  'Combined': {
    'me': user,
    'node': user,
    'version': '1.0',
  },
  'Rename': {'renamed': {...user, 'name': 'Bob'}},
  'UserChanged': {'userChanged': user},
  'Users': {'users': [user]},
};

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

Future<void> main() async {
  final client = GraphQLClient(
    link: FakeLink(),
    cache: GraphQLCache(),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
      mutate: Policies(fetch: FetchPolicy.noCache),
      subscribe: Policies(fetch: FetchPolicy.noCache),
    ),
  );

  // Unions dispatch on __typename, unknown members fall back.
  final results = await client.searchData(
      const SearchVariables(q: 'a').toJson());
  check(results.length == 3, 'three search results');
  final first = results[0] as User;
  check(first.role == Role.default_, 'escaped enum value');
  check(first.class_ == 'x', 'escaped field name');
  check(first.meta!.raw is Map, 'JSON scalar keeps raw map');
  check((results[1] as Post).title == 'Hello', 'post member');
  check((results[2] as UnknownSearchResult).typename == 'Ad', 'fallback');
  check(requests.last.operation.operationName == 'Search', 'operationName');

  // Multiple root fields, interface dispatch, extended schema field.
  final combined = await client.combinedData({'id': '1'});
  check(combined.me.name == 'Ann', 'first root field');
  check(combined.node is User, 'interface dispatch');
  check(combined.version == '1.0', 'field from extend type');

  // Typed variables serialize enums/dates and omit unset optionals.
  final vars = UsersVariables(
    filter: UserFilter(role: Role.default_, since: DateTime.utc(2024)),
  ).toJson();
  check(!vars.containsKey('first'), 'unset optional omitted');
  final filter = vars['filter'] as Map<String, dynamic>;
  check(filter['role'] == 'default', 'enum serialized with schema name');
  check(filter['since'] == '2024-01-01T00:00:00.000Z', 'DateTime serialized');
  check((await client.usersData(vars)).single.id == '1', 'users query');

  // Aliased root field.
  final renamed = await client.renameData(
      const RenameVariables(id: '1', name: 'Bob').toJson());
  check(renamed!.name == 'Bob', 'alias used as response key');

  // Subscriptions are streams.
  final changed = await client.userChangedData().first;
  check(changed.id == '1', 'subscription data');

  // Errors propagate as OperationException instead of being swallowed.
  responses.remove('Combined');
  try {
    await client.combinedData({'id': '1'});
    throw StateError('Check failed: expected OperationException');
  } on OperationException catch (e) {
    check(e.graphqlErrors.single.message == 'boom', 'graphql error kept');
  }

  print('SMOKE OK');
}
''';

void main() {
  test('generated code compiles and works', () async {
    final fixtureDir = p.join('test', 'fixtures');
    final schema =
        File(p.join(fixtureDir, 'schema.graphql')).readAsStringSync();
    final documents = Directory(fixtureDir)
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.graphql') && !f.path.endsWith('schema.graphql'))
        .map((f) => f.readAsStringSync())
        .toList()
      ..sort();

    final files = {
      ..._generate('legacy', schema, documents, strict: false),
      ..._generate('strict', schema, documents, strict: true),
      ..._generate('smoke', _smokeSchema, _smokeDocuments, strict: true),
      'bin/smoke.dart': _smokeMain,
    };

    final result =
        await compileGenerated(files, runScripts: ['bin/smoke.dart']);
    expect(result.errors, isEmpty, reason: result.log);
  });
}
