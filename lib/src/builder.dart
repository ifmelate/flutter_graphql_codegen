import 'dart:io';

import 'package:build/build.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/schema_downloader.dart';
import 'config.dart';
import 'package:yaml/yaml.dart' as yaml;

class GraphQLCodegenBuilder implements Builder {
  final GraphQLCodegenConfig config;

  GraphQLCodegenBuilder(this.config);

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    List<String> documents = [];
    print('BuildStep of graphql codegen: ${buildStep.inputId}');
    // if (inputId.extension == '.schema.graphql') {
    // This is the schema file
    final schemaUrl = await buildStep.readAsString(inputId);
    print('Downloading schema from $schemaUrl');
    final schema = await SchemaDownloader.downloadSchema(schemaUrl);
    print('Graphql Schema downloaded from ${schemaUrl}');
    final documentPaths = config.resolveDocumentPaths();
    documents = await Future.wait(
        documentPaths.map((path) => File(path).readAsString()));
    final generatedCode =
        GraphQLCodeGenerator.generateClientCode(schema, documents);
    final outputId =
        AssetId(inputId.package, '${config.outputDir}/generated_client.dart');
    await buildStep.writeAsString(outputId, generatedCode);
    // } else if (inputId.extension == '.graphql') {
    // This is a document file
    // print('Reading document from ${inputId}');
    // final document = await buildStep.readAsString(inputId);
    // documents.add(document);
    // We don't generate individual files for documents in this setup
    // }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': ['generated_client.dart'],
      };
}

Builder graphqlCodegenBuilder(BuilderOptions options) {
  final configPath = options.config['config_path'] as String?;
  if (configPath == null) {
    throw ArgumentError('Missing config_path in builder options');
  }

  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    throw FileSystemException('Config file not found', configPath);
  }

  final yamlString = configFile.readAsStringSync();

  try {
    final config = GraphQLCodegenConfig.fromYaml(yamlString);
    return GraphQLCodegenBuilder(config);
  } catch (e, stackTrace) {
    print('Error parsing config: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}
