import 'dart:io';

import 'package:build/build.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/schema_downloader.dart';
import 'package:flutter_graphql_codegen/src/utils.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'config.dart';
import 'package:path/path.dart' as path;

class GraphQLCodegenBuilder implements Builder {
  final GraphQLCodegenConfig config;

  GraphQLCodegenBuilder(this.config);
  Future<void> _writeFile(String filePath, String content) async {
    final directory = Directory(path.dirname(filePath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await File(filePath).writeAsString(content);
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    List<String> documents = [];
    print('BuildStep of graphql codegen: ${buildStep.inputId}');
    // if (inputId.extension == '.schema.graphql') {
    // This is the schema file
    final schemaUrl = config.schemaUrl;
    print('Downloading schema from $schemaUrl');
    final schema = await SchemaDownloader.downloadSchema(schemaUrl);
    print('Graphql Schema downloaded from $schemaUrl');

    // Generate types file
    final typesCode = GraphQLCodeGenerator.generateTypesFile(schema);
    final typesOutputPath = '${config.outputDir}/types.dart';
    await _writeFile(typesOutputPath, typesCode);
    print('Generated types file: $typesOutputPath');

    // Process each document
    final documentPaths = await _resolveDocumentPaths(config.documentPaths);
    print('Found ${documentPaths.length} Graphql Documents');
    if (documentPaths.isEmpty) {
      throw Exception('No Graphql Documents found');
    }

    final typesContent = await File(typesOutputPath).readAsString();

    for (final documentPath in documentPaths) {
      final documentContent = await File(documentPath).readAsString();
      final operations = parseOperations(documentContent);

      for (final operation in operations) {
        final operationCode = GraphQLCodeGenerator.generateOperationFile(schema,
            documentContent, operation.name, operation.type, typesContent);

        final outputFileName = '${operation.name.toLowerCase()}_graphql.dart';
        print('Generating GraphQL client $outputFileName');
        final outputPath = '${config.outputDir}/$outputFileName';
        await _writeFile(outputPath, operationCode);
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
