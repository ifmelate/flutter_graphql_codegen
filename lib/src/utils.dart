import 'parser.dart';

class Operation {
  final String name;
  final String type;

  Operation(this.name, this.type);
}

/// Returns the named operations (name + `query`/`mutation`/`subscription`)
/// declared in [documentContent].
///
/// Uses the GraphQL parser, so keywords inside strings, comments or field
/// names are not mistaken for operations.
List<Operation> parseOperations(String documentContent) {
  return [
    for (final op in GraphQLParser.parseOperations(documentContent))
      if (op.name != 'Anonymous') Operation(op.name, op.type),
  ];
}
