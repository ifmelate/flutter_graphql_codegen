library;

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

/// Members every Dart object has; a generated field with one of these names
/// would clash with (or accidentally override) them.
const Set<String> _objectMemberNames = {
  'hashCode', 'runtimeType', 'toString', 'noSuchMethod', //
};

/// Members that a generated JSON class declares itself.
const Set<String> _generatedClassMemberNames = {'toJson', 'fromJson'};

/// Members every Dart enum has.
const Set<String> _enumMemberNames = {'values', 'index', 'name'};

/// Returns a valid Dart identifier for a GraphQL field or variable name.
///
/// Reserved words and names that clash with built-in members get a trailing
/// underscore (`class` -> `class_`). [className] guards against a member having
/// the same name as its enclosing class, which Dart does not allow.
String dartFieldName(String graphqlName, {String? className}) {
  if (dartReservedWords.contains(graphqlName) ||
      _objectMemberNames.contains(graphqlName) ||
      _generatedClassMemberNames.contains(graphqlName) ||
      graphqlName == className) {
    return '${graphqlName}_';
  }
  return graphqlName;
}

/// Returns a valid Dart identifier for a GraphQL enum value.
String dartEnumValueName(String graphqlValue) {
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
