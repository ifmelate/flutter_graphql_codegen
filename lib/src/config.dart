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

  /// HTTP headers sent when downloading a remote schema. Values may reference
  /// environment variables as `${NAME}`.
  final Map<String, String> schemaHeaders;

  GraphQLCodegenConfig({
    required this.schemaUrl,
    required this.outputDir,
    required this.documentPaths,
    this.fileNaming = 'snake_case',
    this.strictNullability = false,
    this.emitIndex = true,
    this.diagnosticsFormat = 'plain',
    Map<String, String>? scalarMapping,
    Map<String, String>? schemaHeaders,
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
        scalarMapping: scalarMappingMap,
        schemaHeaders: schemaHeaders,
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
