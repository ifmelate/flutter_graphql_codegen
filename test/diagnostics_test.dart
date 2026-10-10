import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';

void main() {
  group('Diagnostics and error codes', () {
    test('missing schema triggers CFG001', () {
      const yaml = '''
output_dir: out
document_paths: ["test/fixtures/*.graphql"]
''';
      expect(
        () => GraphQLCodegenConfig.fromYaml(yaml),
        throwsA(isA<CodegenException>()
            .having((e) => e.code, 'code', CodegenErrorCodes.cfgMissingSchema)),
      );
    });

    test('missing documents triggers CFG002', () {
      const yaml = 'schema_url: test/fixtures/schema.graphql';
      expect(
        () => GraphQLCodegenConfig.fromYaml(yaml),
        throwsA(isA<CodegenException>().having(
            (e) => e.code, 'code', CodegenErrorCodes.cfgMissingDocuments)),
      );
    });
  });
}
