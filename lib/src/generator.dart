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

extension ${operationName.capitalize()}Extension on GraphQLClient {
  Future<QueryResult<Object?>> ${operationName.decapitalize()}([Map<String, dynamic>? variables]) async {
    final options = $optionsType(
      document: gql("""
$documentContent
      """),
      variables: variables ?? const {},
    );

    final result = await $methodName(options);

    if (result.hasException) {
      throw result.exception!;
    }

    return result;
  }

  Future<Map<String, dynamic>?> ${operationName.decapitalize()}Data([Map<String, dynamic>? variables]) async {
    final result = await ${operationName.decapitalize()}(variables);
    return result.data;
  }
}
''';
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }

  String decapitalize() {
    return "${this[0].toLowerCase()}${this.substring(1)}";
  }
}
