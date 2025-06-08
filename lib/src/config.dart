import 'dart:io';
import 'package:glob/list_local_fs.dart';
import 'package:yaml/yaml.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart' as yaml;

class GraphQLCodegenConfig {
  final String schemaUrl;
  final String outputDir;
  final List<String> documentPaths;

  GraphQLCodegenConfig({
    required this.schemaUrl,
    required this.outputDir,
    required this.documentPaths,
  });

  factory GraphQLCodegenConfig.fromYaml(String yamlString) {
    try {
      final yamlMap = yaml.loadYaml(yamlString) as yaml.YamlMap;

      var schemaUrl =
          yamlMap['schema_url'] as String? ?? yamlMap['schema'] as String?;

      if (schemaUrl == null) {
        throw ArgumentError('Missing schema_url or schema in configuration');
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
        throw ArgumentError(
            'Missing document_paths or documents in configuration');
      }

      return GraphQLCodegenConfig(
        schemaUrl: schemaUrl,
        outputDir: outputDir,
        documentPaths: documentPaths.map((e) => e as String).toList(),
      );
    } catch (e) {
      print('❌ Error parsing GraphQL codegen config: $e');
      rethrow;
    }
  }

  List<dynamic> resolveDocumentPaths() {
    return documentPaths.expand((path) {
      final glob = Glob(path);
      return glob.listSync().whereType<File>().map((file) => file.path);
    }).toList();
  }
}
