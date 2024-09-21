import 'package:yaml/yaml.dart';

class GraphQLCodegenConfig {
  final String schemaUrl;
  final String outputDir;

  GraphQLCodegenConfig({required this.schemaUrl, required this.outputDir});

  factory GraphQLCodegenConfig.fromYaml(String yamlString) {
    final yaml = loadYaml(yamlString);
    return GraphQLCodegenConfig(
      schemaUrl: yaml['schema_url'],
      outputDir: yaml['output_dir'],
    );
  }
}
