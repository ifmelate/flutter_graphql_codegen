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
  bool unknownEnumFallback = false,
  bool deprecatedAnnotations = false,
  Map<String, String> scalarMapping = const {},
  Map<String, String> scalarImports = const {},
  Map<String, String> scalarConverters = const {},
}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = strict;
  CodegenConfigContext.unknownEnumFallback = unknownEnumFallback;
  CodegenConfigContext.deprecatedAnnotations = deprecatedAnnotations;
  CodegenConfigContext.scalarMapping = Map.of(scalarMapping);
  CodegenConfigContext.scalarImports = Map.of(scalarImports);
  CodegenConfigContext.scalarConverters = Map.of(scalarConverters);
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
type Query { a: Int }
type Mutation { b: Int }
type Subscription { c: Int }
''';

const _clientNamesDocuments = [
  r'''
query Query { a }
query Fragment { a }
query Link { a }
mutation Mutate { b }
subscription Subscribe { c }
''',
];

const _clientNamesMain = r'''
import 'package:fgc_compile_check/client_names/Fragment.g.dart';
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
  client.writeFragment_({'__typename': 'Query', 'a': 6});
  check(client.readFragment_() == 6, 'readFragment_/writeFragment_');
  check(await client.linkData() == 1 && client.link is FakeLink,
      'link_ keeps the client link');
  check((await client.link_()).data!['a'] == 1, 'link_');
  check(await client.mutateData() == 2, 'mutate_');
  check(await client.subscribeData().first == 3, 'subscribe_');
  print('CLIENT NAMES OK');
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
      ..._generate('fallback', _smokeSchema, _smokeDocuments,
          strict: true, unknownEnumFallback: true, deprecatedAnnotations: true),
      ..._generate('collide', _collideSchema, _collideDocuments, strict: true),
      ..._generate('edge', _edgeSchema, _edgeDocuments, strict: true),
      ..._generate('edge_legacy', _edgeSchema, _edgeDocuments, strict: false),
      ..._generate('client_names', _clientNamesSchema, _clientNamesDocuments,
          strict: true),
      // No object types: nothing for json_serializable, so no part file.
      ..._generate('no_objects', 'enum Color { RED GREEN }\nscalar JSON',
          const [],
          strict: true),
      ..._generate('mapped', _mappedSchema, _mappedDocuments,
          strict: true,
          scalarMapping: {
            'Money': 'Money',
            'Cents': 'Cents',
            'Date': 'DateTime'
          },
          scalarImports: {
            'Money': 'package:fgc_compile_check/scalars/money.dart',
            'Cents': 'package:fgc_compile_check/scalars/money.dart',
          },
          scalarConverters: {
            'Money': 'MoneyConverter'
          }),
      'lib/scalars/money.dart': _mappedLibrary,
      'bin/mapped.dart': _mappedMain,
      'bin/smoke.dart': _smokeMain,
      'bin/fallback.dart': _fallbackMain,
      'bin/collide.dart': _collideMain,
      'bin/edge.dart': _edgeMain,
      'bin/client_names.dart': _clientNamesMain,
    };

    final result = await compileGenerated(
      files,
      runScripts: [
        'bin/smoke.dart',
        'bin/fallback.dart',
        'bin/collide.dart',
        'bin/mapped.dart',
        'bin/edge.dart',
        'bin/client_names.dart',
      ],
      // json_serializable's output uses deprecated members when they are
      // annotated; that trade-off of deprecated_annotations is documented.
      mustBeClean: (path) =>
          path.startsWith('lib/') && path != 'lib/fallback/types.g.dart',
    );
    expect(result.errors, isEmpty, reason: result.log);
  });
}
