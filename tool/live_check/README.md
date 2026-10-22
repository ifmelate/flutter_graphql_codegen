# Live checks against public GraphQL APIs

The tests in `test/` build their responses themselves. These checks use the
generator the way an app does, against real servers:

1. `fetch_schema` downloads the server's schema
2. `build_runner` generates the code (from this repository, not pub.dev)
3. `dart analyze` checks the generated code
4. `bin/main.dart` runs real queries and checks the parsed results

| Package | API | What it exercises |
|---------|-----|-------------------|
| `countries` | https://countries.trevorblades.com/graphql | input filters with nullable lists, a variable with a default used by `@include`, aliases with arguments, typed cache read/write |
| `rick_and_morty` | https://rickandmortyapi.com/graphql | pagination, default (legacy) nullability, a fragment shared by two queries, fragment cache read/write |
| `gitlab` | https://gitlab.com/api/graphql | a schema with thousands of types, a union deep in the result, a fragment on an interface, Relay `edges`/`nodes`/`pageInfo`, enum variables |
| `github` | https://api.github.com/graphql | interfaces (`GitObject`, `Node`, `Actor`), a union (`SearchResultItem`), input objects in arguments, a list of enums with a default |

Each check prints `OK` or `FAIL`; the script exits with 1 when any fails.
The checks don't depend on exact counts, since the data changes.

## Running

```bash
tool/live_check/run.sh                 # all packages
tool/live_check/run.sh countries gitlab
GITHUB_TOKEN=... tool/live_check/run.sh github
```

The GitHub API needs a token (any token that can read public repositories);
without `GITHUB_TOKEN` that package is skipped. The token is only read from
the environment. The other APIs need no authentication. Only public data is
read.

Downloaded schemas, generated code and logs are not committed (see
`.gitignore`). The directory is not part of the published package.

These checks need the network and depend on third-party servers, so they are
not part of the CI run on pull requests. Run them before a release, or after a
change to code generation, the client extension or the cache helpers.

## What they found

The first run, before 3.0.1, found three bugs that the tests in `test/`
missed. Each now has a regression test in
`test/public_api_regressions_test.dart`:

- a variable with a default value was left out of the request; with
  `@include` on it, the normalized cache expected fields the server didn't
  send (`PartialDataException`)
- nullable list fields of input classes defaulted to `[]`, so a filter like
  `{code: {eq: "DE"}}` was sent with `in: []` and matched nothing
- GitLab's schema has a scalar named `Duration`, which hid `dart:core`'s
  `Duration` in the generated code
