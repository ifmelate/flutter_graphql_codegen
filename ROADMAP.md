# Roadmap

Plans, not promises. Order may change; each item ships with tests.

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
