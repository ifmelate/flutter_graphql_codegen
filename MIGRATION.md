# Migration

- [3.0 to 3.1](#migrating-from-30-to-31)
- [2.x to 3.0](#migrating-from-2x-to-30)

## Migrating from 3.0 to 3.1

3.1 adds options that are all off by default, so most projects only bump the
version. Three things behave differently:

**Input `copyWith(x: null)` now sends `null`.** In 3.0 it set the field to
null, and `toJson()` then left it out, so the server kept its value. Now the
field is sent as `null`, which servers read as "clear it". If you used
`copyWith(x: null)` to mean "don't send x", build the input without it
instead:

```dart
// 3.0: email left out; 3.1: email sent as null
final patch = current.copyWith(email: null);

// leave email out in 3.1
final patch = UserPatch(name: current.name, tags: current.tags);
```

**Input `fromJson` keeps explicit nulls.** A key holding `null`
(`{'email': null}`) becomes an explicit `null` that `toJson()` sends again; a
missing key stays absent. In 3.0 both were left out. This matters if you
build inputs from stored or user-provided JSON: drop the null keys first if
you don't want them sent. Such an input is also no longer `==` to one built
without the key.

**Variables classes compare by value.** `GetUserVariables(id: '1') ==
GetUserVariables(id: '1')` is now true. Code that relied on identity (keeping
two equal variables apart in a `Set` or as map keys) needs another key.

`<op>QueryOptions` has two new optional parameters, `onComplete` and
`onError`; existing calls compile unchanged. With `include_null_inputs: true`
nothing changes for inputs, since every null was sent already.

To use the Flutter widgets and hooks, add `graphql_flutter: ^5.2.0` (which
needs `graphql: ^5.2.0`); see the README.

## Migrating from 2.x to 3.0

3.0 changes what results look like. In 2.x a query returned the classes of the
schema types (`User`, `Post`), with every field of the type, so a query that
left out a non-null field failed to parse. In 3.0 every selection gets its own
class with only the selected fields (`GetUser_User`), fragments become
interfaces, and interfaces and unions become sealed classes.

There are two ways to upgrade:

- [Quick path](#quick-path-keep-the-2x-classes): set `result_types: schema` and
  keep your code. It takes a few minutes.
- [Full path](#full-path-per-operation-result-classes): move to the new result
  classes, operation by operation in your code, but in one build.

Both need Dart language 3.0 or newer in your package (`environment: sdk:
^3.0.0` or higher). The generator itself already required Dart 3.4 in 2.x.

### Quick path: keep the 2.x classes

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_graphql_codegen: ^3.0.0
  json_serializable: ^6.7.1   # still needed in this mode
```

```yaml
# graphql_codegen.yaml
result_types: schema
```

With `result_types: schema` the generated code is almost the same as with
2.5.0. What still changes:

- Since 3.0.1, a nullable list field of an input class starts as `null`, not
  `[]`, so an unset filter list is left out of the request instead of being
  sent as "none of these". Code that adds to such a list in place
  (`filter.tags?.add(x)` or `filter.tags!.add(x)`) must create the list first:
  `filter.tags = [x]`.
- Since 3.0.1, a variable with a default value is sent with that default when
  you don't give it, instead of being left out.
- `types.dart` has two new top-level functions, `graphqlDeepEquals` and
  `graphqlDeepHash`. Rename your own functions if they have those names and
  you import the generated files without a prefix.
- Helpers deprecated in 2.1 are gone. This only matters if you call the
  generator from Dart code instead of through `build_runner`:

  | Removed | Use instead |
  |---------|-------------|
  | `GraphQLCodeGenerator.generateCode` | `GraphQLCodeGenerator.generateOperationFile` |
  | `TypeGenerator.generateTypeDefinitions`, `generateClassForType` | `TypeGenerator.generateTypesFile` |
  | `TypeGenerator.getDartTypeFromOriginal` | none |
  | `OperationAnalyzer.getOperationReturnType`, `getOperationFieldName`, `hasSkipDirective`, `getSkippableFields` | none |
  | `SchemaAnalyzer.extractCustomScalars`, `getSchemaType`, `isScalarType` | none |
  | `SchemaAnalyzer.mapSchemaTypeToDartType`, `mapGraphQLTypeToDartType` | `SchemaAnalyzer.getDartType` (closest) |

That's all. You can do the full path later.

### Full path: per-operation result classes

Remove `result_types` from the config (or set it to `operation`, the default),
then go through the steps below. `result_types` applies to the whole build, so
all operations switch at once; the compiler shows you every place to change.

#### 1. Dependencies and build

`json_serializable` is no longer used. Remove it from `dev_dependencies` unless
your own code needs it, and delete the old `types.g.dart` from `output_dir`.
Keep `json_annotation` in `dependencies`: `types.dart` still uses its
`JsonConverter`.

```yaml
dependencies:
  graphql: ^5.1.3
  json_annotation: ^4.8.1

dev_dependencies:
  flutter_graphql_codegen: ^3.0.0
  build_runner: ^2.4.6
```

One `build_runner build` is now enough, also on a fresh checkout.

#### 2. Result types

`types.dart` no longer has classes for object types, interfaces and unions.
Results use classes named after the operation and the path of response keys:

```graphql
query GetUser($id: ID!) {
  user(id: $id) { id name friends { id name } }
}
```

| 2.x | 3.0 |
|-----|-----|
| `User? parseGetUserData(...)` | `GetUser_User? parseGetUserData(...)` |
| `Future<User?> getUserData(...)` | `Future<GetUser_User?> getUserData(...)` |
| `QueryOptions<User?> getUserQueryOptions(...)` | `QueryOptions<GetUser_User?> getUserQueryOptions(...)` |
| `user.friends` is `List<User>` | `user.friends` is `List<GetUser_User_Friends>` |
| `DashboardResult` (several root fields) | `DashboardResult`, now with `fromJson`/`toJson`/`copyWith`, and its fields use the new classes |

Field names don't change. Fields you didn't select are gone, which is the
point: if your code reads a field the query doesn't select, add it to the
query. Fields under `@skip`/`@include` are now nullable.

Every class has a `const` constructor, `final` fields, `fromJson`, `toJson`,
deep `==`/`hashCode` and `copyWith`. A non-root class also has `typename`.

#### 3. Code shared between operations: use fragments

In 2.x, a widget or function could take a `User` from any query. In 3.0, each
query has its own class, so put the fields the shared code needs into a
fragment and take the fragment's interface:

```graphql
fragment UserCard on User { id name }

query GetUser($id: ID!) { user(id: $id) { ...UserCard email } }
query Dashboard { me { ...UserCard role } }
```

```dart
// 2.x
Widget userTile(User user) => Text(user.name);

// 3.0: GetUser_User and Dashboard_Me both implement UserCard
Widget userTile(UserCard user) => Text(user.name);
```

The interfaces are in `fragments.dart`, exported from `index.dart`. Fragment
names must be unique across all documents (two fragments with the same name
and different selections fail with `BLD102`). A fragment named like an enum or
input type gets a trailing underscore (`Role_`).

To build a fragment's data by hand, for tests or previews, use
`<Fragment>Data`: `const UserCardData(typename: 'User', id: '1', name: 'Ann')`.

#### 4. Interfaces and unions

Abstract classes with `Unknown<Name>` fallbacks become sealed classes with one
subclass per type the selection has fields for, and `_Other` for the rest:

```dart
// 2.x
switch (result) {
  case User user:
    print('user ${user.name}');
  case Post post:
    print('post ${post.title}');
  case UnknownSearchResult other:
    print('something new: ${other.typename}');
}

// 3.0
switch (result) {
  case Search_Search_OnUser(:final name):
    print('user $name');
  case Search_Search_OnPost(:final title):
    print('post $title');
  case Search_Search_Other(:final typename):
    print('something new: $typename');
}
```

The `switch` is exhaustive without a `default`. Types without fields of their
own in the selection also end up in `_Other`, and `typename` is non-null there.
Keep passing `possibleTypes` to `GraphQLCache`.

#### 5. Writing to the cache

`write<Op>` takes the typed result instead of a raw map, and adds `__typename`
itself:

```dart
// 2.x
client.writeGetUser(vars, {
  '__typename': 'Query',
  'user': {'__typename': 'User', 'id': '42', 'name': 'Ann', 'friends': []},
});

// 3.0
client.writeGetUser(
  vars,
  const GetUser_User(typename: 'User', id: '42', name: 'Ann', friends: []),
);

// or change what is cached
final cached = client.readGetUser(vars);
if (cached != null) client.writeGetUser(vars, cached.copyWith(name: 'Ann'));
```

If you still have a raw map, write it with `package:graphql` directly:
`client.writeQuery(getUserQueryOptions(vars).asRequest, data: map)`.
`read<Op>` and `evict<Op>` work as before (`read<Op>` returns the new class).

Fragments can now be read and written per object with
`client.read<Fragment>Fragment(idFields)` and
`client.write<Fragment>Fragment(idFields, data)`; see the README.

#### 6. Input types

Input classes in `types.dart` are now immutable: a `const` constructor and
`final` fields, plus `==`/`hashCode` and `copyWith`. Constructor calls don't
change; code that assigns fields does:

```dart
// 2.x
final filter = UserFilter(first: 10);
filter.role = Role.ADMIN;

// 3.0
const filter = UserFilter(first: 10);
final admins = filter.copyWith(role: Role.ADMIN);
final everyone = admins.copyWith(role: null);   // null clears a field
```

`toJson()` sends the same JSON as before, including with `include_null_inputs`.

#### 7. `unknown_enum_fallback`

If you use it:

- Enum fields of result classes have a `<field>Raw` sibling, as object types had
  in 2.x. `toJson()` now writes the raw string back for `$unknown`, so the value
  survives a round trip through the cache.
- `$unknown` inside an enum list of an input now throws `ArgumentError` in
  `toJson()`, like a single `$unknown` value already did. In 2.x lists weren't
  checked. (With `result_types: schema` they still aren't.)

#### Checklist

- [ ] `flutter_graphql_codegen: ^3.0.0`, Dart language 3.0+
- [ ] `json_serializable` removed (or `result_types: schema` set)
- [ ] old `types.g.dart` deleted
- [ ] schema class names replaced by operation classes or fragment interfaces
- [ ] `switch` over unions and interfaces uses `_On<Type>` / `_Other`
- [ ] `write<Op>` calls pass typed results
- [ ] no assignments to input fields
