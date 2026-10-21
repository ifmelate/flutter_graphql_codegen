library;

import 'code_utils.dart';

String toSnakeCase(String input) {
  return input
      .replaceAllMapped(RegExp(r'(?<!^)(?=[A-Z])'), (m) => '_')
      .toLowerCase();
}

String toKebabCase(String input) {
  return input
      .replaceAllMapped(RegExp(r'(?<!^)(?=[A-Z])'), (m) => '-')
      .toLowerCase();
}

String toCamelCaseFromPascal(String input) {
  if (input.isEmpty) return input;
  return input[0].toLowerCase() + input.substring(1);
}

String toPascalCase(String input) {
  if (input.isEmpty) return input;
  final parts = input.split(RegExp(r'[_\-\s]+'));
  return parts
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join('');
}

/// Dart reserved words that can never be used as identifiers.
const Set<String> dartReservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

/// Names the generated code refers to without a prefix (dart:core and
/// json_annotation types, built-in helper classes). A schema type with one of
/// these names would shadow them, so its Dart name gets a trailing underscore.
const Set<String> reservedTypeNames = {
  'Map', 'List', 'Set', 'String', 'Object', 'int', 'double', 'num', 'bool', //
  'dynamic', 'DateTime', 'Future', 'Stream', 'ArgumentError', 'StateError',
  // Typed options take a `Duration? pollInterval`.
  'Duration',
  // `enum Enum` would also get a converter named like the built-in one.
  'Enum',
  'Deprecated', 'override', 'JsonConverter', 'JsonSerializable', 'JsonKey',
  'JsonValue', 'FieldRename', 'Decimal', 'Long', 'Byte', 'EnumConverter',
  'DecimalConverter', 'DateTimeConverter', 'LocalDateConverter',
  'LongConverter', 'ByteConverter', 'SafeStringConverter', 'SafeBoolConverter',
  'SafeIntConverter', 'SafeDoubleConverter', 'SafeDecimalConverter',
};

/// Members every Dart object has; a generated field with one of these names
/// would clash with (or accidentally override) them.
const Set<String> _objectMemberNames = {
  'hashCode', 'runtimeType', 'toString', 'noSuchMethod', //
};

/// Members that a generated JSON class declares itself.
const Set<String> _generatedClassMemberNames = {'toJson', 'fromJson'};

/// Members every Dart enum has.
const Set<String> _enumMemberNames = {'values', 'index', 'name'};

/// Leading underscores make a Dart name private, which a named parameter can't
/// be, so they move to the end (`_id` -> `id_`).
String? _publicName(String graphqlName) {
  if (!graphqlName.startsWith('_')) return null;
  final stripped = graphqlName.replaceFirst(RegExp('^_+'), '');
  final suffix = '_' * (graphqlName.length - stripped.length);
  return stripped.isEmpty ? 'value$suffix' : '$stripped$suffix';
}

/// Whether [name] is a Dart type the generated code may refer to. A member
/// with that name would shadow the type inside its class (`Media? Media;`).
bool _isTypeName(String name) {
  if (reservedTypeNames.contains(name) || TypeRegistry.declaresType(name)) {
    return true;
  }
  // Escaped Dart name of a schema type such as `Map` -> `Map_`.
  if (!name.endsWith('_')) return false;
  final base = name.substring(0, name.length - 1);
  return reservedTypeNames.contains(base) && TypeRegistry.declaresType(base);
}

/// Returns a valid Dart identifier for a GraphQL field or variable name.
///
/// Reserved words and names that clash with built-in members or types get a
/// trailing underscore (`class` -> `class_`, `int` -> `int_`), and leading
/// underscores move to the end (`_id` -> `id_`). [className] guards against a
/// member having the same name as its enclosing class, which Dart does not
/// allow.
String dartFieldName(String graphqlName, {String? className}) {
  var name = _publicName(graphqlName) ?? graphqlName;
  if (name == graphqlName &&
      (dartReservedWords.contains(name) ||
          _objectMemberNames.contains(name) ||
          _generatedClassMemberNames.contains(name) ||
          name == className)) {
    name = '${name}_';
  }
  while (_isTypeName(name) || name == className) {
    name = '${name}_';
  }
  return name;
}

/// Returns a valid Dart identifier for a GraphQL enum value.
String dartEnumValueName(String graphqlValue) {
  final public = _publicName(graphqlValue);
  if (public != null) return public;
  if (dartReservedWords.contains(graphqlValue) ||
      _objectMemberNames.contains(graphqlValue) ||
      _enumMemberNames.contains(graphqlValue)) {
    return '${graphqlValue}_';
  }
  return graphqlValue;
}

String transformFileBaseName(String operationName, String mode) {
  switch (mode) {
    case 'snake_case':
      return toSnakeCase(operationName);
    case 'kebab-case':
      return toKebabCase(operationName);
    case 'camelCase':
      return toCamelCaseFromPascal(operationName);
    case 'PascalCase':
      return toPascalCase(operationName);
    default:
      return toSnakeCase(operationName);
  }
}
