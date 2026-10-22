// End to end checks of explicit nulls (input and variables classes) and the
// `enums:` option: the generated code must pass `dart analyze` and behave
// correctly at runtime.
//
// Slow (creates a package and runs build_runner); skip locally with
// `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

import 'support/compile_harness.dart';

/// Generates types.dart, fragments.dart (operation result types) and one file
/// per operation into `lib/<dir>/`.
Map<String, String> _generate(
  String dir,
  String schema,
  List<String> documents, {
  bool strict = true,
  String resultTypes = 'operation',
  bool includeNullInputs = false,
  bool unknownEnumFallback = false,
  Map<String, EnumConfig> enums = const {},
}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.resultTypes = resultTypes;
  CodegenConfigContext.strictNullability = strict;
  CodegenConfigContext.includeNullInputs = includeNullInputs;
  CodegenConfigContext.unknownEnumFallback = unknownEnumFallback;
  CodegenConfigContext.enumConfigs = Map.of(enums);
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

// -----------------------------------------------------------------------------
// Explicit nulls
// -----------------------------------------------------------------------------

const _nullsSchema = r'''
input Patch { id: ID! name: String note: String tags: [String!] page: Page }
input Page { first: Int! after: String }
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

/// Runtime checks; [nulls] is include_null_inputs, [inputs] whether input
/// classes are the hand-written ones (operation result types).
String _nullsMain(String dir, {bool nulls = false, bool inputs = true}) => '''
import 'package:fgc_compile_check/$dir/Update.g.dart';
import 'package:fgc_compile_check/$dir/types.dart';
import 'package:graphql/client.dart';

const nulls = $nulls;
'''
    r'''

final requests = <Request>[];

class FakeLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests.add(request);
    yield Response(data: const {'update': true}, response: const {});
  }
}

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

Future<void> main() async {
'''
    '${inputs ? _inputChecks : ''}'
    r'''
  // Variables: explicit null only when asked for.
  final patch = Patch(id: '1', name: 'x');
  final plain = UpdateVariables(id: '1', patch: patch);
  final json = plain.toJson();
  check(json.containsKey('tag') == nulls, 'null variable');
  check(json['limit'] == 5, 'variable with a default sent with it');
  final explicit = UpdateVariables.withNulls(
      id: '1', patch: patch, tag: null, limit: null);
  final explicitJson = explicit.toJson();
  check(explicitJson.containsKey('tag') && explicitJson['tag'] == null,
      'withNulls sends a null variable');
  check(explicitJson.containsKey('limit') && explicitJson['limit'] == null,
      'withNulls sends null for a variable with a default');
  final absent = UpdateVariables.withNulls(id: '1', patch: patch).toJson();
  check(absent['limit'] == 5 && absent.containsKey('tag') == nulls,
      'withNulls leaves out what is not passed (a default is sent)');

  // copyWith.
  final cleared = plain.copyWith(limit: null);
  check(cleared.toJson().containsKey('limit') && cleared.limit == null,
      'copyWith(x: null) sends null');
  check(cleared.copyWith(id: '2').toJson().containsKey('limit'),
      'copyWith keeps an explicit null');
  check(plain.copyWith(limit: 7).toJson()['limit'] == 7, 'copyWith sets');
  check(plain.copyWith() == plain, 'copyWith() keeps everything');
  check(plain.copyWith(id: '2').id == '2' && plain.copyWith(id: '2') != plain,
      'copyWith replaces a required variable');

  // == and hashCode.
  final same = UpdateVariables(id: '1', patch: patch);
  check(plain == same && plain.hashCode == same.hashCode, 'value equality');
  check(plain != cleared, 'explicit null differs from absent');
  check(
      cleared ==
          UpdateVariables.withNulls(id: '1', patch: patch, limit: null),
      'copyWith(x: null) equals withNulls(x: null)');
  check(<UpdateVariables>{plain, same, cleared}.length == 2, 'in a set');

  // What reaches the link.
  final client = GraphQLClient(
    link: FakeLink(),
    cache: GraphQLCache(),
    defaultPolicies: DefaultPolicies(
      mutate: Policies(fetch: FetchPolicy.noCache),
    ),
  );
  await client.mutate(updateMutationOptions(explicit));
  final sent = requests.last.variables;
  check(sent.containsKey('tag') && sent['tag'] == null, 'null on the wire');
  await client.updateData(plain.toJson());
  check(requests.last.variables['limit'] == 5, 'default on the wire');
  print('NULLS OK');
}
''';

const _inputChecks = r'''
  // Inputs: X(b: null) leaves b out (unless include_null_inputs).
  const plainPatch = Patch(id: '1', name: null);
  check(plainPatch.toJson().containsKey('name') == nulls, 'X(b: null)');
  check(plainPatch.toJson().containsKey('tags') == nulls &&
          plainPatch.toJson()['tags'] == null,
      'a nullable list defaults to null');

  // withNulls: a null argument is sent, an omitted one is not.
  const withNull = Patch.withNulls(id: '1', name: null, tags: null);
  final withNullJson = withNull.toJson();
  check(withNullJson.containsKey('name') && withNullJson['name'] == null,
      'explicit null sent');
  check(withNullJson.containsKey('tags') && withNullJson['tags'] == null,
      'explicit null list sent');
  check(withNullJson.containsKey('note') == nulls, 'absent field left out');
  check(const Patch.withNulls(id: '1').toJson().containsKey('tags') == nulls,
      'withNulls leaves an unset list out');
  check(identical(const Patch.withNulls(id: '1', name: null),
          const Patch.withNulls(id: '1', name: null)),
      'withNulls is const');

  // copyWith(x: null) sends null; other fields keep their state.
  final copy = const Patch(id: '1', name: 'a').copyWith(name: null);
  check(copy.toJson().containsKey('name') && copy.name == null,
      'copyWith(x: null) sends null');
  final again = copy.copyWith(note: 'n');
  check(again.toJson().containsKey('name') && again.toJson()['note'] == 'n',
      'copyWith keeps an explicit null');
  check(copy.copyWith(name: 'b').toJson()['name'] == 'b', 'and can set it');
  check(const Patch(id: '1').copyWith(page: const Page(first: 1))
          .toJson()['page']['first'] == 1,
      'copyWith sets a nested input');

  // == tells explicit null from absent (unless every null is sent anyway).
  check((const Patch(id: '1') == const Patch.withNulls(id: '1', name: null)) ==
          nulls,
      'explicit null vs absent');
  check(copy == const Patch.withNulls(id: '1', name: null),
      'copyWith(x: null) == withNulls(x: null)');
  check(copy.hashCode == const Patch.withNulls(id: '1', name: null).hashCode,
      'hashCode');
  check(const Patch(id: '1') == const Patch.withNulls(id: '1'),
      'nothing passed: equal');

  // fromJson: a key with null is an explicit null, a missing key is absent.
  const nameNull = Patch.withNulls(id: '1', name: null);
  check(Patch.fromJson(nameNull.toJson()) == nameNull, 'round trip of null');
  check(Patch.fromJson({'id': '1'}) == const Patch.withNulls(id: '1'),
      'missing keys');
  check(Patch.fromJson({'id': '1'}).toJson().containsKey('note') == nulls,
      'missing key not sent');
  check(Patch.fromJson({'id': '1', 'page': {'first': 2, 'after': null}})
          .page!
          .toJson()
          .containsKey('after'),
      'nested explicit null');

  // In variables, which stay const too.
  final vars = UpdateVariables(
      id: '1', patch: const Patch(id: '1').copyWith(note: null)).toJson();
  check((vars['patch'] as Map).containsKey('note'), 'nested in variables');
  const constVars = UpdateVariables.withNulls(
      id: '1', patch: Patch.withNulls(id: '1', note: null), tag: null);
  check(constVars.toJson()['tag'] == null &&
          (constVars.toJson()['patch'] as Map).containsKey('note'),
      'const withNulls variables');
  check(UpdateVariables(id: '1', patch: const Patch(id: '1', name: 'x')) ==
          UpdateVariables(id: '1', patch: const Patch(id: '1', name: 'x')),
      'variables compare inputs by value');
''';

// -----------------------------------------------------------------------------
// enums:
// -----------------------------------------------------------------------------

const _roleLibrary = r'''
/// A user type the `Role` enum is mapped to.
class AppRole {
  const AppRole(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is AppRole && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'AppRole($name)';
}

AppRole roleFromJson(String json) => AppRole(json.toLowerCase());

String roleToJson(AppRole role) => role.name.toUpperCase();
''';

const _enums = {
  'Role': EnumConfig(
    type: 'AppRole',
    import: 'package:fgc_compile_check/enums/app_role.dart',
    fromJson: 'roleFromJson',
    toJson: 'roleToJson',
  ),
  'Status': EnumConfig(fallback: 'OTHER'),
};

const _enumsSchema = r'''
enum Role { ADMIN GUEST }
enum Status { ACTIVE OTHER }
enum Kind { A B }
type User {
  id: ID!
  role: Role!
  roles: [Role!]!
  maybe: Role
  maybes: [Role]
  status: Status!
  statuses: [Status]
  kind: Kind
}
input UserFilter { role: Role roles: [Role!] status: Status statuses: [Status!] }
type Query {
  users(role: Role, filter: UserFilter): [User!]!
  me: User!
  status: Status!
}
''';

const _enumsDocuments = [
  r'''
fragment UserBits on User { id role status }
query Users($role: Role, $filter: UserFilter) {
  users(role: $role, filter: $filter) { ...UserBits roles maybe maybes statuses kind }
}
query Me { me { ...UserBits } }
query CurrentStatus { status }
''',
];

const _enumsMain = r'''
import 'package:fgc_compile_check/enums/app_role.dart';
import 'package:fgc_compile_check/enums_ops/CurrentStatus.g.dart';
import 'package:fgc_compile_check/enums_ops/Users.g.dart';
import 'package:fgc_compile_check/enums_ops/fragments.dart';
import 'package:fgc_compile_check/enums_ops/types.dart';
import 'package:graphql/client.dart';

final requests = <Request>[];

const ann = {
  '__typename': 'User',
  'id': '1',
  'role': 'ADMIN',
  'roles': ['ADMIN', 'GUEST'],
  'maybe': null,
  'maybes': ['GUEST', null],
  'status': 'NEW',
  'statuses': ['NEW', null, 'ACTIVE'],
  'kind': 'C',
};

class FakeLink extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests.add(request);
    yield Response(
        data: const {'__typename': 'Query', 'users': [ann]},
        response: const {});
  }
}

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

Future<void> main() async {
  const admin = AppRole('admin');
  const guest = AppRole('guest');

  // Results: the user type through the user's functions.
  final user = parseUsersData({'users': [ann]}).single;
  check(user.role == admin, 'custom type in a result');
  check(user.roles[1] == guest, 'custom type in a list');
  check(user.maybe == null && user.maybes![0] == guest && user.maybes![1] == null,
      'nullable custom type');

  // fallback: unknown values decode to OTHER, the raw string is kept.
  check(user.status == Status.OTHER && user.statusRaw == 'NEW', 'fallback');
  check(user.statuses![0] == Status.OTHER && user.statuses![1] == null &&
          user.statuses![2] == Status.ACTIVE,
      'fallback in a list');
  check(user.statusesRaw![0] == 'NEW', 'raw values of a list');
  check(user.kind == Kind.$unknown && user.kindRaw == 'C',
      r'other enums keep $unknown');

  // Fragment interfaces.
  final UserBits bits = user;
  check(bits.role == admin && bits.statusRaw == 'NEW', 'fragment interface');

  // toJson writes the server's strings back.
  final json = user.toJson();
  check(json['role'] == 'ADMIN' && json['roles'][1] == 'GUEST',
      'custom type serialized with to_json');
  check(json['status'] == 'NEW' && json['statuses'][0] == 'NEW' &&
          json['statuses'][1] == null && json['statuses'][2] == 'ACTIVE',
      'unknown value written back as sent');
  check(Users_Users.fromJson(json) == user, 'round trip');
  final active = Users_Users.fromJson({...ann, 'status': 'ACTIVE'});
  check(active.copyWith(status: Status.OTHER).toJson()['status'] == 'OTHER',
      'a changed value is not replaced by the raw one');
  check(user.copyWith(status: Status.ACTIVE).toJson()['status'] == 'ACTIVE',
      'a known value is serialized');

  // Inputs and variables.
  final vars = UsersVariables(
    role: guest,
    filter: const UserFilter(
        role: admin, roles: [guest], status: Status.OTHER, statuses: [Status.ACTIVE]),
  );
  final varsJson = vars.toJson();
  check(varsJson['role'] == 'GUEST', 'custom type in variables');
  final filter = varsJson['filter'] as Map<String, dynamic>;
  check(filter['role'] == 'ADMIN' && filter['roles'][0] == 'GUEST' &&
          filter['status'] == 'OTHER' && filter['statuses'][0] == 'ACTIVE',
      'custom type and fallback enum in an input');
  final parsedFilter =
      UserFilter.fromJson({'role': 'GUEST', 'status': 'WHAT', 'statuses': ['X']});
  check(parsedFilter.role == guest && parsedFilter.status == Status.OTHER &&
          parsedFilter.statuses![0] == Status.OTHER,
      'input fromJson with both');
  check(vars == UsersVariables(role: guest, filter: vars.filter),
      'variables equality with a custom type');

  // Through the client and the cache.
  final client = GraphQLClient(
    link: FakeLink(),
    cache: GraphQLCache(possibleTypes: possibleTypes),
  );
  final fetched =
      await client.query(usersQueryOptions(variables: vars));
  check(requests.last.variables['role'] == 'GUEST', 'variable on the wire');
  check(fetched.parsedData!.single.role == admin, 'typed result');
  final cached = client.readUsers(variables: vars)!.single;
  check(cached == user && cached.statusRaw == 'NEW', 'read from the cache');

  final changed = user.copyWith(role: guest, roles: [admin]);
  client.writeUsers([changed], variables: vars);
  final back = client.readUsers(variables: vars)!.single;
  check(back.role == guest && back.roles.single == admin, 'cache write + read');
  check(back.status == Status.OTHER && back.statusRaw == 'NEW',
      'the raw value survives the cache');

  client.writeUserBitsFragment({'id': '9'},
      const UserBitsData(typename: 'User', id: '9', role: guest, status: Status.ACTIVE));
  final fragment = client.readUserBitsFragment({'id': '9'})!;
  check(fragment.role == guest && fragment.status == Status.ACTIVE,
      'fragment cache round trip');

  // A root enum field with a fallback.
  check(parseCurrentStatusData({'status': 'NEW'}) == Status.OTHER,
      'root field fallback');
  client.writeCurrentStatus(Status.ACTIVE);
  check(client.readCurrentStatus() == Status.ACTIVE, 'root enum in the cache');
  print('ENUMS OK');
}
''';

// result_types: schema.
const _enumsSchemaMain = r'''
import 'package:fgc_compile_check/enums/app_role.dart';
import 'package:fgc_compile_check/enums_schema/Users.g.dart';
import 'package:fgc_compile_check/enums_schema/types.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

void main() {
  const admin = AppRole('admin');
  const guest = AppRole('guest');
  final user = parseUsersData({
    'users': [
      {
        '__typename': 'User',
        'id': '1',
        'role': 'ADMIN',
        'roles': ['ADMIN', 'GUEST'],
        'maybes': ['GUEST', null],
        'status': 'NEW',
        'statuses': ['NEW', null, 'ACTIVE'],
        'kind': 'C',
      },
    ],
  }).single;
  check(user.role == admin && user.roles[1] == guest, 'custom type');
  check(user.maybe == null && user.maybes![0] == guest && user.maybes![1] == null,
      'nullable custom type in a list');
  check(user.status == Status.OTHER && user.statusRaw == 'NEW', 'fallback');
  check(user.statuses![0] == Status.OTHER && user.statuses![1] == null &&
          user.statuses![2] == Status.ACTIVE,
      'fallback in a list');
  check(user.kind == Kind.$unknown, r'other enums keep $unknown');
  // $unknown can't be serialized here (schema result types).
  user.kind = null;
  final json = user.toJson();
  check(json['role'] == 'ADMIN' && json['roles'][1] == 'GUEST',
      'custom type serialized');

  final vars = UsersVariables(
    role: guest,
    filter: UserFilter(role: admin, roles: [guest], status: Status.OTHER),
  ).toJson();
  check(vars['role'] == 'GUEST', 'custom type in variables');
  final filter = vars['filter'] as Map<String, dynamic>;
  check(filter['role'] == 'ADMIN' && filter['roles'][0] == 'GUEST' &&
          filter['status'] == 'OTHER',
      'custom type in an input');
  check(UserFilter.fromJson({'status': 'X', 'roles': ['GUEST']}).status ==
          Status.OTHER,
      'input fallback');

  // Variables classes are the same as with operation result types.
  final explicit = UsersVariables.withNulls(role: null).toJson();
  check(explicit.containsKey('role') && explicit['role'] == null,
      'withNulls in schema mode');
  check(UsersVariables(role: guest).copyWith(role: null).toJson()
          .containsKey('role'),
      'copyWith in schema mode');
  print('ENUMS SCHEMA OK');
}
''';

void main() {
  test('explicit nulls and enums: generated code compiles and works', () async {
    final files = {
      ..._generate('nulls', _nullsSchema, _nullsDocuments),
      ..._generate('nulls_include', _nullsSchema, _nullsDocuments,
          includeNullInputs: true),
      ..._generate('nulls_legacy', _nullsSchema, _nullsDocuments,
          strict: false),
      ..._generate('nulls_schema', _nullsSchema, _nullsDocuments,
          resultTypes: 'schema'),
      'bin/nulls.dart': _nullsMain('nulls'),
      'bin/nulls_include.dart': _nullsMain('nulls_include', nulls: true),
      'bin/nulls_schema.dart': _nullsMain('nulls_schema', inputs: false),
      'lib/enums/app_role.dart': _roleLibrary,
      ..._generate('enums_ops', _enumsSchema, _enumsDocuments,
          unknownEnumFallback: true, enums: _enums),
      ..._generate('enums_legacy', _enumsSchema, _enumsDocuments,
          strict: false, unknownEnumFallback: true, enums: _enums),
      ..._generate('enums_schema', _enumsSchema, _enumsDocuments,
          resultTypes: 'schema', unknownEnumFallback: true, enums: _enums),
      'bin/enums.dart': _enumsMain,
      'bin/enums_schema.dart': _enumsSchemaMain,
    };

    final result = await compileGenerated(files, runScripts: [
      'bin/nulls.dart',
      'bin/nulls_include.dart',
      'bin/nulls_schema.dart',
      'bin/enums.dart',
      'bin/enums_schema.dart',
    ]);
    expect(result.errors, isEmpty, reason: result.log);
  });
}
