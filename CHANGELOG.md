# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- An operation named like a `GraphQLClient` member (`Query`, `Mutate`,
  `Subscribe`, `Link`, `Fragment`, ...) generated extension methods that the
  client's own members shadowed, and code that didn't compile. Those methods
  now get a trailing underscore (`client.query_()`, `client.readQuery_()`)
- A schema without object or input types produced a `types.dart` with
  `part 'types.g.dart'`, which json_serializable never writes

## [2.4.1] - 2026-10-21

### Fixed
- Didn't resolve next to `build` 3, 4 or 5 (current `build_runner`,
  `source_gen` 4, `hive_ce_generator`): `build` was limited to 2.x. Now
  `>=2.4.0 <6.0.0`
- Didn't resolve next to `hive_generator` on current Dart (3.9): it keeps `dart_style`
  at 2.3.6 (newer 2.x versions need an `analyzer` that no longer installs), and
  2.2.0–2.4.0 required 2.3.7. `dart_style` 2.3.0 and newer work again;
  versions before 2.3.7 format without a language version

## [2.4.0] - 2026-10-21

### Changed
- A `null` in a nullable `DateTime`, `LocalDate`, `Decimal`, `Long`, `Byte` or
  custom scalar field (or list element) now stays `null`. It used to become
  `DateTime.now()`, `Decimal('0')`, `Byte(0)` or a wrapper around `null`.
  Non-nullable fields behave as before
- A field named like a type now gets a trailing underscore (`Media_`), also
  when that type isn't used in the class

### Fixed
- Fields, variables and enum values starting with an underscore (`_id`)
  generated private named parameters that don't compile; they are now `id_`
- A field named like a type (`int: Int`, `String: String`, `Media: Media`)
  shadowed the type and didn't compile
- Lists of custom or built-in scalars with nullable elements (`[Custom]`,
  `[DateTime]`) and nested lists (`[[DateTime]]`) didn't compile

## [2.3.0] - 2026-10-17

### Added
- Typed options for `package:graphql`: every operation file has
  `<operation>QueryOptions` / `<operation>WatchQueryOptions` (queries),
  `<operation>MutationOptions` and `<operation>SubscriptionOptions`. They take
  typed variables and the full set of options (fetch and error policies,
  polling, optimistic results, mutation `update`, ...), and use the generated
  parser as `parserFn`, so `parsedData` and `ObservableQuery` results are typed
- `read<Operation>` / `write<Operation>` cache helpers on the client extension
  of queries
- `scalar_mapping` entries can be `{type, import, converter}`: the import is
  added to the generated files, and the converter is used for fields, list
  elements, variables and results. Mapped types without a converter are read
  with `fromJson` and written with `toJson`
- `strict_scalars`: fail with `SCH401` for custom scalars without a mapping
- `dart run flutter_graphql_codegen:fetch_schema` downloads the schema from
  `schema_endpoint` (new config key) into `schema_url`, so the schema can live
  in the repository and builds don't need the network

### Fixed
- Variables of a scalar mapped to `DateTime` (`scalar_mapping: {Date:
  DateTime}`) were put into the request as `DateTime` objects, which can't be
  sent as JSON. They are now serialized like `DateTime` scalars

## [2.2.0] - 2026-10-17

### Added
- Generated files are formatted with `dart format` for the language version of
  your package, so format checks in CI pass without excluding them
- `types.dart` exports `possibleTypes` for
  `GraphQLCache(possibleTypes: possibleTypes)`, so fragments on interfaces and
  unions are matched when reading from the cache
- Operations are checked against the schema before generation: unknown fields
  at any depth (`BLD103`, previously root fields only), unknown or missing
  required arguments (`BLD105`), undeclared, unused or wrongly typed variables
  (`BLD106`) and missing or unexpected selection sets and invalid fragment
  types (`BLD107`). All problems are reported together with path and line.
  `validate_documents: false` turns the checks off

### Fixed
- Schema types named like identifiers the generated code uses (`Map`,
  `String`, `Object`, `Future`, `Set`, `JsonKey`, object types named
  `Decimal`/`Long`/`Byte`, ...) produced code that didn't compile. Their Dart
  names now get a trailing underscore (`type Map` -> `class Map_`)
- With `strict_nullability`, non-null lists of custom scalars, `DateTime`,
  `LocalDate` and `Decimal` (`[JSON!]!`) didn't compile: the list helpers
  returned nullable lists

### Changed
- A build now fails for operations the schema rejects (they used to generate
  code that failed at runtime). Set `validate_documents: false` to keep the old
  behavior while fixing them
- Requires Dart 3.4 or newer (Flutter 3.22+), because `dart_style` needs it;
  projects on older SDKs keep resolving 2.1.0
- Requires `build` 2.4.0 or newer; adds `dart_style` and `pub_semver`
  dependencies

## [2.1.0] - 2026-10-17

### Added
- Schema descriptions become doc comments on generated classes, fields, enums
  and enum values; `@deprecated` is mentioned there as `Deprecated: <reason>`
- `deprecated_annotations` option: emit Dart `@Deprecated` for schema
  `@deprecated` fields and enum values
- `unknown_enum_fallback` option: enums get a `$unknown` value that unknown
  server values parse to (including in lists) instead of throwing
- Error code `BLD104` for duplicate operation names, in one document or across
  documents, and for names that map to the same output file; generated
  operation files record their source document in a `// Source:` line
- Unknown keys in `graphql_codegen.yaml` are reported as warnings, with a
  suggestion for likely typos

### Fixed
- Lists of enums with escaped values (e.g. `[Role!]` containing `default`)
  failed to parse: `json_serializable` didn't know the GraphQL names.
  Escaped values now carry `@JsonValue`
- The usage hint in `index.dart` showed an invalid `package:your_app/lib/...`
  import and a made-up operation; it now shows the real `package:` URI

### Deprecated
- Public helpers the generator no longer uses, to be removed in 3.0:
  `TypeGenerator.generateClassForType`, `generateTypeDefinitions` and
  `getDartTypeFromOriginal`; `OperationAnalyzer.getOperationReturnType`,
  `getOperationFieldName`, `hasSkipDirective` and `getSkippableFields`;
  `SchemaAnalyzer.extractCustomScalars`, `getSchemaType`,
  `mapSchemaTypeToDartType`, `isScalarType` and `mapGraphQLTypeToDartType`;
  `GraphQLCodeGenerator.generateCode` (use `generateOperationFile`)

## [2.0.0] - 2026-10-10

### Breaking changes and migration

- Typed `*Data` methods throw `OperationException` on GraphQL or network
  errors instead of returning `null`. Wrap calls in `try`/`on
  OperationException` if you relied on `null`.
- An operation that selects several root fields now returns an
  `<Operation>Result` object instead of only the first field.
- Custom scalar wrapper classes store the received JSON in `raw`; `value` is
  still a `String`. `MyScalar('text')` keeps working.
- `DateTimeConverter.toJson` and `LocalDateConverter.toJson` return `dynamic`.
- Unknown enum values throw `ArgumentError` instead of `Exception`.
- The placeholder `Awesome` class was removed.
- Generated object types that implement interfaces or belong to unions now
  declare `implements ...`.

### Added
- Config options `strict_nullability`, `file_naming`, `emit_index`,
  `diagnostics_format` and `scalar_mapping`
- Structured error codes (`CFG*`, `SCH*`, `BLD*`) with plain or JSON output
- Deterministic output: sorted types, fields and enum values, files written
  only when their content changes
- Operations are parsed with the `gql` AST parser instead of regular
  expressions
- Interfaces and unions: generated as abstract classes whose `fromJson`
  dispatches on `__typename`, with `Unknown<Name>` fallbacks; object types
  `implements` their interfaces and unions
- Typed `<Operation>Variables` classes with `toJson()` (enums, dates, custom
  scalars and input types are serialized; unset optional variables are omitted)
- Public `<operation>Document` / `<operation>OperationName` constants and
  `parse<Operation>Data` functions, usable with `watchQuery`, custom fetch
  policies, etc.
- Operations with several root fields return a `<Operation>Result` class
- Fragments defined in other `.graphql` files (matched by `document_paths`)
- `__typename` is added to every selection set of generated documents
- Schema extensions (`extend type`, `extend enum`, ...) are merged
- `schema_headers` config option (with `${ENV_VAR}` expansion) and an
  introspection fallback (converted to SDL) for remote schemas
- New error codes `BLD101` (unknown fragment), `BLD102` (conflicting fragment),
  `BLD103` (unknown root field)
- Test that compiles generated code (json_serializable + `dart analyze`) and
  runs it against a fake link

### Fixed
- Subscriptions now compile: they return `Stream`s via `GraphQLClient.subscribe`
  (previously `SubscriptionOptions` were passed to `query`)
- Generated code for schemas with unions no longer fails json_serializable
- Every operation in a document is generated, not only the first one
- Aliased root fields are read from the alias key
- Dart reserved words and clashing names are escaped (`class` -> `class_`,
  enum value `default` -> `default_`), keeping the GraphQL name on the wire
- Typed `*Data` methods no longer swallow errors and return `null`;
  `OperationException` (with `graphqlErrors`) is thrown instead
- `@skip`/`@include` and other directives are kept when printing operations
- Files whose path contains `schema.graphql` (e.g. `get_schema.graphql`) are
  no longer skipped; schema files are detected by their content
- The schema is loaded and `types.dart` generated once per build instead of
  once per operation file; local schemas are read through the build system so
  editing them triggers a rebuild
- Remote schema downloads have a 30s timeout; failures list every attempt
- `_dateTimeListToJson` now serializes in UTC like `DateTimeConverter`
- Builder output uses `log` instead of `print` (which build_runner reported as
  warnings)
- Generated files no longer produce analyzer warnings in user projects
- `dart analyze --fatal-infos` passes again
- Cross-platform path handling (Windows/macOS/Linux) in the builder and schema
  downloader, including `file://` URIs and `index.dart` exports

### Changed
- Custom scalar wrapper classes keep the raw JSON value (`raw`); `value` is the
  string form (JSON-encoded for non-string values). The constructor accepts any
  JSON value
- `DateTimeConverter.toJson` / `LocalDateConverter.toJson` return `dynamic`
- Unknown enum values throw `ArgumentError` instead of `Exception`
- `Decimal`, `Long`, `Byte` and custom scalar classes implement `==`/`hashCode`
- Mapped scalars (`scalar_mapping`) no longer get a generated wrapper class

### Removed
- Placeholder `Awesome` class

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
