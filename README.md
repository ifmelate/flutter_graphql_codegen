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
- 🚀 **GraphQL client extensions** for queries, mutations, and subscriptions
- 🛡️ **Null safety** support with graceful error handling
- 📦 **Custom scalar support** (DateTime, Decimal, Long, Byte, etc.)
- 🔄 **Safe type converters** with fallback values
- 📋 **Support for complex GraphQL features**:
  - Interfaces and unions
  - Enums with custom values
  - Input types and arguments
  - Fragments and inline fragments
  - Custom directives
  - Nested and recursive types
- 🌐 **Multiple schema sources**: local files, HTTP/HTTPS URLs, file URLs
- 🧪 **Comprehensive test coverage** with robust error handling

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
      flutter_graphql_codegen:
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
import 'lib/graphql/generated/types.dart';
import 'lib/graphql/generated/get_user.dart';

// Initialize GraphQL client
final client = GraphQLClient(
  link: HttpLink('https://your-graphql-endpoint.com/graphql'),
  cache: GraphQLCache(),
);

// Use the generated extension method
final result = await client.getUserQuery(
  variables: GetUserArguments(id: 'user-123'),
);

if (result.hasException) {
  print('Error: ${result.exception}');
} else {
  final user = result.parsedData?.user;
  print('User: ${user?.name} (${user?.email})');
  print('Created: ${user?.createdAt}');
}
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

@DecimalConverter()
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
// Mutation with input validation
final createResult = await client.createUserMutation(
  variables: CreateUserArguments(
    input: CreateUserInput(
      name: 'John Doe',
      email: 'john@example.com',
      role: UserRole.moderator,
    ),
  ),
);

// Subscription with real-time updates
final subscription = client.userUpdatedSubscription(
  variables: UserUpdatedArguments(id: 'user-123'),
);

await for (final result in subscription.stream) {
  if (result.data != null) {
    final user = result.parsedData?.userUpdated;
    print('User updated: ${user?.name}');
  }
}
```

### Error Handling

The generator includes robust error handling:

```dart
// Safe converters handle malformed data gracefully
@SafeBoolConverter()
bool isActive; // Defaults to false if null or invalid

@SafeIntConverter()
int count; // Defaults to 0 if null or invalid

// Custom error handling
final result = await client.getUserQuery(
  variables: GetUserArguments(id: 'invalid-id'),
);

if (result.hasException) {
  // Handle GraphQL errors
  final graphQLErrors = result.exception?.graphqlErrors;
  final networkError = result.exception?.linkException;
  
  print('GraphQL Errors: $graphQLErrors');
  print('Network Error: $networkError');
} else {
  // Safe to access data
  final user = result.parsedData?.user;
}
```

## ⚙️ Configuration Options

| Option | Description | Default | Required |
|--------|-------------|---------|----------|
| `schema_url` | GraphQL schema source (URL or file path) | - | ✅ |
| `output_dir` | Output directory for generated files | `lib/generated` | ❌ |
| `document_paths` | Glob patterns for GraphQL operation files | `**/*.graphql` | ❌ |

## 📚 API Reference

### Generated Types

All GraphQL types are generated as Dart classes with:
- ✅ JSON serialization support (`fromJson`/`toJson`)
- ✅ Null safety with safe defaults
- ✅ Proper field typing based on GraphQL schema
- ✅ Custom scalar handling with type converters

### Generated Extensions

For each operation, the generator creates client extensions:
- **Queries**: `client.{operationName}Query(variables?)`
- **Mutations**: `client.{operationName}Mutation(variables?)`
- **Subscriptions**: `client.{operationName}Subscription(variables?)`

### Type Safety

```dart
// Generated with full type safety
class GetUserArguments {
  final String id;
  
  GetUserArguments({required this.id});
}

class User {
  final String id;
  final String? name;
  final String? email;
  @SafeBoolConverter()
  final bool isActive;
  
  User({
    required this.id,
    this.name,
    this.email,
    required this.isActive,
  });
}
```

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
- The endpoint is accessible
- Authentication headers are set if required
- The URL returns valid GraphQL schema (SDL format)

#### Complex Type Generation Issues

If complex types aren't generating correctly:
- Check that your GraphQL schema is valid
- Ensure operation files have the correct extension (`.graphql`)
- Verify the `document_paths` configuration matches your file structure

## 🧪 Testing

The package includes comprehensive test coverage:

```bash
# Run all tests
dart test

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
