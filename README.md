# flutter_graphql_codegen

[![pub package](https://img.shields.io/pub/v/flutter_graphql_codegen.svg)](https://pub.dev/packages/flutter_graphql_codegen)
[![license](https://img.shields.io/github/license/ifmelate/flutter_graphql_codegen.svg)](https://github.com/ifmelate/flutter_graphql_codegen/blob/master/LICENSE)

A `build_runner` builder that reads your GraphQL schema and `.graphql` operation
files and writes Dart code for [`package:graphql`](https://pub.dev/packages/graphql):
a result class for every selection of every operation, fragment interfaces, input
and enum types from the schema, and an extension on `GraphQLClient` for each
operation. Optionally it also writes
[`graphql_flutter`](https://pub.dev/packages/graphql_flutter) widgets and hooks
per operation.

You write this:

```graphql
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
  }
}
```

and call it like this:

```dart
final user = await client.getUserData(GetUserVariables(id: '42').toJson());
print(user?.name);
```

`user` is a `GetUser_User` with exactly the fields the query selects.

Upgrading from 2.x or 3.0? See [MIGRATION.md](MIGRATION.md).

## Installation

```yaml
dependencies:
  graphql: ^5.1.3
  json_annotation: ^4.8.1

dev_dependencies:
  flutter_graphql_codegen: ^3.3.0
  build_runner: ^2.4.6
```

For the Flutter widgets and hooks (see
[Flutter widgets and hooks](#flutter-widgets-and-hooks)) add `graphql_flutter`,
and `flutter_hooks` if you write `HookWidget`s:

```yaml
dependencies:
  graphql: ^5.2.0                     # graphql_flutter 5.2 needs graphql 5.2
  graphql_flutter: ^5.2.0
  flutter_hooks: ">=0.18.2 <0.21.0"   # the range graphql_flutter 5.2 accepts
```

The generated code uses sealed classes and patterns, so your package needs Dart
language version 3.0 or newer (`environment: sdk: ^3.0.0` or higher in
`pubspec.yaml`). The generator itself runs on Dart 3.4+ (Flutter 3.22+).

`json_serializable` is only needed with `result_types: schema` (see
[Schema result types](#schema-result-types)).

## Configuration

Put a `graphql_codegen.yaml` next to your `pubspec.yaml`:

```yaml
schema_url: lib/graphql/schema.graphql
output_dir: lib/graphql/generated
document_paths:
  - lib/graphql/documents/**/*.graphql
strict_nullability: true
```

The builder looks for `graphql_codegen.yaml` by default. If you keep the file
somewhere else, point to it from `build.yaml`:

```yaml
targets:
  $default:
    builders:
      flutter_graphql_codegen|graphql_codegen:
        options:
          config_path: config/graphql_codegen.yaml
```

### Where the schema comes from

`schema_url` can be a path inside the project, an absolute path, a `file://`
URL, a `package:` URI of a file in `lib/` of a dependency (see
[Several packages](#several-packages)) or an HTTP(S) endpoint.

Local schema files are tracked by `build_runner`, so editing the schema triggers
regeneration.

For an HTTP(S) endpoint the builder tries a plain `GET` (expecting SDL), then
`GET ?sdl`, and finally a standard introspection query, which it converts to SDL.
Each request times out after 30 seconds. The remote schema is downloaded once per
`build_runner` run, so restart `watch` after the server's schema changes.

If the endpoint needs authentication, add headers. `${NAME}` is replaced with the
environment variable `NAME`, which keeps tokens out of the repository:

```yaml
schema_url: https://api.example.com/graphql
schema_headers:
  Authorization: "Bearer ${GRAPHQL_TOKEN}"
```

#### Keeping the schema in the repository

Downloading during every build makes builds depend on the network and on the
server's current schema. The alternative: keep the schema as a file in the
project and refresh it with a command when the server changes.

```yaml
schema_url: lib/graphql/schema.graphql             # the build reads this file
schema_endpoint: https://api.example.com/graphql   # fetch_schema downloads from here
schema_headers:
  Authorization: "Bearer ${GRAPHQL_TOKEN}"
```

```bash
dart run flutter_graphql_codegen:fetch_schema
```

It downloads the schema the same way the builder does (SDL, `?sdl`,
introspection) with `schema_headers`, and writes it to `schema_url`. Options:
`--config <file>`, `--endpoint <url>`, `--output <file>` and
`--header "Name: value"` (repeatable). It exits with 1 when the download fails
and 64 on wrong usage, so it works in scripts and CI.

### All options

| Option | Default | Description |
|--------|---------|-------------|
| `schema_url` (or `schema`) | required | Where to load the schema from |
| `document_paths` (or `documents`) | required | Globs for operation files; also used to find shared fragments |
| `output_dir` | `lib/graphql/generated` | Where generated files go |
| `result_types` | `operation` | `operation`: a class per selection, with only the selected fields. `schema`: one class per schema type, as in 2.x (see [Schema result types](#schema-result-types)) |
| `strict_nullability` | `false` | Follow `!` from the schema exactly (see below) |
| `file_naming` | `snake_case` | `snake_case`, `kebab-case`, `camelCase` or `PascalCase` |
| `emit_index` | `true` | Write an `index.dart` that exports everything |
| `scalar_mapping` | `{}` | Map a custom scalar to an existing Dart type, e.g. `Date: DateTime` |
| `schema_headers` | `{}` | HTTP headers for downloading a remote schema |
| `diagnostics_format` | `plain` | `plain` or `json` error output |
| `unknown_enum_fallback` | `false` | Add a `$unknown` value to every enum instead of throwing on values the server added later (see below) |
| `deprecated_annotations` | `false` | Turn schema `@deprecated` into Dart `@Deprecated` (see below) |
| `include_null_inputs` | `false` | Send a null input field or variable as `null` instead of leaving it out (see below) |
| `validate_documents` | `true` | Check operations against the schema before generating (see [Errors](#errors)) |
| `strict_scalars` | `false` | Fail when a custom scalar has no `scalar_mapping` entry (see [Custom scalars](#custom-scalars)) |
| `schema_endpoint` | none | Where `fetch_schema` downloads the schema from (see above) |
| `flutter_widgets` | `false` | Write a `graphql_flutter` widget per operation (see [Flutter widgets and hooks](#flutter-widgets-and-hooks)) |
| `flutter_hooks` | `false` | Write `graphql_flutter` hooks per operation (same section) |
| `enums` | `{}` | Per enum: map it to your own Dart type, or give it a fallback value (see [Enums](#enums)) |
| `group_operations` | `none` | `directory`: reach operations as `client.<directory>.<operation>()` (see [Grouping operations](#grouping-operations)) |
| `types_import` | none | `package:` URI of a `types.dart` generated by another package, used instead of writing one (see [Several packages](#several-packages)) |
| `fragment_imports` | `[]` | Fragments generated by other packages: list of `{dart, documents}` (same section) |
| `prune_types` | `false` | Declare in `types.dart` only the enums, input types and scalars your operations and fragments use (see [Smaller types.dart](#smaller-typesdart)) |
| `fragment_masking` | `false` | Keep a spread fragment's fields off the class that spreads it (see [Fragment masking](#fragment-masking)) |
| `persisted_documents` | `false` | Give every operation document an id and write a manifest for the server (see [Persisted documents](#persisted-documents)) |

A misspelled key is ignored with a warning that suggests the closest option.

About `strict_nullability`: with the default `false`, every field of a result
class is nullable (except `typename`), and so are lists and their elements.
Turn it on for new projects. It's off by default only so existing code keeps
compiling. The examples in this README assume it is on.

About `unknown_enum_fallback`: by default an enum value the generator doesn't
know (the server added it after you generated the code) throws while parsing.
That is risky for mobile apps, where old versions stay installed for a long
time. With the option on, every enum gets an extra `$unknown` value, and unknown
values parse to it, also inside lists. Each enum field of a result class (and of
a fragment interface) also gets a `<field>Raw` sibling with the string the
server sent: `user.role` is `Role.$unknown`, `user.roleRaw` is `'OWNER'`; lists
get `List<String?>?`. `toJson()` of a result class writes the raw string back,
so writing the object to the cache keeps the server's value. Sending `$unknown`
to the server in variables or an input throws `ArgumentError`, also inside a
list (with `result_types: schema`, not inside list fields of inputs). It's off
by default because the extra value makes your existing
exhaustive `switch` statements over enums incomplete. To give a single enum a
fallback among its own values instead, see [Enums](#enums).

About `include_null_inputs`: by default a null field of an input type, or a null
optional variable, is left out of the request. For a server that means "not
set". With the option on, every null is sent as `null`. A variable with a
default value (`$first: Int = 10`) is sent with its default when you don't give
it (or pass `null` to the constructor), with or without the option, because an explicit `null` would replace the
default. To send `null` for single fields without the option, see
[Variables and input types](#variables-and-input-types). The option matches
`includeIfNull` in Artemis, if you are moving from there.

About `deprecated_annotations`: descriptions from the schema always become doc
comments, and a `@deprecated` field or enum value gets a `Deprecated: <reason>`
line there. With the option on it also gets a real `@Deprecated` annotation, so
the IDE strikes it out. With `result_types: schema`, `types.g.dart` (written by
`json_serializable`) uses those members too, so `dart analyze` reports
`deprecated_member_use_from_same_package` there. Exclude generated files from
analysis in that case:

```yaml
# analysis_options.yaml
analyzer:
  exclude:
    - "**/*.g.dart"
```

## Running the generator

```bash
dart run build_runner build --delete-conflicting-outputs
```

One run writes everything. (With `result_types: schema` a fresh checkout needs
a second run, so that `json_serializable` can write `types.g.dart`.)

## What you get

`output_dir` ends up with:

- `types.dart`: enums, input types, scalar wrappers and converters, and a
  `possibleTypes` map, all from the schema
- `fragments.dart`: an interface, a data class and a document for every
  fragment in `document_paths`
- one `<operation>_graphql.g.dart` per named operation (a file with three
  operations produces three files), with its result classes (and its widgets
  and hooks, if you turn them on)
- with `group_operations: directory`, one `<group>_operations.dart` per
  documents directory
- `index.dart`, which exports all of the above

The files are formatted with `dart format` for your package's language version,
so a `dart format --set-exit-if-changed` check in CI passes without excluding
them.

For `query GetUser($id: ID!)`, the operation file contains:

```dart
final getUserDocument = graphql.gql(r"""...""");      // the query, with fragments
const String getUserOperationName = 'GetUser';

class GetUserVariables { ... Map<String, dynamic> toJson() }

class GetUser_User { ... }                            // the result classes
GetUser_User? parseGetUserData(Map<String, dynamic>? data);   // response -> result

// package:graphql options with typed variables and parsedData
QueryOptions<GetUser_User?> getUserQueryOptions(GetUserVariables variables, {fetchPolicy, ...});
WatchQueryOptions<GetUser_User?> getUserWatchQueryOptions(GetUserVariables variables, {...});

extension GetUserExtension on graphql.GraphQLClient {
  Future<QueryResult<Map<String, dynamic>>> getUser([Map<String, dynamic>? variables]);
  Future<GetUser_User?> getUserData([Map<String, dynamic>? variables]);
  GetUser_User? readGetUser(GetUserVariables variables);              // from the cache
  void writeGetUser(GetUserVariables variables, GetUser_User? data);  // into the cache
  bool evictGetUser(GetUserVariables variables);                      // drop from the cache
}
```

Mutations work the same way through `client.mutate`. Subscriptions return
streams:

```dart
client.userUpdatedData({'id': '42'}).listen((user) => print(user?.name));
```

### Result classes

Every selection set becomes a class with exactly the fields it selects. The
name is the operation name followed by the response keys on the way, each
starting with a capital letter:

```graphql
query GetUser($id: ID!) {
  user(id: $id) {        # GetUser_User
    id
    name
    email
    friends {            # GetUser_User_Friends
      id
      name
    }
  }
}
```

```dart
class GetUser_User {
  final String typename;                     // __typename
  final String id;
  final String name;
  final String? email;
  final List<GetUser_User_Friends> friends;
  ...
}
```

- A field you don't select isn't there, so `user { id }` parses fine even when
  `name` is non-null in the schema.
- Aliases are separate fields: `first: me { id } second: me { name }` gives
  `first` and `second`, each with its own class.
- A field selected more than once (directly, in inline fragments, in fragment
  spreads) is one field with the subfields merged.
- A field reached only through `@skip` or `@include` is nullable, since the
  server may leave it out.
- Every class except the operation's root has `typename`, the object's
  `__typename`. The builder adds `__typename` to every selection in the
  generated documents, so you don't have to.

If an operation selects one root field, `parse<Op>Data` and `<op>Data()` return
that field's type (`GetUser_User?` above). With more than one, they return an
`<Op>Result` with one property per field (named after the alias if there is
one):

```dart
// query Dashboard { me { id name } notifications }
final dashboard = await client.dashboardData();   // DashboardResult
print(dashboard.me.name);                         // Dashboard_Me
print(dashboard.notifications.length);            // List<String>
```

Each class has a `const` constructor, `final` fields, `fromJson`, `toJson` (in
the shape of the response, `__typename` included), `==` and `hashCode` that
compare lists and maps by their elements, and a typed `copyWith`:

```dart
final renamed = user.copyWith(name: 'Ann');
final noEmail = user.copyWith(email: null);   // null clears a nullable field
print(renamed == user);                       // false
print(GetUser_User.fromJson(user.toJson()) == user);   // true
```

### Interfaces and unions

A selection on an interface or union becomes a sealed class. Each type the
selection has its own fields for gets a subclass `<Base>_On<Type>`, and
`<Base>_Other` stands for every other type, including types the server adds
after you generated the code. `fromJson` picks the subclass by `__typename`.

```graphql
query Search($q: String!) {
  search(q: $q) {                      # Search_Search (union SearchResult)
    ... on User { id name }            # Search_Search_OnUser
    ... on Post { id title }           # Search_Search_OnPost
  }                                    # Search_Search_Other: anything else
}
```

A `switch` over it is exhaustive without a `default`:

```dart
final results = await client.searchData(SearchVariables(q: 'dart').toJson());
for (final result in results) {
  final text = switch (result) {
    Search_Search_OnUser(:final name) => 'user $name',
    Search_Search_OnPost(:final title) => 'post $title',
    Search_Search_Other(:final typename) => 'something new: $typename',
  };
  print(text);
}
```

Fields selected for every type (`id` on `node(id:) { id ... on User { name } }`)
are getters of the sealed class, so you can read them without a `switch`.

Pass `possibleTypes` to the cache, so fragments on interfaces and unions are
matched correctly when results are read back from it:

```dart
final client = GraphQLClient(
  link: link,
  cache: GraphQLCache(possibleTypes: possibleTypes),
);
```

### Fragments

Each fragment becomes an `abstract interface class` with its fields. Every
result class whose selection spreads the fragment implements it, so one
function can take objects from different operations:

```graphql
fragment UserCard on User { id name }

query GetUser($id: ID!) { user(id: $id) { ...UserCard email } }
query Dashboard { me { ...UserCard role } notifications }
```

```dart
String userLabel(UserCard user) => '${user.name} (#${user.id})';

final user = await client.getUserData(GetUserVariables(id: '42').toJson());
final dashboard = await client.dashboardData();
print(userLabel(user!));          // GetUser_User implements UserCard
print(userLabel(dashboard.me));   // Dashboard_Me implements UserCard
```

- Nested selections of a fragment get their own interfaces
  (`fragment WithFriends on User { friends { id } }` gives
  `WithFriends_Friends`), and the nested classes of the operation implement
  them.
- A fragment on an interface or union also gets `<Fragment>_On<Type>`
  interfaces for its type-specific parts.
- A spread under `@skip`/`@include` doesn't make the class implement the
  fragment, because its fields may be missing.

`fragments.dart` also has, for every fragment:

- `<Fragment>Data`, a class with the fragment's fields (for example to build
  one by hand or read it from the cache);
- `<fragment>Fragment`, the fragment's document (with the fragments it uses),
  and `<fragment>FragmentName`.

Fragments can live in their own files, as long as those files match
`document_paths`. Each operation document includes only the fragments it uses.
Fragment names must be unique across all documents.

### Fragment masking

By default a class gets the fields of every fragment it spreads. A screen
that spreads `...UserCard` for a child widget can then read `avatarUrl`
itself, and removing `avatarUrl` from the fragment breaks the screen, not
just the widget. With `fragment_masking: true` the class only has the fields
its own selection names, plus one member per spread fragment holding that
fragment's data:

```graphql
fragment UserCard on User { name avatarUrl }

query Profile { me { id ...UserCard } }
```

```dart
class UserCardView extends StatelessWidget {
  const UserCardView(this.user, {super.key});
  final UserCard user;
  // ...
}

final me = await client.profileData();
me.id;                    // selected by the query
UserCardView(me.userCard); // the fragment's data, typed as UserCard
// me.avatarUrl does not exist: only the fragment selects it
```

- The member is named after the fragment (`UserCard` gives `userCard`) and
  typed by its interface, or by its `<Fragment>_On<Type>` interface when the
  class is of that type. It is parsed from the same JSON object, so the
  response is unchanged; `toJson()` merges the fragment's fields back in, so
  writing the class to the cache stores everything.
- Fragments mask the fragments they spread too (`UserCardData.avatarBits`).
- A spread under `@skip`/`@include` is not masked: whether it was included
  can't be told from the response. Its fields stay on the class, nullable.
- Fragments from `fragment_imports` are not masked; generate the package
  declaring them without `fragment_masking`.
- Inline fragments (`... on User { name }`) are never masked.

### Relay connections: `nodes`

A class whose selection has `edges { node { ... } }` gets a `nodes` getter with
the nodes of all edges, leaving out null edges and null nodes:

```graphql
query Users($first: Int = 20, $after: String) {
  users(first: $first, after: $after) {
    edges { node { id name } }
    pageInfo { hasNextPage endCursor }
  }
}
```

```dart
final page = await client.usersData();
for (final user in page.nodes) {             // List<Users_Users_Edges_Node>
  print(user.name);
}
// instead of page.edges?.map((e) => e?.node).whereType<...>()
```

- `edges` and `node` are matched by response key, so an alias
  (`items: edges`) means no getter. `node` must be an object, interface or
  union; for an abstract type the list holds the sealed class.
- It's a getter, not a field: it isn't in the constructor, `toJson`, `==` or
  `copyWith`.
- A class that selects a field named `nodes` itself (or uses `nodes` as an
  alias) keeps that field and gets no getter.
- It is available on result classes and fragment data classes
  (`<Fragment>Data`); it is not part of fragment interfaces.
- With `result_types: schema` there is no getter.

### Cache

For queries, `read<Op>` returns the cached result, typed, or null when it isn't
cached. `write<Op>` takes the same type and puts it into the cache, as if the
server had returned it:

```dart
const vars = GetUserVariables(id: '42');
final cached = client.readGetUser(vars);              // GetUser_User?
if (cached != null) {
  client.writeGetUser(vars, cached.copyWith(name: 'Ann'));
}
```

`evict<Op>` removes the query's cached root fields for those variables, so the
next `cacheFirst` read goes to the network (after a mutation that made the
result stale, for example). It returns whether anything was removed. Other
variables of the same query and the objects the result pointed to stay cached.
Active `watchQuery` results aren't notified; call `refetch()` on them if you
need fresh data right away.

**Select `id` on entities.** The normalized cache of `package:graphql` stores
objects by `__typename` and `id`. If one query selects `user { id name }` and
another selects `user { name }` without `id`, the cache can fail to read the
second back once the first has stored that user under its `id`, and the query
fails with `CacheMissException`. Select `id` on every object that has one, in
every operation and fragment that reads it. `__typename` is added for you;
`id` is not.

Fragments can be read and written for a single object.
`read<Fragment>Fragment` returns a `<Fragment>Data` (null when the object isn't
cached), and `write<Fragment>Fragment` takes any object that implements the
fragment interface:

```dart
final card = client.readUserCardFragment({'id': '42'});   // UserCardData?
client.writeUserCardFragment({'id': '42'}, dashboard.me);
```

The first argument identifies the object (usually its `id`). For a fragment on
an object type, `__typename` is added for you; for a fragment on an interface or
union, pass it when reading (`{'__typename': 'User', 'id': '42'}`); when
writing it comes from the data. Both take `variables:` for fragments with
arguments, plus `optimistic:` (read) or `broadcast:` (write).

### Options for `query`, `watchQuery`, `mutate` and `subscribe`

The extension methods cover the common case. For `watchQuery`, a fetch or
error policy, polling, optimistic results or a mutation `update` callback, use
the generated options functions. They take typed variables, and their
`parserFn` is the generated parser, so `parsedData` is typed:

```dart
final result = await client.query(getUserQueryOptions(
  const GetUserVariables(id: '42'),
  fetchPolicy: FetchPolicy.networkOnly,
));
final GetUser_User? user = result.parsedData;

final ObservableQuery<GetUser_User?> query = client.watchQuery(
  getUserWatchQueryOptions(const GetUserVariables(id: '42'),
      fetchPolicy: FetchPolicy.cacheAndNetwork),
);
query.stream.listen((result) => print(result.parsedData?.name));
```

There are `<operation>QueryOptions` and `<operation>WatchQueryOptions` for
queries, `<operation>MutationOptions` for mutations and
`<operation>SubscriptionOptions` for subscriptions. Operations without
variables take no variables argument; operations whose variables are all
optional take `variables:` as a named argument. Unlike the extension methods,
`client.query(...)` doesn't throw on errors: check `result.hasException`.

`<operation>QueryOptions` also takes `onComplete` and `onError`. `package:graphql`
itself doesn't call them; `graphql_flutter`'s `Query` widget and `useQuery` hook
do (and so the generated query widget and `use<Op>Query` hook). `onComplete`
gets the raw `data` map, not the parsed result.

### Variables and input types

`GetUserVariables` turns typed values into the map that `package:graphql` expects.
Enums are sent by their schema name, `DateTime` as ISO-8601 in UTC, and input
types through their `toJson()`. Optional variables you leave out are left out of
the map entirely, except those with a default value in the operation
(`$first: Int = 20`), which are sent with that default.

Input types from the schema are immutable classes in `types.dart`, with a
`const` constructor, `fromJson`/`toJson`, `==`/`hashCode` and a typed
`copyWith`. Non-null list fields default to an empty list, nullable ones to
`null`.

#### Leaving a field out vs. sending `null`

For a server, a field that isn't in the request means "don't change it", and
`null` means "clear it". The plain constructor leaves null fields out; the
`withNulls` constructor and `copyWith` send an explicit `null`:

```graphql
input UserPatch { name: String email: String tags: [String!] }
mutation UpdateUser($id: ID!, $patch: UserPatch!) { ... }
```

```dart
const UserPatch(name: 'Ann', email: null).toJson();
// {name: Ann}                      email is left out: unchanged on the server

const UserPatch.withNulls(name: 'Ann', email: null).toJson();
// {name: Ann, email: null}         email is cleared; tags is still left out

const UserPatch(name: 'Ann').copyWith(email: null).toJson();
// {name: Ann, email: null}         same as withNulls
```

- `withNulls` is a `const` factory with the same parameters as the
  constructor, on every input with nullable fields. A parameter you pass as
  `null` is sent as `null`; one you don't pass is left out.
- `copyWith(x: null)` sends `null` for `x`; `copyWith(x: value)` sets it again.
  Other fields keep what they had, including an explicit `null`.
- `fromJson` keeps the difference: a key holding `null` becomes an explicit
  `null`, a missing key stays absent, so `X.fromJson(x.toJson()) == x`.
- `==` and `hashCode` tell the two apart:
  `UserPatch(name: 'Ann') != UserPatch.withNulls(name: 'Ann', email: null)`.
- With `include_null_inputs: true` every null is sent anyway, so there is
  nothing to tell apart.
- This is for input classes in operation mode. With `result_types: schema`,
  input classes are the mutable `json_serializable` classes of 2.x.

Variables classes work the same way, in both result modes:

```dart
const vars = UsersVariables(after: 'abc');
vars.toJson();                                  // {first: 20, after: abc}
UsersVariables.withNulls(first: null).toJson(); // {first: null}
vars.copyWith(after: null).toJson();            // {first: 20, after: null}
vars == const UsersVariables(after: 'abc');     // true
```

They have `==`/`hashCode` (deep for lists and inputs), a typed `copyWith` and,
when some variable is nullable, `withNulls`. A variable with a default is sent
with the default when you don't give it or pass `null` to the plain
constructor; `withNulls(first: null)` or `copyWith(first: null)` sends `null`,
which replaces the default on the server.

### Names that aren't valid Dart

A field called `class` or an enum value called `default` gets a trailing
underscore in Dart (`class_`, `Role.default_`), and so does a field named like a
type (`int`, `String`, `Media: Media` -> `int_`, `String_`, `Media_`). Leading
underscores would make a name private, so they move to the end: `_id` becomes
`id_`. JSON keys and values sent to the server keep the original GraphQL names.

Result classes have `typename` and `copyWith` members, so selected fields with
those names become `typename_` and `copyWith_`. When two result classes of an
operation would get the same name, the second gets a number (`A_User_2`). A
fragment named like a declaration in `types.dart` (an enum, an input type) gets
a trailing underscore (`fragment Role` -> `Role_`).

Client methods of an operation named like a `GraphQLClient` member get one too:
`query Query` gives `client.query_()`, `client.readQuery_()` and
`client.writeQuery_()` (and `client.queryData()`, which doesn't clash).

The same goes for schema types named like something the generated code relies
on: `dart:core` types (`Map`, `String`, `Object`, `Future`, `Set`, ...),
`json_annotation` classes (`JsonKey`, ...) and the built-in helpers (`Decimal`,
`Long`, `Byte` when they are object types rather than scalars). `input Map`
becomes `class Map_`, `scalar Object` becomes `Object_`. `__typename` and
`possibleTypes` keep the GraphQL names.

### Schema result types

`result_types: schema` generates the 2.x API instead: one class per object
type, interface and union in `types.dart` (using `json_serializable`, which then
has to be in your dev dependencies), `Unknown<Name>` fallbacks for interfaces
and unions, and `write<Op>` taking the raw response map. Those classes have all
fields of the schema type, so a query that leaves out a non-null field fails to
parse. Use it to upgrade from 2.x without changing your code; see
[MIGRATION.md](MIGRATION.md).

### Smaller types.dart

By default `types.dart` declares every enum, input type and custom scalar of
the schema. For a large public schema that's a lot: GitLab's (4,580 types)
gives 134,016 lines. With `prune_types: true` it declares only what the
operations and fragments in `document_paths` use:

```yaml
prune_types: true
```

- Kept: enums and custom scalars of selected fields (fragments included);
  the types of variables, with every input type, enum and scalar their
  fields reach; interfaces and unions in `possibleTypes` that are selected
  or used as a type condition. For GitLab's schema and the two queries in
  `tool/live_check/gitlab`, that's 421 lines.
- Every document then affects `types.dart`: adding an operation that uses a
  new enum or input type adds it.
- A type no operation uses isn't declared, so code of yours that uses it
  directly (an enum in a widget, say) stops compiling. Select it in some
  operation, or leave the option off.
- It applies to `result_types: operation` only. Don't turn it on in a package
  whose `types.dart` other packages use through `types_import`: it only knows
  its own operations.

## Persisted documents

A server can refuse every document it hasn't been given in advance, so a
copied token can't run arbitrary queries, and the app sends a short id
instead of the whole document. With `persisted_documents`, the generator
gives every operation document an id (its hash) and writes a manifest of
them for the server:

```yaml
persisted_documents: true
# or
persisted_documents:
  algorithm: sha256   # sha256 (default), sha1 or md5
  manifest: lib/graphql/generated/persisted_documents.json  # the default
  directory: persisted_operations  # optional: one <id>.graphql per document
```

- The manifest maps each id to its document: `{"<id>": "query GetUser ..."}`.
  The document is the text the client sends (with the `__typename` fields
  `package:graphql` adds), so the id is the hash of what the server runs.
- `directory` gets one `<id>.graphql` file per document, the layout of Hot
  Chocolate's file system storage (`AddFileSystemOperationDocumentStorage`).
  Files of documents that are gone are deleted. It must not be matched by
  `document_paths`.
- Each operation file gets `<operation>DocumentId`, and
  `persisted_documents.dart` (exported by `index.dart`) has all ids by
  operation name plus `PersistedDocumentsSerializer`.

Send ids instead of documents by giving the serializer to `HttpLink`:

```dart
final link = HttpLink(
  'https://api.example.com/graphql',
  serializer: const PersistedDocumentsSerializer(),
);
```

`format:` says where the id goes:

| `format` | Request | Servers |
|----------|---------|---------|
| `PersistedDocumentFormat.apollo` (default) | `extensions.persistedQuery.sha256Hash` | Apollo Router, GraphQL Hive, graphql-java, Hot Chocolate with a SHA-256 hash provider |
| `PersistedDocumentFormat.documentId` | top-level `documentId` | GraphQL Hive, servers following the GraphQL over HTTP proposal |
| `PersistedDocumentFormat.id` | top-level `id` | Hot Chocolate, with any hash provider |

- `sendDocument: true` sends the document as well, for servers that register
  documents on first use (automatic persisted queries). A server that only
  runs persisted documents may refuse such requests: Hot Chocolate does.
- Operations without an id (documents you build by hand) are sent as usual.
- `WebSocketLink` takes a `serializer` in its `SocketClientConfig` too, if your
  server accepts ids for subscriptions.

With Hot Chocolate (checked on 15.0.3), put the ids in `directory:` and point
its file system storage there:

```csharp
builder.Services.AddSha256DocumentHashProvider(HashFormat.Hex);
builder.Services
    .AddGraphQLServer()
    // ...
    .AddFileSystemOperationDocumentStorage("./persisted_operations")
    .UsePersistedOperationPipeline()
    .ModifyRequestOptions(o =>
        o.PersistedOperations.OnlyAllowPersistedDocuments = true);
```

The `id` format works with any hash provider, since the server looks the id
up as a file name. The default `apollo` format needs the SHA-256 provider in
hex, as above: Hot Chocolate reads `extensions.persistedQuery` only then. It
doesn't read `documentId`.

## Custom scalars

| GraphQL | Dart |
|---------|------|
| `DateTime` | `DateTime`, written back as UTC ISO-8601 |
| `LocalDate` | `DateTime`, written back as `yyyy-MM-dd` |
| `Decimal`, `Long` | small wrapper classes that keep the value as a string |
| `Byte`, `Short` | `Byte` wrapper / `int` |
| anything else | a generated wrapper class with `raw` (the JSON value as received) and `value` (its string form) |

To use your own type instead, add it to `scalar_mapping`. The short form works
for types that are always in scope (`String`, `int`, `DateTime`,
`Map<String, dynamic>`, ...):

```yaml
scalar_mapping:
  Date: DateTime
  JSON: Map<String, dynamic>
```

For a type from another library, use the long form with `import`. The import
is added to `types.dart`, `fragments.dart` and the operation files:

```yaml
scalar_mapping:
  Decimal:
    type: Decimal
    import: package:decimal/decimal.dart
  Money:
    type: Money
    import: package:my_app/money.dart
    converter: MoneyConverter
```

Without `converter`, the type needs `fromJson` and `toJson`, like `Decimal` from
`package:decimal`. With `converter`, give the name of a `JsonConverter` class
with a `const` constructor, exported by the same `import`. It's used for fields,
list elements, variables and results. Give it a non-nullable JSON type
(`JsonConverter<Money, int>`, not `<Money, Object?>`), so null values are
handled for you instead of being passed to `fromJson`.

With `strict_scalars: true`, a custom scalar that isn't mapped (and isn't one of
the built-in ones above) fails the build with `SCH401`, instead of silently
becoming a wrapper class.

Non-nullable `int`, `double` and `bool` fields have lenient converters: a missing
or malformed value becomes `0`, `0.0` or `false` instead of throwing.

## Enums

Every GraphQL enum becomes a Dart enum in `types.dart`. The `enums` option
changes that for single enums:

```yaml
enums:
  Role:                      # use your own Dart type
    type: AppRole
    import: package:my_app/role.dart
    from_json: roleFromJson
    to_json: roleToJson
  Status:                    # decode unknown values as one of its values
    fallback: OTHER
```

### Your own type

With `type`, no Dart enum is generated. Result fields, list elements, input
fields and variables of that enum use your type, converted by two top-level
functions that `import` exports: `from_json` (`AppRole Function(String)`) and
`to_json` (`String Function(AppRole)`).

```dart
// lib/role.dart
class AppRole {
  const AppRole(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is AppRole && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

AppRole roleFromJson(String json) => AppRole(json.toLowerCase());
String roleToJson(AppRole role) => role.name.toUpperCase();
```

```dart
final user = await client.getUserData(const GetUserVariables(id: '42').toJson());
final AppRole role = user!.role;
```

The import is added to `types.dart`, `fragments.dart` and the operation files.
Give your type `==` and `hashCode`, since result classes compare their fields
with `==`. What an unknown value becomes is up to `from_json`, so the enum gets
no `$unknown` and no `<field>Raw` sibling, also with `unknown_enum_fallback`.

### Fallback value

With `fallback`, a value the generated code doesn't know decodes as that value
(also in lists) instead of throwing. For that enum it replaces
`unknown_enum_fallback`: there is no `$unknown`, so `switch` statements over it
stay as they are. Enum fields get a `<field>Raw` sibling with the string the
server sent, and `toJson()` writes it back while the field still holds the
decoded value, so the cache keeps what the server sent:

```dart
// the server sent status: "SUSPENDED", added after you generated the code
print(user.status);      // Status.OTHER
print(user.statusRaw);   // SUSPENDED
```

### Checks

Problems in the option fail the build with `CFG999`, all listed together: an
entry that isn't an enum of the schema (the message lists the enums), a
`fallback` that isn't one of the enum's values, `type` without both
`from_json` and `to_json`, `import`/`from_json`/`to_json` without `type`, and
`type` together with `fallback`. Unknown keys in an entry are ignored with a
warning. Custom types and fallbacks work with `result_types: schema` too.

## Flutter widgets and hooks

With `flutter_widgets: true` and/or `flutter_hooks: true`, every operation file
also gets [`graphql_flutter`](https://pub.dev/packages/graphql_flutter)
widgets or hooks built on the typed options functions, so `result.parsedData`
is typed and variables are the generated variables class:

```yaml
flutter_widgets: true
flutter_hooks: true
```

| Operation | `flutter_widgets` | `flutter_hooks` |
|-----------|-------------------|-----------------|
| query `GetUser` | `GetUserQuery` | `useGetUserQuery`, `useGetUserWatchQuery` |
| mutation `UpdateUser` | `UpdateUserMutation`, `RunUpdateUserMutation` | `useUpdateUserMutation`, `RunUpdateUserMutation` |
| subscription `UserUpdated` | `UserUpdatedSubscription` | `useUserUpdatedSubscription` |

A trailing operation kind isn't repeated: operation `GetUserQuery` gets the
widget `GetUserQuery` and the hook `useGetUserQuery`. The generated files
import `package:flutter/widgets.dart` and `graphql_flutter` (with prefixes), so
turn the options on only in Flutter packages that depend on `graphql_flutter`
(see [Installation](#installation)). Both options work with
`result_types: schema` too.

### Widgets

```dart
GetUserQuery(
  variables: const GetUserVariables(id: '42'),
  fetchPolicy: FetchPolicy.cacheAndNetwork,
  builder: (result, {refetch, fetchMore}) {
    if (result.hasException) return Text('${result.exception}');
    final GetUser_User? user = result.parsedData;
    return Text(user?.name ?? 'loading');
  },
)

UpdateUserMutation(
  onCompleted: (data) => print('saved'),
  builder: (runMutation, result) => TextButton(
    onPressed: () => runMutation(const UpdateUserVariables(
        id: '42', patch: UserPatch(name: 'Ann'))),
    child: Text(result?.parsedData?.name ?? 'Save'),
  ),
)

UserUpdatedSubscription(
  variables: const UserUpdatedVariables(id: '42'),
  onSubscriptionResult: (result, client) => print(result.parsedData?.name),
  builder: (result) => Text(result.parsedData?.name ?? 'waiting'),
)
```

- Widgets take `variables:` (required when the operation has required
  variables, left out when it has none), the parameters of the operation's
  options function (`fetchPolicy`, `errorPolicy`, `pollInterval`, `onComplete`,
  `onError`, ...; `update`, `onCompleted`, `onError` for mutations), `client:`
  and `builder:`.
- Without `client:` they run on the client of the nearest `GraphQLProvider`;
  with it, on that client (through `QueryOnClient`, `MutationOnClient`,
  `SubscriptionOnClient`).
- A mutation gets its variables per run: `runMutation` is a
  `Run<Op>Mutation` taking the variables class (and `optimisticResult:`) and
  returning `MultiSourceResult`.

### Hooks

The hooks are `graphql_flutter`'s `useQuery`, `useWatchQuery`, `useMutation`
and `useSubscription` with the typed options, so call them in a `HookWidget`
or `HookBuilder` from `flutter_hooks`:

```dart
class UserName extends HookWidget {
  const UserName({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final query = useGetUserQuery(GetUserVariables(id: id));
    final GetUser_User? user = query.result.parsedData;
    final update = useUpdateUserMutation();
    return TextButton(
      onPressed: () => update.runMutation(
          UpdateUserVariables(id: id, patch: const UserPatch(name: 'Ann'))),
      child: Text(user?.name ?? 'loading'),
    );
  }
}
```

- `use<Op>Query` returns `graphql_flutter`'s `QueryHookResult` (`result`,
  `refetch`, `fetchMore`). `use<Op>WatchQuery` returns the `ObservableQuery`;
  pass `fetchResults: true` (or call `fetchResults()`) to run it.
- `use<Op>Mutation` returns a record `(runMutation: Run<Op>Mutation, result:
  QueryResult)`. `use<Op>Subscription` returns the latest `QueryResult` and
  takes `onSubscriptionResult:`.
- Hooks have no `client` parameter: they use the nearest `GraphQLProvider`. To
  run on another client, pass the typed options to `graphql_flutter`'s
  `*OnClient` hooks: `useQueryOnClient(client, getUserQueryOptions(vars))`.

A widget or `Run<Op>Mutation` named like a type in `types.dart` fails with
`BLD108`; rename the operation.

### Testing widgets with subscriptions

`graphql_flutter`'s subscriptions listen for connectivity changes through
`connectivity_plus`, which has no platform side in `flutter test`. Mock its
channel in widget tests that pump a subscription widget or hook:

```dart
setUp(() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(onListen: (arguments, events) {}),
  );
});
```

## Grouping operations

In a large project the client extension gets long. With
`group_operations: directory` the operations of each documents directory are
also reachable through a getter named after it:

```yaml
document_paths:
  - lib/graphql/documents/**/*.graphql
group_operations: directory
```

```text
lib/graphql/documents/
  users/get_user.graphql         query GetUser       client.users.getUser(...)
  users/admin/ban_user.graphql   mutation BanUser    client.usersAdmin.banUser(...)
  version.graphql                query Version       client.version(...) (not grouped)
```

```dart
final user = await client.users.getUserData(
    const GetUserVariables(id: '42').toJson());
final cached = client.users.readGetUser(const GetUserVariables(id: '42'));
await client.getUserData(const GetUserVariables(id: '42').toJson()); // still works
```

- The root is the longest directory that the literal parts of all
  `document_paths` patterns share (`lib/graphql/documents` above). Documents
  directly in the root aren't grouped.
- The group name joins the directories below the root in camelCase:
  `users/admin` -> `usersAdmin`, `user-profiles` -> `userProfiles`. Words in
  capitals are lowercased (`API/keys` -> `apiKeys`), and a name starting with
  a digit gets a `group` prefix (`2fa` -> `group2fa`).
- Each group gets a class (`UsersOperations`) in its own file
  (`users_operations.dart`, following `file_naming`), with the getter on
  `GraphQLClient`. `index.dart` exports the group files. Operation files add
  their methods to the class with an extension (`GetUserInGroup`).
- Group methods have the same names and parameters as the client methods
  (`getUser`, `getUserData`, `readGetUser`, `writeGetUser`, `evictGetUser`)
  and call them. An operation named `Client` gets `client_()` in its group,
  since the class has a `client` field.
- A getter that would be a Dart keyword, a `GraphQLClient` member or an
  operation's client method gets a trailing underscore: directory `class/`
  gives `client.class_`, `query/` gives `client.query_`, and `users/` next to
  an operation `Users` gives `client.users_`.
- Two directories with the same group name (`user-admin/` and `user_admin/`),
  or a group class named like a declaration in `types.dart`, `fragments.dart`
  or an operation file, fail with `BLD108`.
- Group files of directories that no longer have operations are deleted.
  Grouping works with both result modes.

## Several packages

In a repository with several packages, the schema, its types and common
fragments can live in one shared package, and each feature package generates
only its own operations on top of them:

```text
packages/
  shared/     schema.graphql, common fragments; its own types.dart and fragments.dart
  feature/    depends on shared; its operations use shared's types and fragments
```

The shared package is configured as usual:

```yaml
# shared/graphql_codegen.yaml
schema_url: lib/graphql/schema.graphql
document_paths: [lib/graphql/**.graphql]
output_dir: lib/graphql/generated
strict_nullability: true
```

The feature package points to it:

```yaml
# feature/graphql_codegen.yaml
schema_url: package:shared/graphql/schema.graphql
document_paths: [lib/graphql/**.graphql]
output_dir: lib/graphql/generated
strict_nullability: true
types_import: package:shared/graphql/generated/types.dart
fragment_imports:
  - dart: package:shared/graphql/generated/fragments.dart
    documents: "package:shared/graphql/**.graphql"
```

```graphql
# shared/lib/graphql/fragments.graphql
fragment UserBits on User { id name role }

# feature/lib/graphql/users.graphql
query FeatureUsers($filter: UserFilter) { users(filter: $filter) { ...UserBits } }
```

```dart
import 'package:feature/graphql/generated/index.dart';

String label(UserBits user) => '${user.name} (${user.role.name})';

final users = await client.featureUsersData(
    const FeatureUsersVariables(filter: UserFilter(role: Role.ADMIN)).toJson());
users.map(label);   // FeatureUsers_Users implements the shared UserBits
```

- `schema_url: package:<name>/<path>` reads the schema from `lib/<path>` of a
  dependency, through `build_runner`, so changing it triggers a rebuild.
  `SCH404` when it isn't there.
- `types_import` is the `package:` URI of the shared `types.dart`. No
  `types.dart` is written in the feature package (one it generated before is
  deleted; a file of yours is kept); the generated files import the shared one
  and `index.dart` exports it. Inputs, enums and scalars are then the same
  classes in both packages.
- `fragment_imports` lists fragments generated by other packages: `dart` is
  the `package:` URI of that package's `fragments.dart`, `documents` a
  `package:` URI or glob of the `.graphql` files defining them. The feature's
  operations and fragments can spread them, and their classes implement the
  shared interfaces. The feature's own `fragments.dart` declares only its own
  fragments, the operation documents carry the shared definitions, and
  `index.dart` exports the shared `fragments.dart`.
- An app can import the `index.dart` of both packages; the shared libraries
  are exported by both without conflicts.
- Build the shared package first, then the feature package
  (`dart run build_runner build` in each). If the shared `fragments.dart` isn't
  generated yet, or lacks a fragment its documents define, the feature build
  warns and asks you to generate it.
- Use the same type-related options in both packages: `strict_nullability`,
  `scalar_mapping`, `enums`, `unknown_enum_fallback`, `include_null_inputs`,
  `deprecated_annotations` and `result_types`. The feature's generated code
  assumes the shared `types.dart` was generated with its own settings.
- With `result_types: schema`, `types_import` works the same way;
  `fragment_imports` only adds the shared fragment definitions to the
  documents (there are no fragment interfaces in that mode).
- `build_runner` can't list another package's files, so the `documents` glob
  is matched on disk. A fragment file added to the shared package is picked up
  the next time a document of the feature package is rebuilt.

Problems: a `types_import` or `dart` that isn't `package:<name>/<path>.dart`,
a `documents` that isn't a `package:` URI, or a package that isn't a
dependency fail with `CFG999`. A local fragment named like an imported one, or
a fragment imported from two libraries, fails with `BLD102`. An operation or
fragment that would declare a top-level name the imported library declares as
well (operation `UserBitsFragment` next to the shared fragment `UserBits`)
fails with `BLD108`.

## Errors

Both `getUser(...)` and `getUserData(...)` throw `OperationException` when the
response has GraphQL errors or the request failed, so you get the original
error details:

```dart
try {
  final user = await client.getUserData({'id': '42'});
} on OperationException catch (e) {
  print(e.graphqlErrors);
  print(e.linkException);
}
```

Problems found during generation are reported with a code:

| Code | Meaning |
|------|---------|
| `CFG001` / `CFG002` | `schema_url` / `document_paths` missing from the config |
| `CFG999` | Other config problem: a bad value, an unset env variable in `schema_headers`, an `enums` entry that doesn't fit the schema (see [Enums](#enums)), a malformed `types_import` or `fragment_imports` URI, or a `fragment_imports` package that isn't a dependency |
| `SCH400` | The schema doesn't parse |
| `SCH401` | A custom scalar has no `scalar_mapping` entry and `strict_scalars` is on |
| `SCH402` | The schema has types the spec doesn't allow: an object, interface or input type without fields, a union without members, an enum without values, an interface implemented twice |
| `SCH404` | Schema file not found (also a `package:` `schema_url` outside `lib/` of a dependency) |
| `SCH500` | Remote schema download failed; the message lists every attempt |
| `BLD100` | An operation file doesn't parse |
| `BLD101` | An operation uses a fragment that isn't defined anywhere |
| `BLD102` | Two fragments share a name but differ, two fragments would generate a class with the same name, or a fragment clashes with one from `fragment_imports` |
| `BLD103` | An operation selects a field the schema doesn't have (at any depth), or a plain field on a union |
| `BLD104` | Two operations have the same name (or names that map to the same file) |
| `BLD105` | Unknown argument, or a required argument is missing |
| `BLD106` | A variable is used but not declared, declared but never used, or has an unknown or non-input type |
| `BLD107` | A selection set is missing (object field) or not allowed (scalar field), a fragment is on an unknown or non-composite type, a fragment spreads itself, or an alias starts with `__` |
| `BLD108` | Two operations, or an operation and `fragments.dart`, would declare the same top-level name (e.g. `A_B_C` from operations `A_B` and `A`); also a Flutter widget or `Run<Op>Mutation` named like a type in `types.dart`, two documents directories that become the same operation group, a group class clashing with another declaration, and a name clashing with a `fragment_imports` library |
| `BLD200` | Writing `index.dart` failed |

`BLD103` and `BLD105`–`BLD107` come from checking each operation against the
schema. All problems of an operation are reported together, with the path and
line of each one. These are documents a GraphQL server would reject anyway. If a
check gets in the way while you fix an existing project, turn it off with
`validate_documents: false`.

## Known limitations

- Anonymous operations are skipped, with a warning. Give every operation a name.
- If you rename an operation, the old generated file stays in `output_dir`.
  Delete it by hand.
- `result_types` applies to the whole build; you can't mix the two modes.
- With `unknown_enum_fallback`, a query whose single root field is an enum
  (`query { status }`) can't be written to the cache while that field is
  `$unknown`: `write<Op>` throws `ArgumentError`, because there is no object to
  keep the raw value in.
- By default `types.dart` has every enum, input type and custom scalar of the
  schema, so a large schema gives a large file; `prune_types` limits it to
  what the operations use (see [Smaller types.dart](#smaller-typesdart)).
- One schema per build. Several packages can share one schema (see
  [Several packages](#several-packages)), but a package can't use two.

## Troubleshooting

**Conflicting outputs**: `dart run build_runner clean`, then build again.

**`Target of URI hasn't been generated: types.g.dart`** or
**`_$UserFromJson isn't defined`** (only with `result_types: schema`): run
`build_runner build` once more (see [Running the generator](#running-the-generator)).

**Remote schema fails to download**: read the `SCH500` message. It says what
each attempt (SDL, `?sdl`, introspection) returned. A 401 or 403 usually means
`schema_headers` are missing; HTML in the response usually means the URL points
to a playground page instead of the API.

**`CacheMissException` for a query that worked over the network**: some
operation probably selects an object without its `id` while another selects
it with `id`. Select `id` everywhere (see [Cache](#cache)).

**Widget tests with a subscription fail on the `connectivity_plus` channel**:
mock it (see [Testing widgets with subscriptions](#testing-widgets-with-subscriptions)).

## Development

```bash
dart pub get
dart test             # includes tests that compile and run generated code
dart test -x compile  # skip those
dart test -t flutter  # only the Flutter widgets and hooks (needs flutter on PATH)
```

The compile test generates code for several schemas in both result modes, runs
`json_serializable` and `dart analyze` on it, and executes it against a fake
GraphQL link. If you change what the generator emits, that's the test that tells
you whether the output still works.

Changes are listed in [CHANGELOG.md](CHANGELOG.md), plans in
[ROADMAP.md](ROADMAP.md). License: see [LICENSE](LICENSE).
