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

/// Generates types.dart, fragments.dart (operation result types with
/// fragments) and one file per operation into `lib/<dir>/`.
Map<String, String> _generate(
  String dir,
  String schema,
  List<String> documents, {
  required bool strict,
  String resultTypes = 'operation',
  bool unknownEnumFallback = false,
  bool deprecatedAnnotations = false,
  bool includeNullInputs = false,
  Map<String, String> scalarMapping = const {},
  Map<String, String> scalarImports = const {},
  Map<String, String> scalarConverters = const {},
}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.resultTypes = resultTypes;
  CodegenConfigContext.strictNullability = strict;
  CodegenConfigContext.unknownEnumFallback = unknownEnumFallback;
  CodegenConfigContext.deprecatedAnnotations = deprecatedAnnotations;
  CodegenConfigContext.includeNullInputs = includeNullInputs;
  CodegenConfigContext.scalarMapping = Map.of(scalarMapping);
  CodegenConfigContext.scalarImports = Map.of(scalarImports);
  CodegenConfigContext.scalarConverters = Map.of(scalarConverters);
  try {
    final types = TypeGenerator.generateTypesFile(schema);
    final files = <String, String>{'lib/$dir/types.dart': types};
    final fragments =
        DocumentUtils.collectFragments(documents.map(gql_lang.parseString));
    if (resultTypes == 'operation') {
      final code =
          GraphQLCodeGenerator.generateFragmentsFile(schema, fragments);
      if (code != null) files['lib/$dir/fragments.dart'] = code;
    }
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

"""
A person.
"""
type User implements Node {
  "Stable id."
  id: ID!
  name: String!
  nick: String @deprecated(reason: "Use 'name'")
  role: Role!
  roles: [Role!]!
  meta: JSON
  class: String
}

type Post implements Node { id: ID! title: String! }

union SearchResult = User | Post

enum Role { ADMIN "Old." default @deprecated }

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
    ... on User { id name nick role roles meta class }
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
      {...user, 'nick': 'A', 'roles': ['ADMIN', 'default'], 'meta': {'a': 1}, 'class': 'x'},
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
    cache: GraphQLCache(possibleTypes: possibleTypes),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.noCache),
      mutate: Policies(fetch: FetchPolicy.noCache),
      subscribe: Policies(fetch: FetchPolicy.noCache),
    ),
  );

  check(possibleTypes['SearchResult']!.containsAll(['Post', 'User']),
      'possibleTypes lists union members');

  // Unions dispatch on __typename, unknown members fall back.
  final results = await client.searchData(
      const SearchVariables(q: 'a').toJson());
  check(results.length == 3, 'three search results');
  final first = results[0] as User;
  check(first.role == Role.default_, 'escaped enum value');
  check(first.class_ == 'x', 'escaped field name');
  check(first.nick == 'A', 'deprecated field still parsed');
  check(first.roles.length == 2 && first.roles[1] == Role.default_,
      'escaped enum value in a list');
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

  // Typed options: parsedData is typed for query, mutate and subscribe.
  final typed =
      await client.query(searchQueryOptions(const SearchVariables(q: 'a')));
  check(typed.parsedData!.length == 3, 'typed QueryOptions');
  final ObservableQuery<CombinedResult> watched = client.watchQuery(
      combinedWatchQueryOptions(const CombinedVariables(id: '1')));
  watched.close();
  final renamedTyped = await client.mutate(
      renameMutationOptions(const RenameVariables(id: '1', name: 'Bob')));
  check(renamedTyped.parsedData!.name == 'Bob', 'typed MutationOptions');
  final changedTyped =
      await client.subscribe(userChangedSubscriptionOptions()).first;
  check(changedTyped.parsedData!.id == '1', 'typed SubscriptionOptions');

  // Cache helpers: write raw data, read it back typed.
  const cacheVars = UsersVariables(first: 1);
  check(client.readUsers(variables: cacheVars) == null, 'cache miss is null');
  client.writeUsers({
    '__typename': 'Query',
    'users': [user],
  }, variables: cacheVars);
  check(client.readUsers(variables: cacheVars)!.single.name == 'Ann',
      'cache round trip');

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

const _fallbackMain = r'''
import 'package:fgc_compile_check/fallback/types.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  final user = User.fromJson({
    'id': '1',
    'name': 'Ann',
    'role': 'OWNER',
    'roles': ['ADMIN', 'OWNER', 'default'],
  });
  check(user.role == Role.$unknown, 'unknown enum value');
  check(user.roles[0] == Role.ADMIN, 'known value in list');
  check(user.roles[1] == Role.$unknown, 'unknown value in list');
  // ignore: deprecated_member_use_from_same_package
  check(user.roles[2] == Role.default_, 'escaped value in list');
  check(user.roleRaw == 'OWNER', 'raw value next to \$unknown');
  check(user.rolesRaw![1] == 'OWNER' && user.rolesRaw![2] == 'default',
      'raw values of a list');
  final known = User.fromJson(
      {'id': '2', 'name': 'Bob', 'role': 'ADMIN', 'roles': ['ADMIN']}).toJson();
  check(known['role'] == 'ADMIN' && known.keys.every((k) => !k.contains('#')),
      'raw values are not sent back');
  check(UserFilter(role: Role.ADMIN).toJson()['role'] == 'ADMIN',
      'known value serialized');
  try {
    UserFilter(role: Role.$unknown).toJson();
    throw StateError(r'Check failed: $unknown must not be serialized');
  } on ArgumentError {
    // expected
  }
  print('FALLBACK OK');
}
''';

// Schema types named like identifiers the generated code relies on.
const _collideSchema = r'''
scalar Object
scalar DateTime
type Map { key: String! tags: [Object!]! at: [DateTime!]! }
type Decimal { amount: String! }
type User { id: ID! }
union Set = Map | User
enum Future { NOW LATER }
enum Enum { A B }
input Stream { from: Future }
type Query {
  maps(filter: Stream): [Map!]!
  obj: Object
  set: [Set!]!
  when: Future!
  decimal: Decimal
  kind: Enum
}
type Subscription { ticks: Map! }
''';

const _collideDocuments = [
  r'''
query Everything($s: Stream) {
  maps(filter: $s) { key tags at }
  obj
  set { ... on Map { key } ... on User { id } }
  when
  decimal { amount }
  kind
}
subscription Ticks { ticks { key } }
''',
];

const _collideMain = r'''
import 'package:fgc_compile_check/collide/Everything.g.dart';
import 'package:fgc_compile_check/collide/types.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  final data = parseEverythingData({
    'maps': [
      {
        '__typename': 'Map',
        'key': 'k',
        'tags': ['a', 1],
        'at': ['2024-01-01T00:00:00Z'],
      },
    ],
    'obj': {'any': 'thing'},
    'set': [
      {'__typename': 'Map', 'key': 'm'},
      {'__typename': 'User', 'id': '1'},
    ],
    'when': 'LATER',
    'decimal': {'__typename': 'Decimal', 'amount': '1.5'},
    'kind': 'B',
  });
  check(data.maps.single.key == 'k', 'Map_ parsed');
  check(data.maps.single.tags[1].raw == 1, 'Object_ list parsed');
  check(data.maps.single.at.single.year == 2024, 'DateTime list parsed');
  check(data.obj!.raw is Map, 'Object_ scalar keeps the raw JSON');
  check(data.set[0] is Map_ && data.set[1] is User, 'Set_ dispatch');
  check(data.when == Future_.LATER, 'Future_ enum parsed');
  check(data.decimal!.amount == '1.5', 'Decimal_ object parsed');
  check(Decimal('2.50').value == '2.50', 'built-in Decimal still there');
  check(data.kind == Enum_.B, 'Enum_ enum parsed');
  check(EverythingVariables(s: Stream_(from: Future_.NOW))
          .toJson()['s']['from'] == 'NOW',
      'Stream_ input serialized');
  check(possibleTypes['Set']!.contains('Map'), 'GraphQL names in possibleTypes');
  print('COLLIDE OK');
}
''';

// Names Dart can't use as they are (`_id`, a field named like a type) and
// lists of converted scalars with nullable elements, nested lists included.
const _edgeSchema = r'''
scalar Custom
scalar DateTime
scalar LocalDate
scalar Decimal
type Media { id: ID! title: String }
type Thing {
  _id: ID!
  int: Int
  String: String
  Media: Media
  customs: [Custom]
  customGrid: [[Custom]]
  dates: [DateTime]
  dateGrid: [[DateTime!]]
  days: [LocalDate]
  amounts: [Decimal]
  seen: DateTime
  day: LocalDate
  custom: Custom
  amount: Decimal
}
input ThingInput {
  _id: ID!
  int: Int
  String: String
  customs: [Custom]
  dates: [DateTime]
}
enum Kind { visible _hidden }
type Query {
  Media(_id: ID): Media
  thing(input: ThingInput): Thing
  kinds: [Kind!]!
  grid: [[Custom]]
  lastSeen: DateTime
  lastCustom: Custom
}
''';

const _edgeDocuments = [
  r'''
query EdgeCases($_id: ID, $input: ThingInput) {
  Media(_id: $_id) { id title }
  thing(input: $input) {
    _id int String Media { id } customs customGrid dates dateGrid days amounts
    seen day custom amount
  }
  kinds
  grid
  lastSeen
  lastCustom
}
''',
];

const _edgeMain = r'''
import 'package:fgc_compile_check/edge/EdgeCases.g.dart';
import 'package:fgc_compile_check/edge/types.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  final data = parseEdgeCasesData({
    'Media': {'__typename': 'Media', 'id': 'm1', 'title': 'T'},
    'thing': {
      '__typename': 'Thing',
      '_id': 't1',
      'int': 3,
      'String': 's',
      'Media': {'__typename': 'Media', 'id': 'm2'},
      'customs': ['a', null, {'k': 1}],
      'customGrid': [['a', null], null],
      'dates': ['2024-01-02T03:04:05Z', null],
      'dateGrid': [['2024-01-02T03:04:05Z']],
      'days': ['2024-01-02', null],
      'amounts': ['1.5', null],
      'seen': null,
      'day': null,
      'custom': null,
      'amount': null,
    },
    'kinds': ['visible', '_hidden'],
    'grid': [['g'], null],
    'lastSeen': null,
    'lastCustom': null,
  });
  check(data.Media_!.id == 'm1', 'field named like its type');
  final thing = data.thing!;
  check(thing.id_ == 't1', '_id field');
  check(thing.int_ == 3 && thing.String_ == 's', 'fields named int/String');
  check(thing.Media_!.id == 'm2', 'nested field named like its type');
  check(thing.customs![0]!.value == 'a' && thing.customs![1] == null,
      'list of nullable custom scalars');
  check(thing.customs![2]!.raw is Map, 'custom scalar keeps raw JSON');
  check(thing.customGrid![0]![0]!.value == 'a' &&
          thing.customGrid![0]![1] == null &&
          thing.customGrid![1] == null,
      'nested list of custom scalars');
  check(thing.dates![0]!.year == 2024 && thing.dates![1] == null,
      'list of nullable DateTime');
  check(thing.dateGrid![0]![0].year == 2024, 'nested DateTime list');
  check(thing.days![0]!.day == 2 && thing.days![1] == null, 'LocalDate list');
  check(thing.amounts![0]!.value == '1.5' && thing.amounts![1] == null,
      'Decimal list');
  check(data.kinds[1] == Kind.hidden_, 'enum value with underscore');
  check(data.grid![0]![0]!.value == 'g' && data.grid![1] == null,
      'root nested list of custom scalars');
  check(thing.seen == null, 'null DateTime stays null');
  check(thing.day == null, 'null LocalDate stays null');
  check(thing.custom == null, 'null custom scalar stays null');
  check(thing.amount == null, 'null Decimal stays null');
  check(data.lastSeen == null, 'null root DateTime stays null');
  check(data.lastCustom == null, 'null root custom scalar stays null');

  final vars = EdgeCasesVariables(
    id_: 'x',
    input: ThingInput(
      id_: 't',
      int_: 1,
      String_: 'y',
      customs: [const Custom('c'), null],
      dates: [DateTime.utc(2024, 5, 1), null],
    ),
  ).toJson();
  check(vars['_id'] == 'x', '_id variable keeps its GraphQL name');
  final input = vars['input'] as Map<String, dynamic>;
  check(input['_id'] == 't' && input['int'] == 1 && input['String'] == 'y',
      'escaped input fields keep their GraphQL names');
  check(input['customs'][0] == 'c' && input['customs'][1] == null,
      'custom scalar list serialized');
  check(input['dates'][0] == '2024-05-01T00:00:00.000Z' &&
          input['dates'][1] == null,
      'DateTime list serialized');
  print('EDGE OK');
}
''';

// Operations named like GraphQLClient members: the extension methods would be
// shadowed by the client's own (query, readQuery, link, ...).
const _clientNamesSchema = r'''
type Query { a: Int, item(id: ID!): Int }
type Mutation { b: Int }
type Subscription { c: Int }
''';

const _clientNamesDocuments = [
  r'''
query Query { a }
query Fragment { a }
query Link { a }
query Item($id: ID!) { item(id: $id) }
mutation Mutate { b }
subscription Subscribe { c }
query Introspection {
  __schema { queryType { name } }
  __type(name: "Query") { name }
}
''',
];

const _clientNamesMain = r'''
import 'package:fgc_compile_check/client_names/Fragment.g.dart';
import 'package:fgc_compile_check/client_names/Introspection.g.dart';
import 'package:fgc_compile_check/client_names/Item.g.dart';
import 'package:fgc_compile_check/client_names/Link.g.dart';
import 'package:fgc_compile_check/client_names/Mutate.g.dart';
import 'package:fgc_compile_check/client_names/Query.g.dart';
import 'package:fgc_compile_check/client_names/Subscribe.g.dart';
import 'package:graphql/client.dart';

class FakeLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final data = switch (request.operation.operationName) {
      'Mutate' => {'b': 2},
      'Subscribe' => {'c': 3},
      _ => {'a': 1},
    };
    yield Response(data: data, response: const {});
  }
}

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

  check((await client.query_()).data!['a'] == 1, 'query_ runs the operation');
  check(await client.queryData() == 1, 'queryData');
  client.writeQuery_({'__typename': 'Query', 'a': 5});
  check(client.readQuery_() == 5, 'readQuery_/writeQuery_ use the cache');
  check(client.evictQuery() && client.readQuery_() == null, 'evictQuery');

  // evict removes the entry for the given variables only.
  client.writeItem(const ItemVariables(id: '1'), {'__typename': 'Query', 'item': 10});
  client.writeItem(const ItemVariables(id: '2'), {'__typename': 'Query', 'item': 20});
  check(client.evictItem(const ItemVariables(id: '1')), 'evictItem');
  check(client.readItem(const ItemVariables(id: '1')) == null &&
          client.readItem(const ItemVariables(id: '2')) == 20,
      'other variables stay cached');
  check(!client.evictItem(const ItemVariables(id: '1')), 'nothing to evict');
  client.writeFragment_({'__typename': 'Query', 'a': 6});
  check(client.readFragment_() == 6, 'readFragment_/writeFragment_');
  check(await client.linkData() == 1 && client.link is FakeLink,
      'link_ keeps the client link');
  check((await client.link_()).data!['a'] == 1, 'link_');
  check(await client.mutateData() == 2, 'mutate_');
  check(await client.subscribeData().first == 3, 'subscribe_');

  // __schema and __type aren't in the SDL; they stay raw JSON.
  final meta = parseIntrospectionData({
    '__schema': {
      'queryType': {'name': 'Query'}
    },
    '__type': {'name': 'Query'},
  });
  check(meta.schema__!['queryType']['name'] == 'Query', '__schema');
  check(meta.type__!['name'] == 'Query', '__type');
  print('CLIENT NAMES OK');
}
''';

// include_null_inputs: null input fields and variables are sent as null,
// except variables with a default value, which are sent with the default.
const _nullsSchema = r'''
input Patch { name: String, note: String }
type Query { ok: Boolean }
type Mutation {
  update(id: ID!, patch: Patch!, limit: Int = 5, tag: String): Boolean
}
''';

const _nullsDocuments = [
  r'''
mutation Update($id: ID!, $patch: Patch!, $limit: Int = 5, $tag: String) {
  update(id: $id, patch: $patch, limit: $limit, tag: $tag)
}
''',
];

String _nullsMain(String dir, {required bool sendsNulls}) => '''
import 'package:fgc_compile_check/$dir/Update.g.dart';
import 'package:fgc_compile_check/$dir/types.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: \$message');
}

void main() {
  final vars = UpdateVariables(id: '1', patch: Patch(name: 'x')).toJson();
  final patch = vars['patch'] as Map<String, dynamic>;
  check(patch['name'] == 'x', 'set field sent');
  check(patch.containsKey('note') == $sendsNulls, 'null input field');
  check(vars.containsKey('tag') == $sendsNulls, 'null variable');
  check(vars['limit'] == 5, 'variable with a default is sent with it');
  check(UpdateVariables(id: '1', patch: Patch(), limit: 3).toJson()['limit'] == 3,
      'variable with a default is sent when set');
  print('NULLS OK');
}
''';

// scalar_mapping with imports: a converter (Money), a type with
// fromJson/toJson (Cents) and the short form (Date: DateTime).
const _mappedLibrary = r'''
import 'package:json_annotation/json_annotation.dart';

class Money {
  const Money(this.cents);
  final int cents;
}

// A non-nullable JSON type lets json_serializable handle nulls.
class MoneyConverter implements JsonConverter<Money, int> {
  const MoneyConverter();

  @override
  Money fromJson(int json) => Money(json);

  @override
  int toJson(Money object) => object.cents;
}

class Cents {
  const Cents(this.value);
  factory Cents.fromJson(Object? json) => Cents(json as int);
  final int value;
  Object? toJson() => value;
}
''';

const _mappedSchema = r'''
scalar Money
scalar Cents
scalar Date
type Item {
  price: Money!
  prices: [Money!]!
  maybe: [Money]
  cents: Cents!
  day: Date!
}
input ItemInput { price: Money! cents: Cents day: Date }
type Query { item(day: Date!, price: Money, input: ItemInput): Item! total: Money! }
''';

const _mappedDocuments = [
  r'''
query GetItem($day: Date!, $price: Money, $input: ItemInput) {
  item(day: $day, price: $price, input: $input) { price prices maybe cents day }
  total
}
''',
];

const _mappedMain = r'''
import 'package:fgc_compile_check/mapped/GetItem.g.dart';
import 'package:fgc_compile_check/mapped/types.dart';
import 'package:fgc_compile_check/scalars/money.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  final data = parseGetItemData({
    'item': {
      '__typename': 'Item',
      'price': 150,
      'prices': [1, 2],
      'maybe': [3, null],
      'cents': 7,
      'day': '2024-05-01T00:00:00.000Z',
    },
    'total': 999,
  });
  check(data.item.price.cents == 150, 'converter on a field');
  check(data.item.prices[1].cents == 2, 'converter on list elements');
  check(data.item.maybe![0]!.cents == 3 && data.item.maybe![1] == null,
      'converter on nullable list elements');
  check(data.item.cents.value == 7, 'type with fromJson');
  check(data.item.day.year == 2024, 'short form mapping');
  check(data.total.cents == 999, 'root field through the converter');
  check(data.item.toJson()['price'] == 150, 'converter toJson');

  final vars = GetItemVariables(
    day: DateTime.utc(2024, 5, 1),
    price: const Money(5),
    input: ItemInput(price: const Money(6), cents: const Cents(7)),
  ).toJson();
  check(vars['day'] == '2024-05-01T00:00:00.000Z', 'mapped DateTime variable');
  check(vars['price'] == 5, 'converter variable');
  final input = vars['input'] as Map<String, dynamic>;
  check(input['price'] == 6 && input['cents'] == 7, 'input with mapped scalars');
  print('MAPPED OK');
}
''';

// Input classes of `result_types: operation`, hand-written in types.dart.
const _opTypesSchema = r'''
scalar JSON
scalar DateTime
scalar LocalDate
scalar Decimal
scalar Long
scalar Money

enum Status { ACTIVE default _hidden }

"""
Product filter.
"""
input ProductFilter {
  _id: ID
  name: String!
  int: Int
  class: String
  status: Status
  statuses: [Status!]
  tags: [String!]!
  grid: [[Int]]
  since: DateTime
  days: [LocalDate]
  price: Decimal
  total: Long
  meta: JSON
  metas: [JSON]
  page: Page
  pages: [Page!]
  other: Int
  value: String
  json: String
  e: Int
  old: String @deprecated(reason: "Use name")
  money: Money
  monies: [Money]
}

input Page { first: Int! after: String }

type Product { id: ID! }
union Thing = Product
type Query { products(filter: ProductFilter): [Product!]! thing: Thing }
''';

String _opTypesMain(String dir,
        {bool nulls = false, bool fallback = false, bool mapped = false}) =>
    '''
import 'package:fgc_compile_check/$dir/types.dart';
${mapped ? "import 'package:fgc_compile_check/scalars/money.dart';" : ''}

const nulls = $nulls;
const fallback = $fallback;
const mapped = $mapped;
'''
    r'''

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  const page = Page(first: 10);
  final filter = ProductFilter(
    id_: 'p1',
    name: 'Lamp',
    int_: 3,
    class_: 'x',
    status: Status.default_,
    statuses: [Status.ACTIVE, Status.hidden_],
    tags: ['a'],
    grid: [
      [1, null],
      null
    ],
    since: DateTime.utc(2024, 5, 1),
    days: [DateTime(2024, 5, 2), null],
    price: Decimal('1.50'),
    total: Long('12'),
    meta: const JSON({'k': 1}),
    metas: [const JSON('m'), null],
    page: page,
    pages: [page, const Page(first: 1, after: 'c')],
    other: 1,
    value: 'v',
    json: 'j',
    e: 2,
    money: const Money(5),
    monies: [const Money(6), null],
  );

  final json = filter.toJson();
  check(json['_id'] == 'p1' && json['int'] == 3 && json['class'] == 'x',
      'escaped fields keep their GraphQL names');
  check(json['name'] == 'Lamp', 'string field');
  check(json['status'] == 'default', 'escaped enum value');
  check(graphqlDeepEquals(json['statuses'], ['ACTIVE', '_hidden']),
      'enum list');
  check(graphqlDeepEquals(json['tags'], ['a']), 'string list');
  check(
      graphqlDeepEquals(json['grid'], [
        [1, null],
        null
      ]),
      'nested list with nulls');
  check(json['since'] == '2024-05-01T00:00:00.000Z', 'DateTime');
  check(graphqlDeepEquals(json['days'], ['2024-05-02', null]), 'LocalDate list');
  check(json['price'] == '1.50' && json['total'] == '12', 'Decimal and Long');
  check(graphqlDeepEquals(json['meta'], {'k': 1}), 'custom scalar keeps raw JSON');
  check(graphqlDeepEquals(json['metas'], ['m', null]), 'custom scalar list');
  check(
      graphqlDeepEquals(
          json['page'], nulls ? {'first': 10, 'after': null} : {'first': 10}),
      'nested input');
  check(graphqlDeepEquals((json['pages'] as List)[1], {'first': 1, 'after': 'c'}),
      'list of inputs');
  check(json['other'] == 1 && json['value'] == 'v' && json['json'] == 'j' &&
          json['e'] == 2,
      'fields named like generated locals');
  check(json['money'] == 5 && graphqlDeepEquals(json['monies'], [6, null]),
      mapped ? 'scalar_mapping converter' : 'custom scalar wrapper');
  check(json.containsKey('old') == nulls, 'unset field');
  check(json.keys.length == (nulls ? 23 : 22), 'all fields written');

  // Unset optional fields: left out unless include_null_inputs. A non-null
  // list defaults to empty, a nullable one to null (`[]` would mean "none").
  final empty = const ProductFilter(name: 'n').toJson();
  check(empty.containsKey('int') == nulls && empty.containsKey('page') == nulls,
      'null fields');
  check(graphqlDeepEquals(empty['tags'], []), 'non-null list defaults to empty');
  check(empty.containsKey('pages') == nulls && empty['pages'] == null,
      'nullable list defaults to null');
  if (nulls) check(empty['int'] == null, 'null written as null');

  // fromJson round trip.
  final back = ProductFilter.fromJson(json);
  check(graphqlDeepEquals(back.toJson(), json), 'json round trip');
  check(back.days![0]!.day == 2 && back.since!.isUtc, 'dates parsed');
  check(back.page == page, 'nested input parsed');
  if (!mapped) {
    // Mapped Money has no ==, so only the wrapper compares by value.
    check(back == filter && back.hashCode == filter.hashCode,
        'equal after round trip');
  }
  check(ProductFilter.fromJson({'name': 'n'}) == const ProductFilter(name: 'n'),
      'missing fields');

  // Value equality, deep for lists.
  final a = ProductFilter(name: 'n', tags: ['x'], pages: [const Page(first: 1)]);
  final b = ProductFilter(name: 'n', tags: ['x'], pages: [const Page(first: 1)]);
  check(a == b && a.hashCode == b.hashCode, 'lists compared by elements');
  check(a != ProductFilter(name: 'n', tags: ['y']), 'different list');
  check(a != const ProductFilter(name: 'm'), 'different field');

  // copyWith changes the given fields, null included.
  final copy = filter.copyWith(name: 'Desk', int_: null, page: null);
  check(copy.name == 'Desk' && copy.int_ == null && copy.page == null,
      'copyWith sets values and null');
  check(copy.class_ == 'x' && copy.tags == filter.tags, 'other fields kept');
  check(filter.copyWith() == filter, 'copyWith() keeps everything');
  check(const Page(first: 1).copyWith(after: 'z').toJson()['after'] == 'z',
      'copyWith on another input');

  // Enums.
  final parsed = ProductFilter.fromJson({
    'name': 'n',
    'status': '_hidden',
    'statuses': ['default'],
  });
  check(parsed.status == Status.hidden_ && parsed.statuses![0] == Status.default_,
      'enum values parsed');
  Object? error;
  try {
    ProductFilter.fromJson({'name': 'n', 'status': 'NEW', 'statuses': ['NEW']});
  } catch (e) {
    error = e;
  }
  check((error == null) == fallback, 'unknown enum values');
'''
    '${fallback ? _opTypesFallbackChecks : ''}'
    '''
  print('OP TYPES $dir OK');
}
''';

const _opTypesFallbackChecks = r'''
  final unknown = ProductFilter.fromJson(
      {'name': 'n', 'status': 'NEW', 'statuses': ['NEW', 'ACTIVE']});
  check(unknown.status == Status.$unknown, r'unknown value is $unknown');
  check(unknown.statuses![0] == Status.$unknown, r'$unknown in a list');
  try {
    const ProductFilter(name: 'n', status: Status.$unknown).toJson();
    throw StateError(r'Check failed: $unknown must not be serialized');
  } on ArgumentError {
    // expected
  }
''';

// result_types: operation — classes follow the selections.
const _amountLibrary = r'''
import 'package:json_annotation/json_annotation.dart';

class Amount {
  const Amount(this.cents);
  final int cents;

  @override
  bool operator ==(Object other) => other is Amount && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;
}

class AmountConverter implements JsonConverter<Amount, int> {
  const AmountConverter();

  @override
  Amount fromJson(int json) => Amount(json);

  @override
  int toJson(Amount object) => object.cents;
}
''';

const _opsSchema = r'''
scalar DateTime
scalar JSON
scalar Amount
scalar Url

interface Node { id: ID! }

"""
A person.
"""
type User implements Node {
  id: ID!
  "Display name."
  name: String!
  email: String
  role: Role!
  roles: [Role!]!
  friends: [User!]!
  best: User
  born: DateTime
  meta: JSON
  balance: Amount
  site: Url
  tags: [String!]
  nick: String @deprecated(reason: "Use name")
}

type Post implements Node { id: ID! title: String! author: User! }

union SearchResult = User | Post

enum Role { ADMIN EDITOR }

type Query {
  me: User!
  user(id: ID!): User
  users: [User!]!
  node(id: ID!): Node
  search(q: String!): [SearchResult!]!
}

type Mutation { rename(id: ID!, name: String!): User }
''';

const _opsDocuments = [
  r'''
fragment UserBits on User { id name role }
fragment NodeBits on Node { id ... on User { name } }
fragment ResultBits on SearchResult { __typename ... on Post { title } }
fragment WithFriends on User { ...UserBits friends { ...UserBits } }
fragment PostBits on Post { id title author { ...UserBits } }
fragment QueryBits on Query { me { id } users { id name } }
''',
  r'''
query RootBits { ...QueryBits }
query RootInline { ... on Query { me { id } } }
''',
  r'''
query Partial { me { id } }
query Aliases { first: me { id } second: me { userName: name id } }
query Merged {
  me { friends { id } friends { name } best { id } ... on User { best { name } } }
}
query Conditional($x: Boolean!) {
  me {
    id
    email @include(if: $x)
    ... on User @skip(if: $x) { name }
    ...UserBits @include(if: $x)
  }
}
''',
  r'''
query Search($q: String!) {
  search(q: $q) { ... on User { id name } ...PostBits }
}
query AnyNode($id: ID!) { node(id: $id) { id ...NodeBits } }
query Results($q: String!) { search(q: $q) { ...ResultBits } }
query Me { me { ...WithFriends email } }
query Users { users { ...UserBits roles born meta balance site tags nick } }
query GetUser($id: ID!) { user(id: $id) { id name role friends { id name } } }
mutation Rename($id: ID!, $name: String!) {
  rename(id: $id, name: $name) { ...UserBits }
}
''',
];

const _opsScalars = (
  mapping: {'Amount': 'Amount', 'Url': 'String'},
  imports: {'Amount': 'package:fgc_compile_check/scalars/amount.dart'},
  converters: {'Amount': 'AmountConverter'},
);

const _opsMain = r'''
import 'package:fgc_compile_check/ops/Aliases.g.dart';
import 'package:fgc_compile_check/ops/AnyNode.g.dart';
import 'package:fgc_compile_check/ops/Conditional.g.dart';
import 'package:fgc_compile_check/ops/GetUser.g.dart';
import 'package:fgc_compile_check/ops/Me.g.dart';
import 'package:fgc_compile_check/ops/Merged.g.dart';
import 'package:fgc_compile_check/ops/Partial.g.dart';
import 'package:fgc_compile_check/ops/Rename.g.dart';
import 'package:fgc_compile_check/ops/Results.g.dart';
import 'package:fgc_compile_check/ops/RootBits.g.dart';
import 'package:fgc_compile_check/ops/RootInline.g.dart';
import 'package:fgc_compile_check/ops/Search.g.dart';
import 'package:fgc_compile_check/ops/Users.g.dart';
import 'package:fgc_compile_check/ops/fragments.dart';
import 'package:fgc_compile_check/ops/types.dart';
import 'package:fgc_compile_check/scalars/amount.dart';
import 'package:graphql/client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

/// Takes the fragment interface: works for objects of any operation.
String label(UserBits user) => '${user.id}:${user.name}:${user.role.name}';

String describe(Search_Search result) => switch (result) {
      Search_Search_OnUser(:final name) => 'user $name',
      Search_Search_OnPost(:final title, :final author) =>
        'post $title by ${label(author)}',
      Search_Search_Other(:final typename) => 'other $typename',
    };

const ann = {'__typename': 'User', 'id': '1', 'name': 'Ann', 'role': 'ADMIN'};
const bob = {'__typename': 'User', 'id': '2', 'name': 'Bob', 'role': 'EDITOR'};

class FakeLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    yield Response(data: {
      'rename': {...ann, 'name': 'Zed'},
    }, response: const {});
  }
}

Future<void> main() async {
  // Partial selection: `name` is non-null in the schema but not selected.
  final partial = parsePartialData({
    'me': {'__typename': 'User', 'id': '1'},
  });
  check(partial.id == '1' && partial.typename == 'User', 'partial selection');

  // Aliases are separate fields.
  final aliases = parseAliasesData({
    'first': {'__typename': 'User', 'id': '1'},
    'second': {'__typename': 'User', 'userName': 'Ann', 'id': '1'},
  });
  check(aliases.first.id == '1' && aliases.second.userName == 'Ann',
      'aliases');

  // The same field selected twice: one field with merged subfields.
  final merged = parseMergedData({
    'me': {
      '__typename': 'User',
      'friends': [
        {'__typename': 'User', 'id': '2', 'name': 'Bob'},
      ],
      'best': {'__typename': 'User', 'id': '3', 'name': 'Cy'},
    },
  });
  check(merged.friends.single.id == '2' && merged.friends.single.name == 'Bob',
      'merged list selections');
  check(merged.best!.id == '3' && merged.best!.name == 'Cy',
      'merged through an inline fragment');

  // @skip/@include make fields nullable; a conditional spread is not an
  // interface of the class.
  final skipped = parseConditionalData({
    'me': {'__typename': 'User', 'id': '1'},
  });
  check(skipped.email == null && skipped.name == null && skipped.role == null,
      'conditional fields may be missing');
  final Object conditional = skipped;
  check(conditional is! UserBits, 'conditional spread is not implemented');
  final included = parseConditionalData({
    'me': {...ann, 'email': 'a@x'},
  });
  check(included.name == 'Ann' && included.role == Role.ADMIN, 'included');

  // Unions: pattern matching over the sealed class, unknown types -> _Other.
  final results = parseSearchData({
    'search': [
      {...ann},
      {
        '__typename': 'Post',
        'id': 'p',
        'title': 'Hi',
        'author': {...bob},
      },
      {'__typename': 'Ad'},
    ],
  });
  check(describe(results[0]) == 'user Ann', 'union member');
  check(describe(results[1]) == 'post Hi by 2:Bob:EDITOR',
      'fragment on a union member');
  check(describe(results[2]) == 'other Ad', 'unknown type');
  check(results[1] is PostBits, 'variant implements the fragment');

  // Interfaces with a fragment on the interface.
  final user = parseAnyNodeData({'node': ann})!;
  check(user is AnyNode_Node_OnUser && user.name == 'Ann', 'interface variant');
  check(user is NodeBits_OnUser, 'type-specific fragment interface');
  final robot = parseAnyNodeData({
    'node': {'__typename': 'Robot', 'id': '9'},
  })!;
  check(robot is AnyNode_Node_Other && robot.id == '9', 'interface _Other');
  final NodeBits bits = robot;
  check(bits.id == '9', 'sealed base implements the fragment');

  // Fragment on a union, with a part for one member.
  final union = parseResultsData({
    'search': [
      {'__typename': 'Post', 'title': 'T'},
      {'__typename': 'User'},
    ],
  });
  check(union[0] is ResultBits_OnPost &&
          (union[0] as ResultBits_OnPost).title == 'T',
      'fragment on a union');
  check(union[1] is Results_Search_Other, 'member without own fields');

  // Nested fragments; one function for objects from two operations.
  final me = parseMeData({
    'me': {
      ...ann,
      'email': 'a@x',
      'friends': [bob],
    },
  });
  final users = parseUsersData({
    'users': [
      {
        ...bob,
        'roles': ['ADMIN', 'EDITOR'],
        'born': '2024-01-02T03:04:05.000Z',
        'meta': {'a': [1, 2]},
        'balance': 150,
        'site': 'https://x',
        'tags': ['a', 'b'],
        'nick': 'B',
      },
    ],
  });
  check(label(me) == '1:Ann:ADMIN', 'fragment interface (Me)');
  check(label(me.friends.single) == '2:Bob:EDITOR', 'nested fragment');
  check(label(users.single) == '2:Bob:EDITOR', 'fragment interface (Users)');
  final WithFriends withFriends = me;
  check(withFriends.friends.single.name == 'Bob', 'covariant nested type');

  // Scalars, enums, custom scalars and scalar_mapping.
  final u = users.single;
  check(u.roles[1] == Role.EDITOR, 'enum list');
  check(u.born!.isUtc && u.born!.year == 2024, 'DateTime');
  check(u.meta!.raw is Map, 'custom scalar keeps the raw JSON');
  check(u.balance == const Amount(150), 'mapped scalar with a converter');
  check(u.site == 'https://x', 'mapped scalar (short form)');

  // toJson -> fromJson, == and hashCode (deep for lists).
  final json = u.toJson();
  check(json['__typename'] == 'User' && json['balance'] == 150 &&
          json['born'] == '2024-01-02T03:04:05.000Z' &&
          json['roles'][1] == 'EDITOR',
      'toJson in response shape');
  final again = Users_Users.fromJson(json);
  check(again == u && again.hashCode == u.hashCode, 'round trip');
  check(Me_Me.fromJson(me.toJson()) == me, 'round trip with nested lists');
  check(u.copyWith(tags: ['a', 'c']) != u, 'deep list inequality');
  check(u.copyWith(tags: ['a', 'b']) == u, 'deep list equality');

  // copyWith, including clearing a nullable field.
  final renamed = u.copyWith(name: 'Bea');
  check(renamed.name == 'Bea' && renamed.id == '2', 'copyWith replaces');
  check(u.copyWith(born: null).born == null, 'copyWith sets null');
  check(u.copyWith().born == u.born, 'copyWith keeps unpassed fields');

  // Typed write<Op>, then read<Op> through the normalized cache.
  final client = GraphQLClient(
    link: FakeLink(),
    cache: GraphQLCache(possibleTypes: possibleTypes),
    defaultPolicies: DefaultPolicies(
      mutate: Policies(fetch: FetchPolicy.noCache),
    ),
  );
  const vars = GetUserVariables(id: '1');
  check(client.readGetUser(vars) == null, 'cache miss');
  final written = GetUser_User(
    typename: 'User',
    id: '1',
    name: 'Ann',
    role: Role.ADMIN,
    friends: [GetUser_User_Friends(typename: 'User', id: '2', name: 'Bob')],
  );
  client.writeGetUser(vars, written);
  check(client.readGetUser(vars) == written, 'typed cache round trip');
  client.writeGetUser(vars, written.copyWith(name: 'Ann 2'));
  check(client.readGetUser(vars)!.name == 'Ann 2', 'cache update');

  // Root selections through a fragment spread or an inline fragment.
  final root = parseRootBitsData({
    'me': {'__typename': 'User', 'id': '1'},
    'users': [bob],
  });
  final QueryBits queryBits = root;
  check(queryBits.me.id == '1' && root.users.single.name == 'Bob',
      'root fragment spread');
  check(RootBitsResult.fromJson(root.toJson()) == root, 'root round trip');
  final inline = parseRootInlineData({
    'me': {'__typename': 'User', 'id': '1'},
  });
  check(inline.id == '1', 'root inline fragment');

  final rename = await client.renameData();
  check(rename!.name == 'Zed' && label(rename) == '1:Zed:ADMIN', 'mutation');
  print('OPS OK');
}
''';

// Legacy nullability: every level nullable.
const _opsLegacyMain = r'''
import 'package:fgc_compile_check/ops_legacy/Me.g.dart';
import 'package:fgc_compile_check/ops_legacy/Search.g.dart';
import 'package:fgc_compile_check/ops_legacy/fragments.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  final me = parseMeData({
    'me': {
      '__typename': 'User',
      'id': '1',
      'friends': [null],
    },
  })!;
  final UserBits bits = me;
  check(bits.name == null && me.friends!.single == null, 'nullable levels');
  check(Me_Me.fromJson(me.toJson()) == me, 'round trip');
  final search = parseSearchData({
    'search': [null, {'__typename': 'User', 'id': '1'}],
  })!;
  check(search[0] == null && search[1] is Search_Search_OnUser,
      'nullable list elements');
  print('OPS LEGACY OK');
}
''';

// unknown_enum_fallback: `<field>Raw` next to `$unknown`.
const _opsFallbackMain = r'''
import 'package:fgc_compile_check/ops_fallback/Users.g.dart';
import 'package:fgc_compile_check/ops_fallback/fragments.dart';
import 'package:fgc_compile_check/ops_fallback/types.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  final u = parseUsersData({
    'users': [
      {
        '__typename': 'User',
        'id': '1',
        'name': 'Ann',
        'role': 'OWNER',
        'roles': ['ADMIN', 'OWNER'],
      },
    ],
  }).single;
  check(u.role == Role.$unknown && u.roleRaw == 'OWNER', 'raw value');
  final UserBits bits = u;
  check(bits.roleRaw == 'OWNER', 'raw value on the fragment interface');
  check(u.roles[1] == Role.$unknown && u.rolesRaw![1] == 'OWNER',
      'raw values of a list');
  final json = u.toJson();
  check(!json.containsKey('roleRaw') && !json.containsKey('rolesRaw'),
      'raw fields are not keys of their own');
  check(json['role'] == 'OWNER' && json['roles'][1] == 'OWNER',
      r'$unknown is written back as the raw value');
  check(Users_Users.fromJson(json) == u, 'round trip');
  final known = u.copyWith(role: Role.EDITOR).toJson();
  check(known['role'] == 'EDITOR', 'known value serialized');
  print('OPS FALLBACK OK');
}
''';

// read<Fragment>Fragment / write<Fragment>Fragment and a fragment on an
// introspection type.
const _fragsSchema = r'''
interface Node { id: ID! }
type User implements Node { id: ID! name: String! friends(first: Int): [User!]! }
type Post implements Node { id: ID! title: String! }
type Query { user(id: ID!): User node(id: ID!): Node }
''';

const _fragsDocuments = [
  r'''
fragment UserBits on User { id name }
fragment UserFriends on User { id friends(first: $n) { id name } }
fragment NodeBits on Node { id ... on User { name } ... on Post { title } }
fragment FullType on __Type { name kind }
''',
  r'''
query GetUser($id: ID!) { user(id: $id) { ...UserBits } }
query GetFriends($id: ID!, $n: Int) { user(id: $id) { ...UserFriends } }
query GetNode($id: ID!) { node(id: $id) { ...NodeBits } }
query Introspect { __schema { types { ...FullType } } }
''',
];

const _fragsMain = r'''
import 'package:fgc_compile_check/frags/GetFriends.g.dart';
import 'package:fgc_compile_check/frags/GetNode.g.dart';
import 'package:fgc_compile_check/frags/GetUser.g.dart';
import 'package:fgc_compile_check/frags/Introspect.g.dart';
import 'package:fgc_compile_check/frags/fragments.dart';
import 'package:fgc_compile_check/frags/types.dart';
import 'package:graphql/client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

class NoLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      throw UnsupportedError('cache only');
}

void main() {
  final client = GraphQLClient(
    link: NoLink(),
    cache: GraphQLCache(possibleTypes: possibleTypes),
  );

  // Not cached.
  check(client.readUserBitsFragment({'id': '1'}) == null, 'cache miss');

  // An object from an operation, written through the fragment.
  const vars = GetUserVariables(id: '1');
  final user = parseGetUserData({
    'user': {'__typename': 'User', 'id': '1', 'name': 'Ann'},
  })!;
  client.writeGetUser(vars, user);
  client.writeUserBitsFragment({'id': '1'}, user.copyWith(name: 'Ann 2'));
  final bits = client.readUserBitsFragment({'id': '1'});
  check(bits == const UserBitsData(typename: 'User', id: '1', name: 'Ann 2'),
      'fragment read back');
  check(client.readGetUser(vars) == user.copyWith(name: 'Ann 2'),
      'operation sees the fragment write');
  // __typename given explicitly works too.
  check(client.readUserBitsFragment({'__typename': 'User', 'id': '1'}) == bits,
      'explicit __typename');

  // Data classes can be written as well.
  const cy = UserBitsData(typename: 'User', id: '3', name: 'Cy');
  client.writeUserBitsFragment({'id': '3'}, cy);
  check(client.readUserBitsFragment({'id': '3'}) == cy, 'data class round trip');

  // Variables in fragment arguments.
  final friends = parseGetFriendsData({
    'user': {
      '__typename': 'User',
      'id': '1',
      'friends': [
        {'__typename': 'User', 'id': '2', 'name': 'Bob'},
      ],
    },
  })!;
  client.writeUserFriendsFragment({'id': '1'}, friends, variables: {'n': 1});
  final read = client.readUserFriendsFragment({'id': '1'}, variables: {'n': 1});
  check(read != null && read.friends.single.name == 'Bob', 'with variables');
  check(read == UserFriendsData.fromJson(friends.toJson()), 'equal data');
  check(client.readUserFriendsFragment({'id': '1'}, variables: {'n': 2}) == null,
      'other variables are not cached');
  // user(id: "1") is cached by writeGetUser above.
  check(
      client
              .readGetFriends(const GetFriendsVariables(id: '1', n: 1))!
              .friends
              .single
              .name ==
          'Bob',
      'operation reads the fragment write');

  // Fragment on an interface: __typename comes from the data on write and
  // is required on read.
  final post = parseGetNodeData({
    'node': {'__typename': 'Post', 'id': 'p', 'title': 'T'},
  })!;
  client.writeNodeBitsFragment({'id': 'p'}, post);
  final node = client.readNodeBitsFragment({'__typename': 'Post', 'id': 'p'});
  check(node is NodeBitsData_OnPost && node.title == 'T', 'abstract variant');
  check(node == NodeBitsData.fromJson(post.toJson()), 'abstract equality');
  var threw = false;
  try {
    client.readNodeBitsFragment({'id': 'p'});
  } on ArgumentError {
    threw = true;
  }
  check(threw, 'abstract read needs __typename');
  check(client.readNodeBitsFragment({'__typename': 'User', 'id': 'p'}) == null,
      'other type not cached');

  // Fragments on introspection types: the result stays raw JSON.
  final schema = parseIntrospectData({
    '__schema': {
      'types': [
        {'name': 'User', 'kind': 'OBJECT'},
      ],
    },
  });
  check(schema!['types'][0]['name'] == 'User', 'introspection data');
  print('FRAGS OK');
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

    const schemaTypes = 'schema';
    const mappedScalars = (
      mapping: {'Money': 'Money', 'Cents': 'Cents', 'Date': 'DateTime'},
      imports: {
        'Money': 'package:fgc_compile_check/scalars/money.dart',
        'Cents': 'package:fgc_compile_check/scalars/money.dart',
      },
      converters: {'Money': 'MoneyConverter'},
    );
    final files = {
      // result_types: schema (the 2.x output).
      ..._generate('legacy', schema, documents,
          strict: false, resultTypes: schemaTypes),
      ..._generate('strict', schema, documents,
          strict: true, resultTypes: schemaTypes),
      ..._generate('smoke', _smokeSchema, _smokeDocuments,
          strict: true, resultTypes: schemaTypes),
      ..._generate('fallback', _smokeSchema, _smokeDocuments,
          strict: true,
          resultTypes: schemaTypes,
          unknownEnumFallback: true,
          deprecatedAnnotations: true),
      ..._generate('collide', _collideSchema, _collideDocuments,
          strict: true, resultTypes: schemaTypes),
      ..._generate('edge', _edgeSchema, _edgeDocuments,
          strict: true, resultTypes: schemaTypes),
      ..._generate('edge_legacy', _edgeSchema, _edgeDocuments,
          strict: false, resultTypes: schemaTypes),
      ..._generate('client_names', _clientNamesSchema, _clientNamesDocuments,
          strict: true, resultTypes: schemaTypes),
      ..._generate('nulls', _nullsSchema, _nullsDocuments,
          strict: true, resultTypes: schemaTypes, includeNullInputs: true),
      ..._generate('nulls_default', _nullsSchema, _nullsDocuments,
          strict: true, resultTypes: schemaTypes),
      // No object types: nothing for json_serializable, so no part file.
      ..._generate(
          'no_objects', 'enum Color { RED GREEN }\nscalar JSON', const [],
          strict: true, resultTypes: schemaTypes),
      ..._generate('mapped', _mappedSchema, _mappedDocuments,
          strict: true,
          resultTypes: schemaTypes,
          scalarMapping: mappedScalars.mapping,
          scalarImports: mappedScalars.imports,
          scalarConverters: mappedScalars.converters),
      // Operation result types: types.dart alone (operation files still
      // use schema result types in these checks).
      ..._generate('op_types', _opTypesSchema, const [],
          strict: true, resultTypes: 'operation'),
      ..._generate('op_types_legacy', _opTypesSchema, const [],
          strict: false, resultTypes: 'operation'),
      ..._generate('op_types_nulls', _opTypesSchema, const [],
          strict: true, includeNullInputs: true, resultTypes: 'operation'),
      ..._generate('op_types_fallback', _opTypesSchema, const [],
          strict: true,
          unknownEnumFallback: true,
          deprecatedAnnotations: true,
          resultTypes: 'operation'),
      ..._generate('op_types_mapped', _opTypesSchema, const [],
          strict: true,
          scalarMapping: {'Money': 'Money'},
          scalarImports: {
            'Money': 'package:fgc_compile_check/scalars/money.dart'
          },
          scalarConverters: {'Money': 'MoneyConverter'},
          resultTypes: 'operation'),
      'bin/op_types.dart': _opTypesMain('op_types'),
      'bin/op_types_legacy.dart': _opTypesMain('op_types_legacy'),
      'bin/op_types_nulls.dart': _opTypesMain('op_types_nulls', nulls: true),
      'bin/op_types_fallback.dart':
          _opTypesMain('op_types_fallback', fallback: true),
      'bin/op_types_mapped.dart': _opTypesMain('op_types_mapped', mapped: true),
      'lib/scalars/money.dart': _mappedLibrary,

      // result_types: operation.
      ..._generate('ops', _opsSchema, _opsDocuments,
          strict: true,
          deprecatedAnnotations: true,
          scalarMapping: _opsScalars.mapping,
          scalarImports: _opsScalars.imports,
          scalarConverters: _opsScalars.converters),
      ..._generate('ops_legacy', _opsSchema, _opsDocuments,
          strict: false,
          scalarMapping: _opsScalars.mapping,
          scalarImports: _opsScalars.imports,
          scalarConverters: _opsScalars.converters),
      ..._generate('ops_fallback', _opsSchema, _opsDocuments,
          strict: true,
          unknownEnumFallback: true,
          scalarMapping: _opsScalars.mapping,
          scalarImports: _opsScalars.imports,
          scalarConverters: _opsScalars.converters),
      'lib/scalars/amount.dart': _amountLibrary,
      'bin/ops.dart': _opsMain,
      'bin/ops_legacy.dart': _opsLegacyMain,
      'bin/ops_fallback.dart': _opsFallbackMain,
      ..._generate('frags', _fragsSchema, _fragsDocuments, strict: true),
      ..._generate('frags_legacy', _fragsSchema, _fragsDocuments,
          strict: false),
      'bin/frags.dart': _fragsMain,
      ..._generate('legacy_ops', schema, documents, strict: false),
      ..._generate('strict_ops', schema, documents, strict: true),
      ..._generate('smoke_ops', _smokeSchema, _smokeDocuments, strict: true),
      ..._generate('fallback_ops', _smokeSchema, _smokeDocuments,
          strict: true, unknownEnumFallback: true, deprecatedAnnotations: true),
      ..._generate('collide_ops', _collideSchema, _collideDocuments,
          strict: true),
      ..._generate('edge_ops', _edgeSchema, _edgeDocuments, strict: true),
      ..._generate('edge_legacy_ops', _edgeSchema, _edgeDocuments,
          strict: false),
      ..._generate(
          'client_names_ops', _clientNamesSchema, _clientNamesDocuments,
          strict: true),
      ..._generate('nulls_ops', _nullsSchema, _nullsDocuments,
          strict: true, includeNullInputs: true),
      ..._generate('mapped_ops', _mappedSchema, _mappedDocuments,
          strict: true,
          scalarMapping: mappedScalars.mapping,
          scalarImports: mappedScalars.imports,
          scalarConverters: mappedScalars.converters),
      'bin/edge_ops.dart': _edgeMain.replaceAll('/edge/', '/edge_ops/'),
      'bin/mapped_ops.dart': _mappedMain.replaceAll('/mapped/', '/mapped_ops/'),
      'bin/nulls_ops.dart': _nullsMain('nulls_ops', sendsNulls: true),
      'bin/mapped.dart': _mappedMain,
      'bin/smoke.dart': _smokeMain,
      'bin/fallback.dart': _fallbackMain,
      'bin/collide.dart': _collideMain,
      'bin/edge.dart': _edgeMain,
      'bin/client_names.dart': _clientNamesMain,
      'bin/nulls.dart': _nullsMain('nulls', sendsNulls: true),
      'bin/nulls_default.dart': _nullsMain('nulls_default', sendsNulls: false),
    };

    // Fragments on introspection types get no declarations.
    expect(files['lib/frags/fragments.dart'], isNot(contains('FullType')));

    // Operation result types need no json_serializable output.
    for (final entry in files.entries) {
      if (entry.key.startsWith('lib/op_types')) {
        expect(entry.value, isNot(contains('.g.dart')), reason: entry.key);
      }
    }

    final result = await compileGenerated(
      files,
      runScripts: [
        'bin/smoke.dart',
        'bin/fallback.dart',
        'bin/collide.dart',
        'bin/mapped.dart',
        'bin/edge.dart',
        'bin/client_names.dart',
        'bin/nulls.dart',
        'bin/nulls_default.dart',
        'bin/op_types.dart',
        'bin/op_types_legacy.dart',
        'bin/op_types_nulls.dart',
        'bin/op_types_fallback.dart',
        'bin/op_types_mapped.dart',
        'bin/ops.dart',
        'bin/ops_legacy.dart',
        'bin/ops_fallback.dart',
        'bin/frags.dart',
        'bin/edge_ops.dart',
        'bin/mapped_ops.dart',
        'bin/nulls_ops.dart',
      ],
      // json_serializable's output uses deprecated members when they are
      // annotated; that trade-off of deprecated_annotations is documented.
      mustBeClean: (path) =>
          path.startsWith('lib/') &&
          !const {
            'lib/fallback/types.g.dart',
            'lib/fallback_ops/types.g.dart',
            'lib/ops/types.g.dart',
          }.contains(path),
    );
    expect(result.errors, isEmpty, reason: result.log);
  });
}
