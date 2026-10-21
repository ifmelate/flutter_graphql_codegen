# flutter_graphql_codegen

[![pub package](https://img.shields.io/pub/v/flutter_graphql_codegen.svg)](https://pub.dev/packages/flutter_graphql_codegen)
[![license](https://img.shields.io/github/license/ifmelate/flutter_graphql_codegen.svg)](https://github.com/ifmelate/flutter_graphql_codegen/blob/main/LICENSE)

A `build_runner` builder that reads your GraphQL schema and `.graphql` operation
files and writes Dart code for [`package:graphql`](https://pub.dev/packages/graphql):
a result class for every selection of every operation, fragment interfaces, input
and enum types from the schema, and an extension on `GraphQLClient` for each
operation.

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

Upgrading from 2.x? See [MIGRATION.md](MIGRATION.md).

## Installation

```yaml
dependencies:
  graphql: ^5.1.3
  json_annotation: ^4.8.1

dev_dependencies:
  flutter_graphql_codegen: ^3.0.0
  build_runner: ^2.4.6
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
URL or an HTTP(S) endpoint.

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
exhaustive `switch` statements over enums incomplete.

About `include_null_inputs`: by default a null field of an input type, or a null
optional variable, is left out of the request. For a server that means "not
set", so you can't clear a field. With the option on, it is sent as `null`.
Variables with a default value (`$first: Int = 10`) are still left out when
null, because an explicit `null` would replace the default. This matches
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
  operations produces three files), with its result classes
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

### Variables and input types

`GetUserVariables` turns typed values into the map that `package:graphql` expects.
Enums are sent by their schema name, `DateTime` as ISO-8601 in UTC, and input
types through their `toJson()`. Optional variables you leave out are left out of
the map entirely. If you need to send an explicit `null`, pass a map by hand.

Input types from the schema are immutable classes in `types.dart`, with a
`const` constructor, `==`/`hashCode` and a `copyWith` that can set fields to
`null`:

```dart
const filter = UserFilter(first: 10, role: Role.ADMIN);
final next = filter.copyWith(first: 20, role: null);
```

List fields default to an empty list. Null fields are left out of `toJson()`
unless `include_null_inputs` is on.

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
| `CFG999` | Other config problem (bad value, unset env variable in `schema_headers`) |
| `SCH400` | The schema doesn't parse |
| `SCH401` | A custom scalar has no `scalar_mapping` entry and `strict_scalars` is on |
| `SCH402` | The schema has types the spec doesn't allow: an object, interface or input type without fields, a union without members, an enum without values, an interface implemented twice |
| `SCH404` | Schema file not found |
| `SCH500` | Remote schema download failed; the message lists every attempt |
| `BLD100` | An operation file doesn't parse |
| `BLD101` | An operation uses a fragment that isn't defined anywhere |
| `BLD102` | Two fragments share a name but differ, or two fragments would generate a class with the same name |
| `BLD103` | An operation selects a field the schema doesn't have (at any depth), or a plain field on a union |
| `BLD104` | Two operations have the same name (or names that map to the same file) |
| `BLD105` | Unknown argument, or a required argument is missing |
| `BLD106` | A variable is used but not declared, declared but never used, or has an unknown or non-input type |
| `BLD107` | A selection set is missing (object field) or not allowed (scalar field), a fragment is on an unknown or non-composite type, a fragment spreads itself, or an alias starts with `__` |
| `BLD108` | Two operations, or an operation and `fragments.dart`, would declare the same top-level name (e.g. `A_B_C` from operations `A_B` and `A`) |
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

## Troubleshooting

**Conflicting outputs**: `dart run build_runner clean`, then build again.

**`Target of URI hasn't been generated: types.g.dart`** or
**`_$UserFromJson isn't defined`** (only with `result_types: schema`): run
`build_runner build` once more (see [Running the generator](#running-the-generator)).

**Remote schema fails to download**: read the `SCH500` message. It says what
each attempt (SDL, `?sdl`, introspection) returned. A 401 or 403 usually means
`schema_headers` are missing; HTML in the response usually means the URL points
to a playground page instead of the API.

## Development

```bash
dart pub get
dart test             # includes a test that compiles and runs generated code
dart test -x compile  # skip that one
```

The compile test generates code for several schemas in both result modes, runs
`json_serializable` and `dart analyze` on it, and executes it against a fake
GraphQL link. If you change what the generator emits, that's the test that tells
you whether the output still works.

Changes are listed in [CHANGELOG.md](CHANGELOG.md), plans in
[ROADMAP.md](ROADMAP.md). License: see [LICENSE](LICENSE).
