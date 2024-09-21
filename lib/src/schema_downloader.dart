import 'package:http/http.dart' as http;
import 'dart:convert';

class SchemaDownloader {
  static Future<String> downloadSchema(String baseUrl) async {
    final url = Uri.parse(baseUrl).replace(queryParameters: {'sdl': ''});

    final response = await http.get(url);

    if (response.statusCode == 200) {
      // Проверяем, начинается ли содержимое с типичных ключевых слов SDL
      if (response.body.trim().startsWith('type') ||
          response.body.trim().startsWith('schema') ||
          response.body.trim().startsWith('directive')) {
        return response.body;
      } else {
        throw FormatException(
            'Received content does not appear to be a GraphQL SDL.');
      }
    } else {
      throw Exception(
          'Failed to download schema: ${response.statusCode}. Response: ${response.body}');
    }
  }

  static Future<String> downloadSchemaUsingIntrospectionQuery(
      String url) async {
    final introspectionQuery = '''
      query IntrospectionQuery {
        __schema {
          queryType { name }
          mutationType { name }
          subscriptionType { name }
          types {
            ...FullType
          }
          directives {
            name
            description
            locations
            args {
              ...InputValue
            }
          }
        }
      }

      fragment FullType on __Type {
        kind
        name
        description
        fields(includeDeprecated: true) {
          name
          description
          args {
            ...InputValue
          }
          type {
            ...TypeRef
          }
          isDeprecated
          deprecationReason
        }
        inputFields {
          ...InputValue
        }
        interfaces {
          ...TypeRef
        }
        enumValues(includeDeprecated: true) {
          name
          description
          isDeprecated
          deprecationReason
        }
        possibleTypes {
          ...TypeRef
        }
      }

      fragment InputValue on __InputValue {
        name
        description
        type { ...TypeRef }
        defaultValue
      }

      fragment TypeRef on __Type {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                    ofType {
                      kind
                      name
                    }
                  }
                }
              }
            }
          }
        }
      }
    ''';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'query': introspectionQuery,
      }),
    );

    final jsonResponse = json.decode(response.body);

    if (jsonResponse['errors'] != null) {
      throw Exception(
          'Failed to download schema: ${response.statusCode}. Errors: ${jsonResponse['errors']}');
    }
    if (response.statusCode == 200) {
      return json.encode(jsonResponse['data']);
    } else {
      throw Exception(
          'Failed to download schema: ${response.statusCode}. Response: ${response.body}');
    }
  }
}
