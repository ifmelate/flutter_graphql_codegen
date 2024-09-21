class Operation {
  final String name;
  final String type;

  Operation(this.name, this.type);
}

List<Operation> parseOperations(String documentContent) {
  final operations = <Operation>[];
  final regex = RegExp(r'(query|mutation|subscription)\s+(\w+)');

  final matches = regex.allMatches(documentContent);

  for (final match in matches) {
    final type = match.group(1)!;
    final name = match.group(2)!;
    operations.add(Operation(name, type));
  }

  return operations;
}
