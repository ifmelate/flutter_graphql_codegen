import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;
import 'config.dart';
import 'generator.dart';
import 'schema_downloader.dart';

class GraphQLCodegenBuilder implements Builder {
  final GraphQLCodegenConfig config;

  GraphQLCodegenBuilder(this.config);

  @override
  Future<void> build(BuildStep buildStep) async {
    final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);
    final graphqlFiles = buildStep.findAssets(Glob('**/*.graphql'));

    final documents = await Future.wait(graphqlFiles.map((asset) async {
      final content = await buildStep.readAsString(asset);
      return content;
    }));

    final generatedCode =
        GraphQLCodeGenerator.generateClientCode(schema, documents);

    final outputId = AssetId(
      buildStep.inputId.package,
      path.join(config.outputDir, 'generated_client.dart'),
    );

    await buildStep.writeAsString(outputId, generatedCode);
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': ['generated_client.dart'],
      };
}
