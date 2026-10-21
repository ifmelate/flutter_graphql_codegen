import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

const _schema = r'''
enum Role { ADMIN GUEST }
type User { role: Role! roles: [Role!]! }
type Query { me: User }
''';

void main() {
  tearDown(CodegenConfigContext.reset);

  test('unknown_enum_fallback is off by default and parsed from config', () {
    const base = '''
schema_url: schema.graphql
document_paths: [a.graphql]
''';
    expect(GraphQLCodegenConfig.fromYaml(base).unknownEnumFallback, isFalse);
    expect(
      GraphQLCodegenConfig.fromYaml('${base}unknown_enum_fallback: true\n')
          .unknownEnumFallback,
      isTrue,
    );
  });

  test('without the option unknown values throw', () {
    final types = TypeGenerator.generateTypesFile(_schema);
    expect(types, isNot(contains(r'$unknown')));
    expect(types, contains("throw ArgumentError.value(json, 'json'"));
  });

  group('with unknown_enum_fallback', () {
    late String types;

    setUp(() {
      CodegenConfigContext.unknownEnumFallback = true;
      types = TypeGenerator.generateTypesFile(_schema);
    });

    test(r'adds a $unknown value', () {
      expect(types, contains(r'  $unknown,' '\n}'));
    });

    test(r'the converter maps unknown values to $unknown', () {
      expect(types, contains(r'default: return Role.$unknown;'));
    });

    test(r'the converter refuses to serialize $unknown', () {
      expect(types, contains(r'case Role.$unknown: throw ArgumentError'));
    });

    test(r'enum lists fall back to $unknown', () {
      // json_serializable decodes the enum lists of `result_types: schema`.
      CodegenConfigContext.resultTypes = 'schema';
      expect(TypeGenerator.generateTypesFile(_schema),
          contains(r'unknownEnumValue: Role.$unknown'));
    });
  });
}
