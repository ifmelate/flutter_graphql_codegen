import 'package:graphql/client.dart';

class GraphQLCodeGenerator {
  static String generateOperationCode(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
  ) {
    final methodName =
        operationType.toLowerCase() == 'mutation' ? 'mutate' : 'query';
    final optionsType = operationType.capitalize() + 'Options';

    return '''
import 'package:graphql/client.dart';

class ${operationName}GraphQLClient {
  final GraphQLClient client;

  ${operationName}GraphQLClient(this.client);

  Future<QueryResult<Object?>> execute([Map<String, dynamic>? variables]) async {
    final options = $optionsType(
      document: gql(r"""
$documentContent
      """),
      variables: variables ?? const {},
    );

    final result = await client.$methodName(options);

    if (result.hasException) {
      throw result.exception!;
    }

    return result;
  }

   Future<Map<String, dynamic>?> get data => execute().then((result) => result.data);
}
''';
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
