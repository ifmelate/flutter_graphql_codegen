# Roadmap

Plans, not promises. Order may change; each item ships with tests.

## 2.5 — fixes without API changes

- An operation named like a `GraphQLClient` method (`Query`, `Mutate`,
  `Subscribe`, ...) generates extension methods that shadow the client's own
- A schema without object types leaves a `part 'types.g.dart'` that is never
  generated
- An enum named `Enum` clashes with the built-in `EnumConverter`
- Empty types (`type Mutation {}`) and repeated interfaces produce broken code
  instead of a clear error
- Document validation doesn't know the `__schema` and `__type` meta fields
- Inputs: tell an explicit `null` from a missing field
- Enums: keep the raw string next to `$unknown`
- Cache: evict a cached query

## 3.0 — result types per operation

- Result classes follow the selection, not the schema type: only the selected
  fields, aliases, `@skip`/`@include` make a field nullable, merged selections.
  Selecting `user { id }` no longer fails on a missing non-null `name`.
  `result_types: schema` keeps the 2.x classes
- Own `fromJson`/`toJson`: no `json_serializable`, one build pass
- `==`, `hashCode` (deep for lists and maps) and `copyWith`
- Fragments become interfaces, also on interfaces and unions
- Unions and interfaces become sealed classes for pattern matching, with an
  `Unknown` case for types added to the server later
- `readFragment` / `writeFragment`
- Removal of the helpers deprecated in 2.x

## 3.1 — Flutter and larger projects

- `graphql_flutter` widgets and `flutter_hooks` hooks per operation
- Several packages in one repository: the schema in a shared package,
  operations and fragments in feature packages
- `.nodes` on Relay-style connections (`edges { node }`)
- Optional grouping of operations: `client.users.getProfile()`

## Later

- Fragment data masking (a parent sees only its own fields, not the fields of
  child fragments)
- Several schemas in one project
