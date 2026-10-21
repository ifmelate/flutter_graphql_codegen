# Roadmap

Plans, not promises. Order may change; each item ships with tests.

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
