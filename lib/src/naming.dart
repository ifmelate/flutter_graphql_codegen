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
