import 'package:yaml/yaml.dart';

class GraphQLCodegenConfig {
  final String schemaUrl;
  final String outputDir;
  final List<String> includes;

  GraphQLCodegenConfig({
    required this.schemaUrl,
    required this.outputDir,
    required this.includes,
  });

  factory GraphQLCodegenConfig.fromYaml(String yamlString) {
    final yaml = loadYaml(yamlString);
    return GraphQLCodegenConfig(
      schemaUrl: yaml['schema_url'],
      outputDir: yaml['output_dir'],
      includes: List<String>.from(yaml['includes']),
    );
  }
}
