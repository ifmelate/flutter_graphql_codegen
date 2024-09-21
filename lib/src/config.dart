import 'package:yaml/yaml.dart' as yaml;

class GraphQLCodegenConfig {
  final String schemaUrl;
  final String outputDir;
  final List<String> documents; // Предполагаем, что это поле вызывает ошибку

  GraphQLCodegenConfig({
    required this.schemaUrl,
    required this.outputDir,
    this.documents = const [], // Значение по умолчанию - пустой список
  });

  factory GraphQLCodegenConfig.fromYaml(String yamlString) {
    final yamlMap = yaml.loadYaml(yamlString) as yaml.YamlMap;
    return GraphQLCodegenConfig(
      schemaUrl: yamlMap['schema_url'] as String? ?? '',
      outputDir: yamlMap['output_dir'] as String? ?? '',
      documents: (yamlMap['documents'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}
