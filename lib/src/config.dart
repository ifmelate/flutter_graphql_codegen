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

  GraphQLCodegenConfig({
    required this.schemaUrl,
    required this.outputDir,
    required this.documentPaths,
    this.fileNaming = 'snake_case',
    this.strictNullability = false,
    this.emitIndex = true,
    this.diagnosticsFormat = 'plain',
    Map<String, String>? scalarMapping,
  }) : scalarMapping = scalarMapping ?? const {};

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

      // Handle different schema source types:
      // 1. HTTP/HTTPS URLs - use as is
      // 2. Local file paths - can use as is (downloader will handle)
      // 3. file:// URLs - use as is
      print('📋 Config: schema source = $schemaUrl');

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

      return GraphQLCodegenConfig(
        schemaUrl: schemaUrl,
        outputDir: outputDir,
        documentPaths: documentPaths.map((e) => e as String).toList(),
        fileNaming: fileNaming,
        strictNullability: strictNullability,
        emitIndex: emitIndex,
        diagnosticsFormat: diagnosticsFormat,
        scalarMapping: scalarMappingMap,
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

  List<dynamic> resolveDocumentPaths() {
    return documentPaths.expand((path) {
      final glob = Glob(path);
      return glob.listSync().whereType<File>().map((file) => file.path);
    }).toList();
  }
}
