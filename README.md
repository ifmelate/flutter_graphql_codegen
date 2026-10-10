<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages). 
-->

# Flutter GraphQL Codegen

[![pub package](https://img.shields.io/pub/v/flutter_graphql_codegen.svg)](https://pub.dev/packages/flutter_graphql_codegen)
[![license](https://img.shields.io/github/license/ifmelate/flutter_graphql_codegen.svg)](https://github.com/ifmelate/flutter_graphql_codegen/blob/main/LICENSE)

A code generator for Flutter GraphQL applications that generates type-safe Dart classes and client extensions from GraphQL schemas and operations.

## ✨ Features

- 🎯 **Type-safe code generation** from GraphQL schemas and operations
- 🔧 **Automatic Dart class generation** with proper JSON serialization
- 🚀 **GraphQL client extensions** for queries, mutations, and subscriptions (as `Stream`s)
- 🧾 **Typed variables** classes for every operation with variables
- 🛡️ **Null safety** support; GraphQL errors surface as `OperationException`
- 📦 **Custom scalar support** (DateTime, Decimal, Long, Byte, etc.)
- 🔄 **Safe type converters** with fallback values
- 📋 **Support for complex GraphQL features**:
  - Interfaces and unions (resolved via `__typename`, with `Unknown*` fallbacks)
  - Enums (values that clash with Dart keywords are escaped, e.g. `default_`)
  - Input types and arguments
  - Fragments (also across files) and inline fragments
  - `@skip` / `@include`, aliases, multiple root fields
  - Schema extensions (`extend type ...`)
  - Nested and recursive types
- 🌐 **Multiple schema sources**: local files, HTTP/HTTPS URLs (SDL or introspection, with auth headers), file URLs
- 🧪 **Comprehensive test coverage** with robust error handling
- 🔁 **Deterministic output**: stable sorting for enums/fields, write-only-if-changed, stable index export

## 🚀 Getting Started

### Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_graphql_codegen: ^1.0.0
  graphql: ^5.1.3
  json_annotation: ^4.8.1

dev_dependencies:
  build_runner: ^2.4.6
  json_serializable: ^6.7.1
```

### Configuration

1. **Create a `build.yaml` file** in your project root:

```yaml
targets:
  $default:
    builders:
      flutter_graphql_codegen|graphql_codegen:
        enabled: true
        options:
          config_path: "graphql_codegen.yaml"
```

2. **Create a `graphql_codegen.yaml` configuration file**:

```yaml
# Schema source - supports multiple formats
schema_url: "lib/graphql/schema.graphql"  # Local file path
# schema_url: "https://api.example.com/graphql"  # HTTP/HTTPS URL
# schema_url: "file:///absolute/path/to/schema.graphql"  # File URL

output_dir: "lib/graphql/generated"
document_paths:
  - "lib/graphql/documents/**/*.graphql"
```

##### Advanced Options

```yaml
# Optional advanced settings
file_naming: snake_case       # snake_case | kebab-case | camelCase | PascalCase
strict_nullability: true      # follow GraphQL '!' exactly for fields and lists
emit_index: true              # generate index.dart exporter
diagnostics_format: plain     # plain | json
scalar_mapping:               # GraphQL scalar -> Dart type overrides
  # JSON: dynamic
  # Date: DateTime
schema_headers:               # headers for downloading a remote schema
  # Authorization: "Bearer ${GRAPHQL_TOKEN}"   # ${VAR} reads an env variable
```

#### Schema Source Options

The `schema_url` field supports multiple source types:

🏠 **Local Files:**
```yaml
schema_url: "schema.graphql"                    # Relative path
schema_url: "lib/graphql/schema.graphql"        # Relative path with directories
schema_url: "/absolute/path/to/schema.graphql"  # Absolute path
```

🔗 **File URLs:**
```yaml
schema_url: "file:///absolute/path/to/schema.graphql"
```

🌐 **HTTP/HTTPS URLs:**
```yaml
schema_url: "https://api.example.com/graphql"      # GraphQL endpoint
schema_url: "http://localhost:4000/graphql/sdl"    # Direct SDL endpoint
```

For URLs the generator tries, in order: `GET <url>` returning SDL, `GET <url>?sdl`,
and finally a standard introspection query (`POST`) whose result is converted to SDL.
Remote schemas are downloaded once per `build_runner` run; restart `watch` to
pick up remote schema changes. Local schema files inside the package are tracked,
so editing them triggers regeneration.

#### Alternative Configuration Format

You can also use alternative field names for compatibility:

```yaml
schema: "lib/graphql/schema.graphql"  # Instead of schema_url
documents:                            # Instead of document_paths
  - "lib/graphql/documents/**/*.graphql"
```

## 📖 Usage

### Basic Example

1. **Define your GraphQL operations** in `.graphql` files:

```graphql
# lib/graphql/queries/get_user.graphql
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
    email
    isActive
    createdAt
  }
}
```

2. **Run the code generator**:

```bash
# First run: Generates GraphQL operation files and types.dart
dart run build_runner build --delete-conflicting-outputs

# Second run: Generates JSON serialization code (types.g.dart)
dart run build_runner build --delete-conflicting-outputs
```

**Important:** You need to run the build command **twice**:
- **First run** generates GraphQL types and operations
- **Second run** generates JSON serialization code for the types

This is because the JSON serialization generator (`json_serializable`) needs the types.dart file to exist before it can generate the corresponding .g.dart files.

3. **Use the generated code** in your Flutter app:

```dart
import 'package:graphql/client.dart';
import 'package:your_app/graphql/generated/index.dart';

final client = GraphQLClient(
  link: HttpLink('https://your-graphql-endpoint.com/graphql'),
  cache: GraphQLCache(),
);

// Typed data (variables built with the generated GetUserVariables class)
final user = await client.getUserData(GetUserVariables(id: 'user-123').toJson());
print('User: ${user?.name}');

// Raw QueryResult, if you need it
final result = await client.getUser({'id': 'user-123'});
```

### What gets generated

For every named operation (each operation in a file gets its own file):

| Generated | Example for `query GetUser($id: ID!)` |
|-----------|----------------------------------------|
| Document constant (with fragments and `__typename`) | `getUserDocument` |
| Operation name constant | `getUserOperationName` |
| Variables class (when the operation has variables) | `GetUserVariables(id: '1').toJson()` |
| Response parser | `User? parseGetUserData(Map<String, dynamic>? data)` |
| Raw method on `GraphQLClient` | `Future<QueryResult<...>> getUser([variables])` |
| Typed method on `GraphQLClient` | `Future<User?> getUserData([variables])` |

- **Mutations** use `client.mutate`, **subscriptions** return `Stream`s from `client.subscribe`.
- An operation selecting **several root fields** returns a `<Operation>Result`
  class with one property per field (aliases are used as names).
- The document constant and parser let you use any client feature, e.g. `watchQuery`
  or a custom `fetchPolicy`:

```dart
final observable = client.watchQuery(WatchQueryOptions(
  document: getUserDocument,
  variables: GetUserVariables(id: '1').toJson(),
  fetchPolicy: FetchPolicy.cacheAndNetwork,
));
observable.stream.map((r) => parseGetUserData(r.data));
```

### Advanced Features

#### Custom Scalars

The generator automatically handles custom scalars with safe converters:

```dart
// Generated safe converters with fallback values
@DateTimeConverter()
DateTime? createdAt;

@SafeIntConverter()
int count;

@SafeBoolConverter()
bool isActive;

@SafeDecimalConverter()
Decimal? price;
```

#### Complex Types and Operations

```graphql
# Schema types
type User {
  id: ID!
  profile: UserProfile
  posts: [Post!]!
  metadata: JSON
  role: UserRole!
}

input CreateUserInput {
  name: String!
  email: String!
  role: UserRole = USER
}

enum UserRole {
  ADMIN
  MODERATOR
  USER
}

# Mutation example
mutation CreateUser($input: CreateUserInput!) {
  createUser(input: $input) {
    id
    name
    email
    role
  }
}

# Subscription example
subscription UserUpdated($id: ID!) {
  userUpdated(id: $id) {
    id
    name
    isActive
  }
}
```

#### Generated Extensions Usage

```dart
// Query
final user = await client.getUserData(GetUserVariables(id: 'user-123').toJson());

// Mutation (input types have toJson(); enums are serialized by their schema name)
final created = await client.createUserData(CreateUserVariables(
  input: CreateUserInput(name: 'John Doe', email: 'john@example.com',
      role: UserRole.MODERATOR),
).toJson());

// Subscription
client.userUpdatedData(UserUpdatedVariables(id: 'user-123').toJson())
    .listen((user) => print(user?.name));
```

#### Interfaces and Unions

Interfaces and unions become abstract classes whose `fromJson` picks the concrete
class from `__typename` (added to every selection automatically). Unknown types
fall back to `Unknown<Name>`:

```dart
for (final item in await client.searchData({'term': 'dart'})) {
  switch (item) {
    case User u: print('user ${u.name}');
    case Post p: print('post ${p.title}');
    case UnknownSearchResult x: print('new type ${x.typename}');
  }
}
```

### Error Handling

The raw methods (`client.getUser(...)`) and typed methods (`client.getUserData(...)`)
throw `OperationException` when the result has GraphQL or network errors, so the
original `graphqlErrors` / `linkException` are preserved:

```dart
try {
  final user = await client.getUserData({'id': 'invalid-id'});
} on OperationException catch (e) {
  print('GraphQL errors: ${e.graphqlErrors}');
  print('Network error: ${e.linkException}');
}
```

Field-level converters stay lenient: `@SafeIntConverter()` / `@SafeBoolConverter()` /
`@SafeDoubleConverter()` on non-nullable fields fall back to `0` / `false` / `0.0`
when a value is missing or malformed.

## ⚙️ Configuration Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `schema_url` | GraphQL schema source (URL or file path) | - | ✅ |
| `output_dir` | Output directory for generated files | `lib/graphql/generated` | ❌ |
| `document_paths` | Glob patterns for GraphQL operation files | `[]` | ✅ |
| `file_naming` | Naming for generated operation files | `snake_case` | ❌ |
| `strict_nullability` | Follow GraphQL nullability (`!`) exactly | `false` | ❌ |
| `emit_index` | Emit `index.dart` exporter | `true` | ❌ |
| `diagnostics_format` | Errors output format | `plain` | ❌ |
| `scalar_mapping` | GraphQL scalar → Dart type map | `{}` | ❌ |
| `schema_headers` | HTTP headers for remote schema download (`${ENV}` expanded) | `{}` | ❌ |

> Note: `document_paths` or `documents` is required; the generator will fail if missing.

### Deterministic Output

- Definitions (types/enums) and fields are sorted by name for stable diffs
- Enum values are sorted alphabetically
- Files are written only when content changes (idempotent writes)
- `index.dart` exports generated files in a deterministic order

### Diagnostics and Error Codes

- `CFG001`: Missing `schema_url`/`schema`
- `CFG002`: Missing `document_paths`/`documents`
- `CFG999`: Invalid configuration
- `SCH400`: Invalid schema contents
- `SCH404`: Schema file not found
- `SCH500`: Schema download failed
- `BLD100`: Operation parse/build error
- `BLD101`: Operation uses an unknown fragment
- `BLD102`: Fragment defined twice with different selections
- `BLD103`: Operation selects a root field that is not in the schema
- `BLD200`: Index generation error

## 📚 API Reference

### Generated Types

All GraphQL types are generated as Dart classes with:
- ✅ JSON serialization support (`fromJson`/`toJson`)
- ✅ Null safety with safe defaults
- ✅ Proper field typing based on GraphQL schema
- ✅ Custom scalar handling with type converters

### Generated Extensions

For each operation `MyOperation`, the generator creates an extension on `GraphQLClient`:
- **Queries / mutations**: `client.myOperation([variables])` → `Future<QueryResult>` and
  `client.myOperationData([variables])` → typed `Future`
- **Subscriptions**: `client.myOperation([variables])` → `Stream<QueryResult>` and
  `client.myOperationData([variables])` → typed `Stream`

### Known Limitations

- Generated classes mirror **schema types**, not the fields an operation selects.
  If an operation does not select a non-nullable field of an object type (for
  example a `String!`), parsing that object throws. Select all non-nullable
  fields of the object types you fetch, or make them nullable in the schema.
- Variables classes omit optional variables that are `null`; explicitly sending
  `null` requires passing a plain map.

## 🔧 Troubleshooting

### Common Issues

#### "Target of URI hasn't been generated" Error

If you see errors like:
```
Target of URI hasn't been generated: 'package:your_app/graphql/generated/types.g.dart'
The method '_$UserFromJson' isn't defined for the type 'User'
```

**Solution:** Run the build command twice as described above. The first run generates the GraphQL types, and the second run generates the JSON serialization code.

#### Missing JSON Serialization Methods

If generated classes are missing `fromJson`/`toJson` methods:

1. Ensure you have the required dependencies:
```yaml
dependencies:
  json_annotation: ^4.8.1

dev_dependencies:
  build_runner: ^2.4.6
  json_serializable: ^6.7.1
```

2. Run build_runner twice:
```bash
dart run build_runner build --delete-conflicting-outputs
dart run build_runner build --delete-conflicting-outputs
```

#### Build Runner Conflicts

If you encounter build conflicts, use the clean option:
```bash
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

#### Schema Download Issues

For HTTP/HTTPS schema URLs, ensure:
- The endpoint is accessible (requests time out after 30 seconds)
- Authentication headers are configured via `schema_headers` if required
- The endpoint serves SDL or allows introspection

The `SCH500` error lists every attempt (SDL, `?sdl`, introspection) and why it failed.

#### Complex Type Generation Issues

If complex types aren't generating correctly:
- Check that your GraphQL schema is valid
- Ensure operation files have the correct extension (`.graphql`)
- Verify the `document_paths` configuration matches your file structure

## 🧪 Testing

The package includes comprehensive test coverage:

```bash
# Run all tests (includes a slower test that compiles generated code)
dart test

# Skip the compile test
dart test -x compile

# Run with coverage
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```

## 🤝 Contributing

Contributions are welcome! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup

1. Fork the repository
2. Clone your fork: `git clone https://github.com/ifmelate/flutter_graphql_codegen.git`
3. Install dependencies: `dart pub get`
4. Run tests: `dart test`
5. Make your changes
6. Submit a pull request



## 🔄 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and releases.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
