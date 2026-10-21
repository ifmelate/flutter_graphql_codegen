// types.dart with `result_types: operation` (the default): no result classes,
// hand-written input classes.
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

const _schema = r'''
scalar JSON
scalar DateTime

interface Node { id: ID! }

type User implements Node { id: ID! name: String role: Role! roles: [Role!] }

type Post implements Node { id: ID! }

union Hit = User | Post

enum Role { ADMIN default }

"""
Filter for users.
"""
input UserFilter {
  "Exact name."
  name: String
  nick: String @deprecated(reason: "Use 'name'")
  role: Role!
  roles: [Role!]
  since: DateTime
  meta: JSON
  page: Page
}

input Page { first: Int! after: String }

type Query { users(filter: UserFilter): [User!]! hits: [Hit!]! node: Node }
''';

void main() {
  late String types;

  setUp(() {
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
    types = TypeGenerator.generateTypesFile(_schema);
  });
  tearDown(CodegenConfigContext.reset);

  test('declares no classes for object types, interfaces and unions', () {
    expect(types, isNot(contains('class User ')));
    expect(types, isNot(contains('class Post ')));
    expect(types, isNot(contains('class Node ')));
    expect(types, isNot(contains('class Hit ')));
    expect(types, isNot(contains('class Unknown')));
    expect(types, contains("'Hit': {'Post', 'User'},"));
    expect(types, contains("'Node': {'Post', 'User'},"));
  });

  test('keeps scalars, enums, converters and the equality helpers', () {
    expect(types, contains('class JSON {'));
    expect(types, contains('class JSONConverter '));
    expect(types, contains('enum Role {'));
    expect(types, contains('class RoleConverter '));
    expect(types, contains('bool graphqlDeepEquals('));
    expect(types, contains('int graphqlDeepHash('));
    expect(types,
        contains("import 'package:json_annotation/json_annotation.dart';"));
  });

  test('needs no json_serializable', () {
    expect(types, isNot(contains('@JsonSerializable')));
    expect(types, isNot(contains('@JsonKey')));
    expect(types, isNot(contains('part ')));
    expect(types, isNot(contains(r'_$')));
  });

  test('input classes are immutable with a const constructor', () {
    expect(types, contains('class UserFilter {'));
    expect(types, contains('  final String? name;'));
    expect(types, contains('  final Role role;'));
    expect(types, contains('  final List<Role>? roles;'));
    expect(types, contains('  const UserFilter({'));
    expect(types, contains('    required this.role,'));
    expect(types, contains('    this.name,'));
    // A nullable list stays null: `[]` would mean "none of these".
    expect(types, contains('    this.roles,'));
    expect(types, isNot(contains('    this.roles = const [],')));
    expect(types, contains('  factory UserFilter.fromJson('));
    expect(types, contains('  Map<String, dynamic> toJson() => {'));
  });

  test('toJson leaves null fields out', () {
    expect(
        types, contains("        if (name case final value?) 'name': value,"));
    expect(
        types, contains("        'role': const RoleConverter().toJson(role),"));
    expect(
        types,
        contains("        if (page case final value?) 'page': "
            'value.toJson(),'));
  });

  test('with include_null_inputs toJson writes null fields', () {
    CodegenConfigContext.includeNullInputs = true;
    final out = TypeGenerator.generateTypesFile(_schema);
    expect(out, contains("        'name': name,"));
    expect(
        out,
        contains("        'page': switch (page) "
            '{ final value? => value.toJson(), null => null },'));
  });

  test('value equality, deep for lists', () {
    expect(types, contains('  bool operator ==(Object other) =>'));
    expect(types, contains('graphqlDeepEquals(roles, other.roles)'));
    expect(types, contains('          name == other.name'));
    expect(types, contains('        graphqlDeepHash(roles),'));
  });

  test('typed copyWith that can set null', () {
    expect(
        types,
        contains(
            '  UserFilter_CopyWith get copyWith => _UserFilter_CopyWith(this);'));
    expect(types, contains('abstract class UserFilter_CopyWith {'));
    expect(types, contains('    Role? role,'));
    expect(types, contains('    Object? name = _undefined,'));
    expect(
        types,
        contains('role: identical(role, _undefined) ? _value.role : '
            'role as Role,'));
    expect('const _undefined = Object();'.allMatches(types), hasLength(1));
  });

  test('doc comments and deprecations as in schema result types', () {
    expect(types, contains('/// Filter for users.\nclass UserFilter {'));
    expect(types, contains('  /// Exact name.\n  final String? name;'));
    expect(
        types, contains("  /// Deprecated: Use 'name'\n  final String? nick;"));
    CodegenConfigContext.deprecatedAnnotations = true;
    expect(TypeGenerator.generateTypesFile(_schema),
        contains("  @Deprecated('Use \\'name\\'')\n  final String? nick;"));
  });

  test('no helpers for result classes, also with unknown_enum_fallback', () {
    CodegenConfigContext.unknownEnumFallback = true;
    final out = TypeGenerator.generateTypesFile(_schema);
    expect(out, contains(r'  $unknown,'));
    expect(out, isNot(contains('_enumRaw')));
    expect(out, isNot(contains('_Nullable')));
    expect(out, isNot(contains('Raw;')));
  });

  test('schemas without inputs declare no _undefined', () {
    final out = TypeGenerator.generateTypesFile('type Query { a: Int }');
    expect(out, isNot(contains('_undefined')));
    expect(out, isNot(contains('class Query')));
  });

  test('fields added by input extensions count', () {
    final out = TypeGenerator.generateTypesFile('''
type Query { a(f: F): Int }
input F { x: Int }
extend input F { y: Int }
''');
    expect(out, contains('  final int? y;'));
  });

  test('members avoid field names', () {
    final out = TypeGenerator.generateTypesFile('''
type Query { a(f: F): Int }
input F { other: Int value: Int copyWith: Int }
''');
    expect(out, contains('  bool operator ==(Object other_) =>'));
    expect(out, contains("if (value case final value_?) 'value': value_,"));
    // A field named copyWith takes the place of the copy getter.
    expect(out, isNot(contains('F_CopyWith')));
  });

  test('schema result types keep json_serializable input classes', () {
    CodegenConfigContext.resultTypes = 'schema';
    final out = TypeGenerator.generateTypesFile(_schema);
    expect(out, contains("part 'types.g.dart';"));
    expect(out, contains('class User implements Hit, Node {'));
    expect(out, contains('@JsonSerializable(includeIfNull: false'));
    expect(out, isNot(contains('UserFilter_CopyWith')));
  });
}
