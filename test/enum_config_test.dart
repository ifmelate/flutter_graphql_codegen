// The `enums:` option: enums mapped to user types and per-enum fallbacks.
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

const _schema = r'''
enum Role { ADMIN GUEST }
enum Status { ACTIVE OTHER default }
type User { role: Role! roles: [Role] status: Status statuses: [Status!]! }
input UserFilter { role: Role status: Status }
type Query { me: User users(role: Role, filter: UserFilter): [User!]! }
''';

const _role = EnumConfig(
  type: 'AppRole',
  import: 'package:app/role.dart',
  fromJson: 'roleFromJson',
  toJson: 'roleToJson',
);

const _yaml = '''
schema_url: schema.graphql
document_paths: [a.graphql]
''';

String _op(String document, String name) {
  final types = GraphQLCodeGenerator.generateTypesFile(_schema);
  return GraphQLCodeGenerator.generateOperationFile(
      _schema, document, name, 'query', types);
}

Matcher _cfgError(Object message) => throwsA(isA<CodegenException>()
    .having((e) => e.code, 'code', CodegenErrorCodes.cfgInvalid)
    .having((e) => e.message, 'message', message));

void main() {
  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
  });
  tearDown(CodegenConfigContext.reset);

  group('config', () {
    test('parses type, import, functions and fallback', () {
      final cfg = GraphQLCodegenConfig.fromYaml('''
${_yaml}enums:
  Role: {type: AppRole, import: "package:app/role.dart", from_json: roleFromJson, to_json: roleToJson}
  Status: {fallback: OTHER}
''');
      final role = cfg.enums['Role']!;
      expect(role.type, 'AppRole');
      expect(role.import, 'package:app/role.dart');
      expect(role.fromJson, 'roleFromJson');
      expect(role.toJson, 'roleToJson');
      expect(cfg.enums['Status']!.fallback, 'OTHER');
    });

    test('a type needs from_json and to_json', () {
      expect(
          () => GraphQLCodegenConfig.fromYaml('''
${_yaml}enums:
  Role: {type: AppRole, from_json: roleFromJson}
'''),
          _cfgError(contains(
              'enums.Role: type "AppRole" needs from_json and to_json')));
    });

    test('functions and import need a type', () {
      expect(() => GraphQLCodegenConfig.fromYaml('''
${_yaml}enums:
  Role: {import: "package:app/role.dart", to_json: roleToJson}
'''), _cfgError(contains('enums.Role: import, to_json need a type')));
    });

    test('fallback and type exclude each other', () {
      expect(() => GraphQLCodegenConfig.fromYaml('''
${_yaml}enums:
  Role: {type: AppRole, from_json: f, to_json: t, fallback: GUEST}
'''), _cfgError(contains("fallback can't be combined with type")));
    });
  });

  group('validation against the schema', () {
    test('unknown enum', () {
      CodegenConfigContext.enumConfigs = {
        'Rol': const EnumConfig(fallback: 'ADMIN'),
      };
      expect(
          () => TypeGenerator.generateTypesFile(_schema),
          _cfgError(contains(
              'enums.Rol: the schema has no enum "Rol" (enums: Role, Status)')));
    });

    test('a type that is not an enum', () {
      CodegenConfigContext.enumConfigs = {
        'User': const EnumConfig(fallback: 'ADMIN'),
      };
      expect(
          () => TypeGenerator.generateTypesFile(_schema),
          _cfgError(
              contains('enums.User: "User" is an object type, not an enum')));
    });

    test('unknown fallback value', () {
      CodegenConfigContext.enumConfigs = {
        'Status': const EnumConfig(fallback: 'NEW'),
      };
      expect(
          () => TypeGenerator.generateTypesFile(_schema),
          _cfgError(contains('enums.Status: fallback "NEW" is not a value of '
              'Status (values: ACTIVE, OTHER, default)')));
    });

    test('operation files are checked too', () {
      CodegenConfigContext.enumConfigs = {'Nope': const EnumConfig()};
      expect(
          () => GraphQLCodeGenerator.generateOperationFile(
              _schema, 'query A { me { role } }', 'A', 'query', ''),
          _cfgError(contains('enums.Nope')));
    });

    test('problems are reported together', () {
      CodegenConfigContext.enumConfigs = {
        'A': const EnumConfig(),
        'Status': const EnumConfig(fallback: 'X'),
      };
      expect(() => TypeGenerator.generateTypesFile(_schema),
          _cfgError(allOf(contains('enums.A'), contains('enums.Status'))));
    });
  });

  group('custom type', () {
    late String types;

    setUp(() {
      CodegenConfigContext.enumConfigs = {'Role': _role};
      types = TypeGenerator.generateTypesFile(_schema);
    });

    test('no Dart enum; a converter calling the functions', () {
      expect(types, isNot(contains('enum Role ')));
      expect(types, contains('enum Status {'));
      expect(
          types,
          contains(
              'class RoleConverter extends JsonConverter<AppRole, String> {'));
      expect(types,
          contains('  AppRole fromJson(String json) => roleFromJson(json);'));
      expect(types,
          contains('  String toJson(AppRole object) => roleToJson(object);'));
    });

    test('the library is imported by types.dart and operation files', () {
      expect(types, contains("import 'package:app/role.dart';"));
      final op = _op('query A { me { role } }', 'A');
      expect(op, contains("import 'package:app/role.dart';"));
    });

    test('input fields and variables use the type', () {
      expect(types, contains('  final AppRole? role;'));
      expect(
          types,
          contains("if (role case final value?) 'role': "
              'const RoleConverter().toJson(value)'));
      final op = _op(r'query A($r: Role) { users(role: $r) { role } }', 'A');
      expect(op, contains('  final AppRole? r;'));
      expect(op, contains("'r': const RoleConverter().toJson(r!)"));
    });

    test('result fields use the type, without a Raw sibling', () {
      CodegenConfigContext.unknownEnumFallback = true;
      final op = _op('query A { me { role roles status } }', 'A');
      expect(op, contains('  final AppRole role;'));
      expect(op, contains('  final List<AppRole?>? roles;'));
      expect(
          op,
          contains("role: const RoleConverter().fromJson(json['role'] "
              'as String),'));
      expect(op, contains("'role': const RoleConverter().toJson(role),"));
      expect(op, isNot(contains('roleRaw')));
      expect(op, contains('statusRaw'), reason: r'Status still has $unknown');
    });

    test('a fragment named like the type gets an underscore', () {
      const fragment = 'fragment AppRole on User { role }';
      final code = GraphQLCodeGenerator.generateFragmentsFile(_schema,
          DocumentUtils.collectFragments([gql_lang.parseString(fragment)]));
      expect(code, contains('abstract interface class AppRole_ '));
    });

    test('schema result types decode lists with the converter', () {
      CodegenConfigContext.resultTypes = 'schema';
      final out = TypeGenerator.generateTypesFile(_schema);
      expect(out, contains('  @RoleConverter()\n  AppRole role;'));
      expect(out,
          contains('  @_NullableRoleConverter()\n  List<AppRole?>? roles;'));
      expect(
          out,
          contains('class _NullableRoleConverter implements '
              'JsonConverter<AppRole?, dynamic> {'));
    });
  });

  group('fallback', () {
    setUp(() {
      CodegenConfigContext.enumConfigs = {
        'Status': const EnumConfig(fallback: 'OTHER'),
      };
    });

    test('unknown values decode to the fallback', () {
      final types = TypeGenerator.generateTypesFile(_schema);
      expect(types, contains('      default: return Status.OTHER;'));
      expect(
          types,
          contains("default: throw ArgumentError.value(json, 'json', "
              "'Unknown Role value');"));
    });

    test(r'overrides unknown_enum_fallback: no $unknown for that enum', () {
      CodegenConfigContext.unknownEnumFallback = true;
      final types = TypeGenerator.generateTypesFile(_schema);
      expect(types, contains(r'default: return Role.$unknown;'));
      expect(types, isNot(contains(r'Status.$unknown')));
      expect(types, contains('      default: return Status.OTHER;'));
    });

    test('result fields get a Raw sibling written back to the cache', () {
      final op = _op('query A { me { status statuses role } }', 'A');
      expect(op, contains('  final String? statusRaw;'));
      expect(op, contains('  final List<String?>? statusesRaw;'));
      expect(
          op,
          contains('as the server sent it, also when it was decoded as '
              'the fallback `OTHER`.'));
      expect(
          op,
          contains("'status': statusRaw != null && "
              'const StatusConverter().fromJson(statusRaw!) == status '
              '? statusRaw : status == null ? null : '
              'const StatusConverter().toJson(status!),'));
      expect(op, isNot(contains('roleRaw')));
    });

    test('schema result types: lists fall back too', () {
      CodegenConfigContext.resultTypes = 'schema';
      final out = TypeGenerator.generateTypesFile(_schema);
      expect(out, contains('unknownEnumValue: Status.OTHER'));
      expect(out, contains('  String? statusRaw;'));
      expect(out, isNot(contains('roleRaw')));
    });
  });
}
