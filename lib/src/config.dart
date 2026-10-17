import 'dart:io';
import 'package:glob/list_local_fs.dart';
import 'package:yaml/yaml.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'diagnostics.dart';

class GraphQLCodegenConfig {
  final String schemaUrl;
  final String outputDir;
  final List<String> documentPaths;
  final String fileNaming; // snake_case | kebab-case | camelCase | pascalCase
  final bool strictNullability; // if true, keep strict nullability from schema
  final bool emitIndex; // whether to emit index.dart
  final String diagnosticsFormat; // plain | json
  final Map<String, String> scalarMapping; // GraphQL scalar -> Dart type

  /// Adds a `$unknown` value to every enum for values the server sends that
  /// were not in the schema at generation time (instead of throwing).
  final bool unknownEnumFallback;

  /// Emits `@Deprecated` for schema `@deprecated` fields and enum values
  /// (otherwise the deprecation is only mentioned in the doc comment).
  final bool deprecatedAnnotations;

  /// HTTP headers sent when downloading a remote schema. Values may reference
  /// environment variables as `${NAME}`.
  final Map<String, String> schemaHeaders;

  /// Problems in the configuration that do not stop generation (e.g. unknown
  /// keys); the builder logs them.
  final List<String> warnings;

  /// Keys understood in `graphql_codegen.yaml`.
  static const Set<String> knownKeys = {
    'schema_url', 'schema', 'document_paths', 'documents', 'output_dir', //
    'strict_nullability', 'file_naming', 'emit_index', 'scalar_mapping',
    'schema_headers', 'diagnostics_format', 'unknown_enum_fallback',
    'deprecated_annotations',
  };

  GraphQLCodegenConfig({
    required this.schemaUrl,
    required this.outputDir,
    required this.documentPaths,
    this.fileNaming = 'snake_case',
    this.strictNullability = false,
    this.emitIndex = true,
    this.diagnosticsFormat = 'plain',
    this.unknownEnumFallback = false,
    this.deprecatedAnnotations = false,
    Map<String, String>? scalarMapping,
    Map<String, String>? schemaHeaders,
    this.warnings = const [],
  })  : scalarMapping = scalarMapping ?? const {},
        schemaHeaders = schemaHeaders ?? const {};

  factory GraphQLCodegenConfig.fromYaml(String yamlString) {
    var diagFormat = 'plain';
    try {
      final yamlMap = yaml.loadYaml(yamlString) as yaml.YamlMap;

      var schemaUrl =
          yamlMap['schema_url'] as String? ?? yamlMap['schema'] as String?;

      if (schemaUrl == null) {
        throw CodegenException(
          CodegenErrorCodes.cfgMissingSchema,
          'Missing schema_url or schema in configuration',
        );
      }

      // Schema source may be an HTTP(S) URL, a local path or a file:// URL;
      // SchemaDownloader handles all of them.

      final outputDir =
          yamlMap['output_dir'] as String? ?? 'lib/graphql/generated';

      final documentPaths = yamlMap['document_paths'] as YamlList? ??
          yamlMap['documents'] as YamlList?;

      if (documentPaths == null) {
        throw CodegenException(
          CodegenErrorCodes.cfgMissingDocuments,
          'Missing document_paths or documents in configuration',
        );
      }

      // Optional settings
      const validFileNamingModes = {
        'snake_case',
        'kebab-case',
        'camelCase',
        'PascalCase',
      };
      final fileNaming =
          (yamlMap['file_naming'] as String?)?.trim() ?? 'snake_case';
      if (!validFileNamingModes.contains(fileNaming)) {
        throw CodegenException(
          CodegenErrorCodes.cfgInvalid,
          'Invalid file_naming "$fileNaming". '
          'Valid options: ${validFileNamingModes.join(', ')}',
        );
      }
      final strictNullability = yamlMap['strict_nullability'] as bool? ?? false;
      final emitIndex = yamlMap['emit_index'] as bool? ?? true;
      final unknownEnumFallback =
          yamlMap['unknown_enum_fallback'] as bool? ?? false;
      final deprecatedAnnotations =
          yamlMap['deprecated_annotations'] as bool? ?? false;
      diagFormat =
          (yamlMap['diagnostics_format'] as String?)?.trim() ?? 'plain';
      final diagnosticsFormat = diagFormat;

      // Scalar mapping
      final scalarMappingMap = <String, String>{};
      final yamlScalars = yamlMap['scalar_mapping'];
      if (yamlScalars is yaml.YamlMap) {
        for (final entry in yamlScalars.entries) {
          final k = entry.key?.toString();
          final v = entry.value?.toString();
          if (k != null && v != null) {
            scalarMappingMap[k] = v;
          }
        }
      }

      // Headers for remote schema download (e.g. auth)
      final schemaHeaders = <String, String>{};
      final yamlHeaders = yamlMap['schema_headers'];
      if (yamlHeaders is yaml.YamlMap) {
        for (final entry in yamlHeaders.entries) {
          final k = entry.key?.toString();
          final v = entry.value?.toString();
          if (k != null && v != null) {
            schemaHeaders[k] = expandEnvironmentVariables(v);
          }
        }
      } else if (yamlHeaders != null) {
        throw CodegenException(
          CodegenErrorCodes.cfgInvalid,
          'schema_headers must be a map of header name to value',
        );
      }

      return GraphQLCodegenConfig(
        schemaUrl: schemaUrl,
        outputDir: outputDir,
        documentPaths: documentPaths.map((e) => e as String).toList(),
        fileNaming: fileNaming,
        strictNullability: strictNullability,
        emitIndex: emitIndex,
        diagnosticsFormat: diagnosticsFormat,
        unknownEnumFallback: unknownEnumFallback,
        deprecatedAnnotations: deprecatedAnnotations,
        scalarMapping: scalarMappingMap,
        schemaHeaders: schemaHeaders,
        warnings: [
          for (final key in yamlMap.keys.map((k) => '$k'))
            if (!knownKeys.contains(key)) _unknownKeyWarning(key),
        ],
      );
    } catch (e) {
      if (e is CodegenException) {
        // Print structured error using configured diagnostics format
        print(e.format(format: diagFormat));
        rethrow;
      }
      print('❌ Error parsing GraphQL codegen config: $e');
      throw CodegenException(CodegenErrorCodes.cfgInvalid, e.toString(),
          cause: e);
    }
  }

  static String _unknownKeyWarning(String key) {
    String? closest;
    var best = 4; // suggest only near misses
    for (final known in knownKeys) {
      final distance = _editDistance(key, known);
      if (distance < best) {
        best = distance;
        closest = known;
      }
    }
    return 'Unknown option "$key" in graphql_codegen.yaml'
        '${closest == null ? '' : ' (did you mean "$closest"?)'}; it is ignored';
  }

  static int _editDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = [i, ...List<int>.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  /// Replaces `${NAME}` with the value of environment variable `NAME`.
  ///
  /// Throws a [CodegenException] when a referenced variable is not set, so a
  /// missing token fails loudly instead of sending an empty header.
  static String expandEnvironmentVariables(String value,
      [Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    return value.replaceAllMapped(RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'),
        (m) {
      final name = m.group(1)!;
      final resolved = env[name];
      if (resolved == null) {
        throw CodegenException(
          CodegenErrorCodes.cfgInvalid,
          'Environment variable "$name" referenced in schema_headers is not set',
        );
      }
      return resolved;
    });
  }

  List<String> resolveDocumentPaths() {
    return documentPaths.expand((path) {
      final glob = Glob(path);
      return glob.listSync().whereType<File>().map((file) => file.path);
    }).toList();
  }
}
