class GraphQLOperation {
  final String name;
  final String type;
  final String content;

  GraphQLOperation(
      {required this.name, required this.type, required this.content});
}

class GraphQLParser {
  static List<GraphQLOperation> parseOperations(String document) {
    final regex = RegExp(
        r'(query|mutation|subscription)\s+(\w+)?\s*($$[\s\S]*?$$)?\s*\{([\s\S]*?)\}',
        multiLine: true);
    final matches = regex.allMatches(document);

    return matches.map((match) {
      final type = match.group(1) ?? 'query';
      final name = match.group(2) ?? 'Anonymous';
      final variables = match.group(3) ?? '';
      final content = match.group(4) ?? '';

      return GraphQLOperation(
        name: name,
        type: type,
        content: '$type $name$variables {\n$content\n}',
      );
    }).toList();
  }
}
