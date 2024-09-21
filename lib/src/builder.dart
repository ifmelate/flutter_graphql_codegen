import 'dart:io';

import 'package:build/build.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/schema_downloader.dart';
import 'package:flutter_graphql_codegen/src/utils.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
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
    final schemaUrl = this.config.schemaUrl;
    print('Downloading schema from $schemaUrl');
    final schema = await SchemaDownloader.downloadSchema(schemaUrl);
    print('Graphql Schema downloaded from ${schemaUrl}');

    /* final generatedCode =
        GraphQLCodeGenerator.generateClientCode(schema, documents);
        */
    // Process each document
    final documentPaths = await _resolveDocumentPaths(config.documentPaths);

    for (final documentPath in documentPaths) {
      final documentContent = await File(documentPath).readAsString();
      final operations = parseOperations(documentContent);

      for (final operation in operations) {
        final generatedCode = GraphQLCodeGenerator.generateOperationCode(
          schema,
          documentContent,
          operation.name,
          operation.type,
        );

        final outputFileName = '${operation.name}_graphql_client.dart';
        final outputPath = '${config.outputDir}/$outputFileName';
        await File(outputPath).writeAsString(generatedCode);
        print('Generated: $outputPath');
      }
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': ['generated_client.dart'],
      };
}

Future<List<String>> _resolveDocumentPaths(List<String> patterns) async {
  final resolvedPaths = <String>[];
  for (final pattern in patterns) {
    final glob = Glob(pattern);
    await for (final entity in glob.list()) {
      if (entity is File) {
        resolvedPaths.add(entity.path);
      }
    }
  }
  return resolvedPaths;
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
