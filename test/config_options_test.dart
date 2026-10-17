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
      expect(cfg.deprecatedAnnotations, isFalse);
      expect(
        GraphQLCodegenConfig.fromYaml('${yaml}deprecated_annotations: true\n')
            .deprecatedAnnotations,
        isTrue,
      );
    });

    test('warns about unknown keys and suggests the closest option', () {
      final cfg = GraphQLCodegenConfig.fromYaml('''
schema_url: schema.graphql
document_paths: [a.graphql]
strict_nulability: true
something_else: 1
''');
      expect(cfg.strictNullability, isFalse);
      expect(cfg.warnings, hasLength(2));
      expect(
          cfg.warnings,
          contains(allOf(contains('strict_nulability'),
              contains('did you mean "strict_nullability"'))));
      expect(
          cfg.warnings,
          contains(allOf(
              contains('something_else'), isNot(contains('did you mean')))));
    });

    test('accepts every documented key without warnings', () {
      final cfg = GraphQLCodegenConfig.fromYaml('''
schema: schema.graphql
documents: [a.graphql]
output_dir: out
strict_nullability: true
file_naming: snake_case
emit_index: true
scalar_mapping: {}
schema_headers: {}
diagnostics_format: plain
unknown_enum_fallback: true
deprecated_annotations: true
validate_documents: true
strict_scalars: false
schema_endpoint: https://example.com/graphql
''');
      expect(cfg.warnings, isEmpty);
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
