import 'package:build/build.dart';
import 'config.dart';

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
  final yamlString = options.config['graphql_codegen'] as String?;
  if (yamlString == null) {
    throw ArgumentError('Missing configuration for GraphQLCodegenBuilder');
  }
  return GraphQLCodegenBuilder(GraphQLCodegenConfig.fromYaml(yamlString));
}
