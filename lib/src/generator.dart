class GraphQLCodeGenerator {
  static String generateClientCode(String schema, List<String> documents) {
    String generatedOperations = _generateOperations(schema, documents);
    String generatedTypes = _generateTypes(schema);

    return '''
import 'package:graphql/graphql.dart';

$generatedTypes

class GeneratedGraphQLClient {
  final GraphQLClient _client;

  GeneratedGraphQLClient(String url)
      : _client = GraphQLClient(
          link: HttpLink(url),
          cache: GraphQLCache(),
        );

  $generatedOperations
}
''';
  }

  static String _generateOperations(String schema, List<String> documents) {
    return documents.map((doc) {
      final opType = _getOperationType(doc);
      final opName = _getOperationName(doc);
      final returnType = _getOperationReturnType(doc, schema);

      return '''
  Future<$returnType> $opName([Map<String, dynamic>? variables]) async {
    final result = await _client.$opType(
      ${opType.capitalize()}Options(
        document: gql(r"""$doc"""),
        variables: variables ?? const {},
      ),
    );
    if (result.hasException) {
      throw result.exception!;
    }
    return $returnType.fromJson(result.data!);
  }
''';
    }).join('\n');
  }

  static String _generateTypes(String schema) {
    // This is a placeholder. You'll need to implement actual type generation based on the schema.
    return '''
class SomeType {
  final String id;
  final String name;

  SomeType({required this.id, required this.name});

  factory SomeType.fromJson(Map<String, dynamic> json) {
    return SomeType(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
''';
  }

  static String _getOperationType(String document) {
    if (document.trim().startsWith('query')) return 'query';
    if (document.trim().startsWith('mutation')) return 'mutate';
    throw ArgumentError('Unknown operation type in document: $document');
  }

  static String _getOperationName(String document) {
    final match = RegExp(r'(query|mutation)\s+(\w+)').firstMatch(document);
    return match?.group(2) ?? 'UnnamedOperation';
  }

  static String _getOperationReturnType(String document, String schema) {
    // This is a placeholder. You'll need to implement logic to determine the return type based on the operation and schema.
    return 'SomeType';
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
