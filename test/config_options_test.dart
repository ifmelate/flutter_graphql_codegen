import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/config.dart';

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
  });
}
