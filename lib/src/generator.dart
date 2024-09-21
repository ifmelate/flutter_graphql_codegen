class GraphQLCodeGenerator {
  static String generateOperationCode(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
  ) {
    return '''
import 'package:graphql/graphql.dart';

class ${operationName}GraphQLClient {
  final GraphQLClient client;

  ${operationName}GraphQLClient(this.client);

  Future<Map<String, dynamic>> execute([Map<String, dynamic>? variables]) async {
    final result = await client.${operationType.toLowerCase()}(
      ${operationType.capitalize()}Options(
        document: gql(r"""
$documentContent
        """),
        variables: variables ?? const {},
      ),
    );

    if (result.hasException) {
      throw result.exception!;
    }

    return result.data!;
  }
}
''';
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
