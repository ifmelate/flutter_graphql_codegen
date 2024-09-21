import 'package:yaml/yaml.dart' as yaml;

class GraphQLCodegenConfig {
  final String schemaUrl;
  final String outputDir;
  final List<String> documents;

  GraphQLCodegenConfig({
    required this.schemaUrl,
    required this.outputDir,
    this.documents = const [],
  });

  factory GraphQLCodegenConfig.fromYaml(String yamlString) {
    final yamlMap = yaml.loadYaml(yamlString) as yaml.YamlMap;
    return GraphQLCodegenConfig(
      schemaUrl: yamlMap['schema_url'] as String? ?? '',
      outputDir: yamlMap['output_dir'] as String? ?? '',
      documents: _parseDocuments(yamlMap['documents']),
    );
  }

  static List<String> _parseDocuments(dynamic documents) {
    if (documents == null) return [];
    if (documents is String) return [documents];
    if (documents is Iterable)
      return documents.map((e) => e.toString()).toList();
    return [];
  }
}
