# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2025-08-31

### Fixed
- CI stability: make `dart analyze --fatal-infos` pass by removing an unused import in tests

## [1.0.0] - 2025-06-08

### Added

#### 🎯 Core Features
- **Type-safe code generation** from GraphQL schemas and operations
- **Automatic Dart class generation** with JSON serialization support via `json_annotation`
- **GraphQL client extensions** for queries, mutations, and subscriptions
- **Full null safety support** with graceful error handling and safe defaults

#### 📦 Custom Scalar Support
- `DateTime` with automatic parsing and `DateTimeConverter`
- `Decimal` for precise decimal numbers with `DecimalConverter`
- `Long` for large integers with `LongConverter`
- `Byte` for byte values with `ByteConverter`
- `JSON` for arbitrary JSON data handling
- Safe type converters for all basic types (`SafeBoolConverter`, `SafeIntConverter`, `SafeDoubleConverter`, `SafeStringConverter`)

#### 🌐 Multiple Schema Sources
- **Local file paths**: relative and absolute paths
- **HTTP/HTTPS URLs**: direct GraphQL endpoint introspection
- **File URLs**: `file://` protocol support
- **Alternative configuration**: support for `schema` and `documents` field names

#### 🔧 Advanced GraphQL Features
- **Object types and interfaces** with proper inheritance handling
- **Union types** with discriminated union support
- **Enums** with custom values and safe parsing
- **Input types** with validation and complex arguments
- **Lists and nullable combinations** (T, T?, [T], [T]?, [T?], [T?]?)
- **Fragments and inline fragments** for query optimization
- **Custom directives** handling
- **Nested and recursive types** with circular reference detection

#### 🛠️ Development Tools
- **Build system integration** via `build_runner` and `Builder` pattern
- **Flexible configuration** through YAML files
- **Glob pattern support** for GraphQL document discovery
- **Output directory customization**
- **Generated file management** with proper imports and exports

#### 🧪 Quality Assurance
- **Comprehensive test coverage** (85%+ coverage)
- **Edge case handling** for malformed GraphQL schemas
- **Error recovery** for invalid or missing data
- **Type safety validation** across all generated code
- **Integration tests** with real-world GraphQL schemas

### Technical Implementation

#### Code Generation Architecture
- Modular generator design with separate components:
  - `TypeGenerator`: Handles GraphQL type to Dart class conversion
  - `ClientExtensionGenerator`: Creates GraphQL client extension methods
  - `SchemaAnalyzer`: Parses and analyzes GraphQL schemas
  - `OperationAnalyzer`: Processes GraphQL operations (queries, mutations, subscriptions)
  - `SchemaDownloader`: Handles schema fetching from various sources

#### Generated Code Structure
```dart
// Example generated type
@JsonSerializable()
class User {
  final String id;
  final String? name;
  @SafeBoolConverter()
  final bool isActive;
  @DateTimeConverter()
  final DateTime? createdAt;
}

// Example generated extension
extension GraphQLClientExtensions on GraphQLClient {
  Future<QueryResult<GetUser$Query>> getUserQuery({
    required GetUserArguments variables,
  }) async {
    // Implementation with type safety
  }
}
```

#### Error Handling Strategy
- **Safe converters**: All custom scalar converters include fallback values
- **Null safety**: Proper handling of nullable types with safe defaults
- **Exception handling**: Graceful degradation for schema parsing errors
- **Validation**: Input validation for all generated methods

### Dependencies
- **Minimum Dart SDK**: 3.0.0 (full null safety support)
- **Flutter compatibility**: 3.x and above
- **Core dependencies**:
  - `json_annotation: ^4.8.1` for serialization annotations
  - `graphql: ^5.1.3` for GraphQL client operations
  - `build: ^2.0.0` for build system integration
  - `yaml: ^3.1.0` for configuration parsing
  - `gql: ^1.0.0` for GraphQL AST parsing

### Performance Optimizations
- **Lazy loading**: Generated extensions are loaded only when needed
- **Efficient parsing**: Optimized GraphQL schema parsing with caching
- **Minimal dependencies**: Only essential packages included
- **Tree-shaking friendly**: Generated code supports dead code elimination

### Documentation & Examples
- **Comprehensive README** with detailed usage examples
- **API documentation** with inline code examples
- **Configuration guide** for all supported schema sources
- **Testing examples** and best practices
- **Migration guide** for future versions

### Breaking Changes
- This is the initial release, no breaking changes from previous versions

### Migration Notes
- For new projects: Follow the installation and configuration guide in README.md
- This package replaces manual GraphQL type definitions and client code

### Known Limitations
- Schema introspection may be slower for very large GraphQL schemas (>1000 types)
- Custom directives are parsed but not actively processed in type generation
- WebSocket subscriptions require additional client configuration

---

**Note**: This changelog follows [Semantic Versioning](https://semver.org/) and [Keep a Changelog](https://keepachangelog.com/) standards.
