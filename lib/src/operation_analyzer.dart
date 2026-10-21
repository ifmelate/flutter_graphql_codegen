/// Operation analysis utilities for GraphQL code generation
library;

/// Utility class for analyzing GraphQL operations
class OperationAnalyzer {
  /// Extracts defined types from generated types content
  static Set<String> extractDefinedTypes(String typesContent) {
    final definedTypes = <String>{};
    final classRegex = RegExp(r'class\s+(\w+)');
    final matches = classRegex.allMatches(typesContent);
    for (final match in matches) {
      definedTypes.add(match.group(1)!);
    }
    return definedTypes;
  }
}
