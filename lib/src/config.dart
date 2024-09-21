import 'dart:io';
import 'package:glob/list_local_fs.dart';
import 'package:yaml/yaml.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart' as yaml;

class GraphQLCodegenConfig {
  final String schemaPath;
  final String outputDir;
  final List<String> documentPaths;

  GraphQLCodegenConfig({
    required this.schemaPath,
    required this.outputDir,
    required this.documentPaths,
  });

  factory GraphQLCodegenConfig.fromYaml(String yamlString) {
    final yamlMap = yaml.loadYaml(yamlString) as yaml.YamlMap;
    print('Loaded YAML: $yamlMap');

    return GraphQLCodegenConfig(
      schemaPath: yamlMap['schema_url'] as String,
      outputDir: yamlMap['output_dir'] as String,
      documentPaths: (yamlMap['document_paths'] as YamlList)
          .map((e) => e as String)
          .toList(),
    );
  }

  List<dynamic> resolveDocumentPaths() {
    return documentPaths.expand((path) {
      final glob = Glob(path);
      return glob.listSync().whereType<File>().map((file) => file.path);
    }).toList();
  }
}
