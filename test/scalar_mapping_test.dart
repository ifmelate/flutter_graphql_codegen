import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

const _base = 'schema_url: s.graphql\ndocument_paths: [a.graphql]\n';

const _schema = r'''
scalar Money
scalar Cents
scalar Date
type Item { price: Money! prices: [Money!]! cents: Cents! day: Date! }
input ItemInput { price: Money! cents: Cents day: Date }
type Query { item(day: Date!, price: Money, input: ItemInput): Item! }
''';

void _configure() {
  CodegenConfigContext.scalarMapping = {
    'Money': 'Money',
    'Cents': 'Cents',
    'Date': 'DateTime',
  };
  CodegenConfigContext.scalarImports = {
    'Money': 'package:app/money.dart',
    'Cents': 'package:app/money.dart',
  };
  CodegenConfigContext.scalarConverters = {'Money': 'MoneyConverter'};
}

void main() {
  setUp(CodegenConfigContext.reset);
  tearDown(CodegenConfigContext.reset);

  group('config', () {
    test('accepts the long form with import and converter', () {
      final cfg = GraphQLCodegenConfig.fromYaml('''
${_base}scalar_mapping:
  Date: DateTime
  Money:
    type: Money
    import: package:app/money.dart
    converter: MoneyConverter
''');
      expect(cfg.scalarMapping, {'Date': 'DateTime', 'Money': 'Money'});
      expect(cfg.scalarImports, {'Money': 'package:app/money.dart'});
      expect(cfg.scalarConverters, {'Money': 'MoneyConverter'});
      expect(cfg.warnings, isEmpty);
    });

    test('the long form needs a type', () {
      expect(
        () => GraphQLCodegenConfig.fromYaml(
            '${_base}scalar_mapping:\n  Money:\n    import: package:a/b.dart\n'),
        throwsA(isA<CodegenException>()
            .having((e) => e.code, 'code', CodegenErrorCodes.cfgInvalid)
            .having((e) => e.message, 'message',
                allOf(contains('Money'), contains('type')))),
      );
    });

    test('unknown keys in the long form are warned about', () {
      final cfg = GraphQLCodegenConfig.fromYaml(
          '${_base}scalar_mapping:\n  Money:\n    type: Money\n    imprt: x\n');
      expect(cfg.warnings, contains(contains('imprt')));
    });

    test('strict_scalars defaults to false', () {
      expect(GraphQLCodegenConfig.fromYaml(_base).strictScalars, isFalse);
      expect(
          GraphQLCodegenConfig.fromYaml('${_base}strict_scalars: true\n')
              .strictScalars,
          isTrue);
    });
  });

  group('types.dart', () {
    late String types;
    setUp(() {
      _configure();
      // Covers the json_serializable classes of `result_types: schema`.
      CodegenConfigContext.resultTypes = 'schema';
      types = TypeGenerator.generateTypesFile(_schema);
    });

    test('imports the mapped types once', () {
      expect("import 'package:app/money.dart';".allMatches(types).length, 1);
    });

    test('uses the converter on fields and lists', () {
      expect(types, contains('  @MoneyConverter()\n  Money price;'));
      expect(types, contains('  @MoneyConverter()\n  List<Money>? prices;'));
    });

    test('generates no wrapper for mapped scalars', () {
      expect(types, isNot(contains('class Money')));
      expect(types, isNot(contains('class Cents')));
    });
  });

  group('operation files', () {
    late String code;
    setUp(() {
      _configure();
      final types = TypeGenerator.generateTypesFile(_schema);
      code = GraphQLCodeGenerator.generateOperationFile(
          _schema,
          r'query GetItem($day: Date!, $price: Money, $input: ItemInput) '
              r'{ item(day: $day, price: $price, input: $input) { price cents } }',
          'GetItem',
          'query',
          types);
    });

    test('import the mapped types', () {
      expect(code, contains("import 'package:app/money.dart';"));
    });

    test('serialize variables through converters and toJson', () {
      expect(code, contains("'day': const DateTimeConverter().toJson(day)"));
      expect(code, contains('const MoneyConverter().toJson(price!)'));
    });

    test('parse root fields through the converter', () {
      CodegenConfigContext.scalarMapping = {'Money': 'Money'};
      CodegenConfigContext.scalarConverters = {'Money': 'MoneyConverter'};
      const schema = 'scalar Money\ntype Query { total: Money! cents: Cents }'
          '\nscalar Cents';
      CodegenConfigContext.scalarMapping['Cents'] = 'Cents';
      final types = TypeGenerator.generateTypesFile(schema);
      final out = GraphQLCodeGenerator.generateOperationFile(
          schema, 'query T { total cents }', 'T', 'query', types);
      expect(out, contains("const MoneyConverter().fromJson(data['total'])"));
      expect(out, contains("Cents.fromJson(data['cents'])"));
    });
  });

  group('strict_scalars', () {
    test('fails for custom scalars without a mapping', () {
      CodegenConfigContext.strictScalars = true;
      expect(
        () => TypeGenerator.generateTypesFile(
            'scalar JSON\nscalar Url\nscalar DateTime\n'
            'type Query { a: JSON b: Url c: DateTime }'),
        throwsA(isA<CodegenException>()
            .having((e) => e.code, 'code', 'SCH401')
            .having(
                (e) => e.message,
                'message',
                allOf(contains('JSON'), contains('Url'),
                    isNot(contains('DateTime'))))),
      );
    });

    test('accepts mapped and built-in scalars', () {
      CodegenConfigContext.resultTypes = 'schema';
      CodegenConfigContext.strictScalars = true;
      CodegenConfigContext.scalarMapping = {'JSON': 'Map<String, dynamic>'};
      expect(
          TypeGenerator.generateTypesFile(
              'scalar JSON\nscalar Decimal\ntype Query { a: JSON b: Decimal }'),
          contains('Map<String, dynamic>? a;'));
    });
  });
}
