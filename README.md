# flutter_graphql_codegen

[![pub package](https://img.shields.io/pub/v/flutter_graphql_codegen.svg)](https://pub.dev/packages/flutter_graphql_codegen)
[![license](https://img.shields.io/github/license/ifmelate/flutter_graphql_codegen.svg)](https://github.com/ifmelate/flutter_graphql_codegen/blob/main/LICENSE)

A `build_runner` builder that reads your GraphQL schema and `.graphql` operation
files and writes Dart code for [`package:graphql`](https://pub.dev/packages/graphql):
model classes for the schema types and an extension on `GraphQLClient` for each
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

## Installation

```yaml
dependencies:
  graphql: ^5.1.3
  json_annotation: ^4.8.1

dev_dependencies:
  flutter_graphql_codegen: ^2.4.1
  build_runner: ^2.4.6
  json_serializable: ^6.7.1
```

The generated model classes use `json_serializable`, so it has to be in your dev
dependencies too.

## Configuration

Put a `graphql_codegen.yaml` next to your `pubspec.yaml`:

```yaml
schema_url: lib/graphql/schema.graphql
output_dir: lib/graphql/generated
document_paths:
  - lib/graphql/documents/**/*.graphql
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
| `strict_nullability` | `false` | Follow `!` from the schema exactly (see below) |
| `file_naming` | `snake_case` | `snake_case`, `kebab-case`, `camelCase` or `PascalCase` |
| `emit_index` | `true` | Write an `index.dart` that exports everything |
| `scalar_mapping` | `{}` | Map a custom scalar to an existing Dart type, e.g. `Date: DateTime` |
| `schema_headers` | `{}` | HTTP headers for downloading a remote schema |
| `diagnostics_format` | `plain` | `plain` or `json` error output |
| `unknown_enum_fallback` | `false` | Add a `$unknown` value to every enum instead of throwing on values the server added later (see below) |
| `deprecated_annotations` | `false` | Turn schema `@deprecated` into Dart `@Deprecated` (see below) |
| `validate_documents` | `true` | Check operations against the schema before generating (see [Errors](#errors)) |
| `strict_scalars` | `false` | Fail when a custom scalar has no `scalar_mapping` entry (see [Custom scalars](#custom-scalars)) |
| `schema_endpoint` | none | Where `fetch_schema` downloads the schema from (see above) |

A misspelled key is ignored with a warning that suggests the closest option.

About `strict_nullability`: with the default `false`, list fields are always
nullable, and the typed `*Data` methods return nullable values at every level.
Turn it on for new projects. It's off by default only so existing code keeps
compiling.

About `unknown_enum_fallback`: by default an enum value the generator doesn't
know (the server added it after you generated the code) throws while parsing.
That is risky for mobile apps, where old versions stay installed for a long
time. With the option on, every enum gets an extra `$unknown` value, and unknown
values parse to it, also inside lists. Sending `$unknown` back to the server
throws `ArgumentError`. It's off by default because the extra value makes your
existing exhaustive `switch` statements over enums incomplete.

About `deprecated_annotations`: descriptions from the schema always become doc
comments, and a `@deprecated` field or enum value gets a `Deprecated: <reason>`
line there. With the option on it also gets a real `@Deprecated` annotation, so
the IDE strikes it out. The catch: `types.g.dart` (written by
`json_serializable`) uses those members too, so `dart analyze`/`flutter analyze`
report `deprecated_member_use_from_same_package` there. Exclude generated files
from analysis if you turn it on:

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

On a fresh checkout you need to run it twice. The first run writes `types.dart`
and the operation files; the second lets `json_serializable` generate
`types.g.dart` for the new classes. After that one run is enough unless the
schema changes.

## What you get

`output_dir` ends up with:

- `types.dart`, with a class for every object, input, interface and union in the
  schema, plus enums, JSON converters and a `possibleTypes` map
- one `<operation>_graphql.g.dart` per named operation (a file with three
  operations produces three files)
- `index.dart`, which exports all of the above

The files are formatted with `dart format` for your package's language version,
so a `dart format --set-exit-if-changed` check in CI passes without excluding
them.

For `query GetUser($id: ID!)`, the operation file contains:

```dart
final getUserDocument = graphql.gql(r"""...""");      // the query, with fragments
const String getUserOperationName = 'GetUser';

class GetUserVariables { ... Map<String, dynamic> toJson() }

User? parseGetUserData(Map<String, dynamic>? data);   // response -> model

// package:graphql options with typed variables and parsedData
QueryOptions<User?> getUserQueryOptions(GetUserVariables variables, {fetchPolicy, ...});
WatchQueryOptions<User?> getUserWatchQueryOptions(GetUserVariables variables, {...});

extension GetUserExtension on graphql.GraphQLClient {
  Future<QueryResult<Map<String, dynamic>>> getUser([Map<String, dynamic>? variables]);
  Future<User?> getUserData([Map<String, dynamic>? variables]);
  User? readGetUser(GetUserVariables variables);              // from the cache
  void writeGetUser(GetUserVariables variables, Map<String, dynamic> data);
}
```

Mutations work the same way through `client.mutate`. Subscriptions return
streams:

```dart
client.userUpdatedData({'id': '42'}).listen((user) => print(user?.name));
```

If an operation selects more than one root field, `*Data` returns a small result
class with one property per field (named after the alias if there is one):

```dart
// query Dashboard { me { id } notifications { id } }
final dashboard = await client.dashboardData();
print(dashboard?.me?.id);
print(dashboard?.notifications?.length);
```

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
final User? user = result.parsedData;

final ObservableQuery<User?> query = client.watchQuery(
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

For queries, `read<Operation>` returns the cached result, typed, or null when
it isn't cached, and `write<Operation>` puts data into the cache. Write data in
the shape the server returns, with `__typename` on every object including the
root.

### Variables

`GetUserVariables` turns typed values into the map that `package:graphql` expects.
Enums are sent by their schema name, `DateTime` as ISO-8601 in UTC, and input
types through their `toJson()`. Optional variables you leave out are left out of
the map entirely. If you need to send an explicit `null`, pass a map by hand.

### Interfaces and unions

These become abstract classes, and `fromJson` picks the concrete class by
`__typename`. The builder adds `__typename` to every selection in the generated
documents, so you don't have to. A type the generator didn't know about (say the
server added a new union member) ends up as `Unknown<Name>` instead of crashing:

```dart
for (final result in await client.searchData({'term': 'dart'})) {
  switch (result) {
    case User user:
      print('user ${user.name}');
    case Post post:
      print('post ${post.title}');
    case UnknownSearchResult other:
      print('something new: ${other.typename}');
  }
}
```

Pass `possibleTypes` to the cache, so fragments on interfaces and unions are
matched correctly when results are read back from it:

```dart
final client = GraphQLClient(
  link: link,
  cache: GraphQLCache(possibleTypes: possibleTypes),
);
```

### Fragments

Fragments can live in their own files, as long as those files match
`document_paths`. Each operation document includes only the fragments it uses.

### Names that aren't valid Dart

A field called `class` or an enum value called `default` gets a trailing
underscore in Dart (`class_`, `Role.default_`), and so does a field named like a
type (`int`, `String`, `Media: Media` -> `int_`, `String_`, `Media_`). Leading
underscores would make a name private, so they move to the end: `_id` becomes
`id_`. JSON keys and values sent to the server keep the original GraphQL names.

The same goes for schema types named like something the generated code relies
on: `dart:core` types (`Map`, `String`, `Object`, `Future`, `Set`, ...),
`json_annotation` classes (`JsonKey`, ...) and the built-in helpers (`Decimal`,
`Long`, `Byte` when they are object types rather than scalars). `type Map`
becomes `class Map_`, `scalar Object` becomes `Object_`. `__typename` and
`possibleTypes` keep the GraphQL names.

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
is added to `types.dart` and to the operation files:

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
| `SCH404` | Schema file not found |
| `SCH500` | Remote schema download failed; the message lists every attempt |
| `BLD100` | An operation file doesn't parse |
| `BLD101` | An operation uses a fragment that isn't defined anywhere |
| `BLD102` | Two fragments share a name but differ |
| `BLD103` | An operation selects a field the schema doesn't have (at any depth), or a plain field on a union |
| `BLD104` | Two operations have the same name (or names that map to the same file) |
| `BLD105` | Unknown argument, or a required argument is missing |
| `BLD106` | A variable is used but not declared, declared but never used, or has an unknown or non-input type |
| `BLD107` | A selection set is missing (object field) or not allowed (scalar field), or a fragment is on an unknown or non-composite type |
| `BLD200` | Writing `index.dart` failed |

`BLD103` and `BLD105`–`BLD107` come from checking each operation against the
schema. All problems of an operation are reported together, with the path and
line of each one. These are documents a GraphQL server would reject anyway. If a
check gets in the way while you fix an existing project, turn it off with
`validate_documents: false`.

## Known limitations

The biggest one: the generated classes follow the schema types, not the fields
your query selects. If `User.name` is `String!` in the schema and a query asks
for `user { id }` only, parsing that `User` throws because `name` is missing.
For now, select every non-nullable field of the object types you fetch.
Per-query result types would fix this properly, but they'd change the generated
API, so they're planned for a major release.

Other limitations:

- Anonymous operations are skipped, with a warning. Give every operation a name.
- If you rename an operation, the old generated file stays in `output_dir`.
  Delete it by hand.

## Troubleshooting

**`Target of URI hasn't been generated: types.g.dart`** or
**`_$UserFromJson isn't defined`**: run `build_runner build` once more (see
[Running the generator](#running-the-generator)).

**Conflicting outputs**: `dart run build_runner clean`, then build again.

**Remote schema fails to download**: read the `SCH500` message. It says what
each attempt (SDL, `?sdl`, introspection) returned. A 401 or 403 usually means
`schema_headers` are missing; HTML in the response usually means the URL points
to a playground page instead of the API.

## Development

```bash
dart pub get
dart test             # includes a ~20s test that compiles and runs generated code
dart test -x compile  # skip that one
```

The compile test generates code for `test/fixtures/schema.graphql`, runs
`json_serializable` and `dart analyze` on it, and executes it against a fake
GraphQL link. If you change what the generator emits, that's the test that tells
you whether the output still works.

Changes are listed in [CHANGELOG.md](CHANGELOG.md). License: see [LICENSE](LICENSE).
