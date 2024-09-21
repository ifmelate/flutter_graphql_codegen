import 'dart:io';

import 'package:build/build.dart';
import 'config.dart';
import 'package:yaml/yaml.dart' as yaml;

class GraphQLCodegenBuilder implements Builder {
  final GraphQLCodegenConfig config;

  GraphQLCodegenBuilder(this.config);

  @override
  Future<void> build(BuildStep buildStep) async {
    // ... (оставьте остальной код без изменений)
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
  final yamlConfig = yaml.loadYaml(yamlString);

  // Используйте yamlConfig для настройки вашего билдера
  return GraphQLCodegenBuilder(GraphQLCodegenConfig.fromYaml(yamlConfig));
}
