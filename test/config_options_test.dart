import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';

void main() {
  group('Config parsing', () {
    test('parses extended options', () {
      const yaml = '''
schema_url: test/fixtures/schema.graphql
output_dir: test/generated
document_paths:
  - test/fixtures/*.graphql
file_naming: kebab-case
strict_nullability: true
emit_index: false
diagnostics_format: json
scalar_mapping:
  Date: DateTime
  Decimal: Decimal
''';

      final cfg = GraphQLCodegenConfig.fromYaml(yaml);
      expect(cfg.fileNaming, 'kebab-case');
      expect(cfg.strictNullability, isTrue);
      expect(cfg.emitIndex, isFalse);
      expect(cfg.diagnosticsFormat, 'json');
      expect(cfg.scalarMapping['Date'], 'DateTime');
    });

    test('parses schema_headers and expands environment variables', () {
      expect(
        GraphQLCodegenConfig.expandEnvironmentVariables(
            r'Bearer ${TOKEN}', {'TOKEN': 'abc'}),
        'Bearer abc',
      );
      expect(
        () => GraphQLCodegenConfig.expandEnvironmentVariables(
            r'Bearer ${MISSING_FGC_TOKEN}', {}),
        throwsA(isA<CodegenException>().having(
            (e) => e.message, 'message', contains('MISSING_FGC_TOKEN'))),
      );

      const yaml = '''
schema_url: https://example.com/graphql
document_paths:
  - lib/**.graphql
schema_headers:
  X-Api-Key: plain-value
''';
      final cfg = GraphQLCodegenConfig.fromYaml(yaml);
      expect(cfg.schemaHeaders, {'X-Api-Key': 'plain-value'});
    });

    test('rejects non-map schema_headers', () {
      const yaml = '''
schema_url: https://example.com/graphql
document_paths:
  - lib/**.graphql
schema_headers: nope
''';
      expect(() => GraphQLCodegenConfig.fromYaml(yaml),
          throwsA(isA<CodegenException>()));
    });
  });
}
