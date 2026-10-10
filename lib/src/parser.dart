import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

class GraphQLOperation {
  final String name;
  final String type; // query | mutation | subscription
  final String content; // full SDL of the operation

  GraphQLOperation(
      {required this.name, required this.type, required this.content});
}

class GraphQLParser {
  /// Parses GraphQL operations using the official gql AST parser for reliability
  static List<GraphQLOperation> parseOperations(String document) {
    final doc = gql_lang.parseString(document);
    final operations = <GraphQLOperation>[];

    for (final def in doc.definitions) {
      if (def is OperationDefinitionNode) {
        final typeString = _operationTypeToString(def.type);
        final opName = def.name?.value ?? 'Anonymous';

        // Print the operation back from the AST (keeps directives, aliases,
        // arguments, default values, etc.)
        final serialized = gql_lang.printNode(def);

        operations.add(GraphQLOperation(
          name: opName,
          type: typeString,
          content: serialized,
        ));
      }
    }

    return operations;
  }

  static String _operationTypeToString(OperationType t) {
    switch (t) {
      case OperationType.query:
        return 'query';
      case OperationType.mutation:
        return 'mutation';
      case OperationType.subscription:
        return 'subscription';
    }
  }
}
