import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class SchemaDownloader {
  /// Downloads GraphQL schema from URL or reads from local file
  /// Supports:
  /// - HTTP/HTTPS URLs: http://example.com/graphql, https://api.example.com/graphql
  /// - Local file paths: schema.graphql, lib/graphql/schema.graphql
  /// - File URLs: file:///path/to/schema.graphql
  static Future<String> downloadSchema(String schemaSource) async {
    print('📥 Loading GraphQL schema from: $schemaSource');

    // Handle HTTP/HTTPS URLs
    if (schemaSource.startsWith('http://') ||
        schemaSource.startsWith('https://')) {
      return await _downloadFromUrl(schemaSource);
    }

    // Handle local files (both file:// URLs and direct paths)
    return await _readFromLocalFile(schemaSource);
  }

  /// Downloads schema from HTTP/HTTPS URL
  static Future<String> _downloadFromUrl(String url) async {
    try {
      print('🌐 Downloading schema from HTTP URL: $url');

      // Try direct SDL endpoint first
      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200 && _isValidGraphQLSchema(response.body)) {
        print('✅ Successfully downloaded schema from direct SDL endpoint');
        return response.body;
      }

      // If direct SDL didn't work, try with ?sdl parameter
      final urlWithSdl = Uri.parse(url).replace(queryParameters: {'sdl': ''});
      response = await http.get(urlWithSdl);

      if (response.statusCode == 200) {
        if (_isValidGraphQLSchema(response.body)) {
          print('✅ Successfully downloaded schema with ?sdl parameter');
          return response.body;
        } else {
          throw FormatException(
            'Received content does not appear to be a valid GraphQL SDL schema.',
          );
        }
      } else {
        throw Exception(
          'Failed to download schema: HTTP ${response.statusCode}. Response: ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error downloading schema from URL: $e');
      rethrow;
    }
  }

  /// Reads schema from local file
  static Future<String> _readFromLocalFile(String filePath) async {
    try {
      // Handle file:// URLs and normalize cross-platform paths
      String actualPath;
      if (filePath.startsWith('file://')) {
        actualPath = p.fromUri(Uri.parse(filePath));
        print('📂 Reading schema from file:// URL: $actualPath');
      } else {
        actualPath = p.normalize(filePath);
        print('📂 Reading schema from local file: $actualPath');
      }

      final file = File(actualPath);

      if (!await file.exists()) {
        throw FileSystemException('Schema file not found', actualPath);
      }

      final content = await file.readAsString();

      if (content.trim().isEmpty) {
        throw FormatException('Schema file is empty: $actualPath');
      }

      if (!_isValidGraphQLSchema(content)) {
        throw FormatException(
            'File does not contain a valid GraphQL schema: $actualPath');
      }

      print('✅ Successfully read schema from local file');
      return content;
    } catch (e) {
      print('❌ Error reading schema from file: $e');
      rethrow;
    }
  }

  /// Validates if content is a valid GraphQL schema
  static bool _isValidGraphQLSchema(String content) {
    final trimmedContent = content.trim();

    if (trimmedContent.isEmpty) return false;

    // Check for common GraphQL schema keywords
    return trimmedContent.contains('type ') ||
        trimmedContent.contains('interface ') ||
        trimmedContent.contains('union ') ||
        trimmedContent.contains('enum ') ||
        trimmedContent.contains('input ') ||
        trimmedContent.contains('scalar ') ||
        trimmedContent.contains('schema ') ||
        trimmedContent.contains('directive ') ||
        // Check for comments that might precede actual schema
        (trimmedContent.startsWith('#') &&
            (trimmedContent.contains('type ') ||
                trimmedContent.contains('schema ')));
  }

  static Future<String> downloadSchemaUsingIntrospectionQuery(
    String url,
  ) async {
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
      body: json.encode({'query': introspectionQuery}),
    );

    final jsonResponse = json.decode(response.body);

    if (jsonResponse['errors'] != null) {
      throw Exception(
        'Failed to download schema: ${response.statusCode}. Errors: ${jsonResponse['errors']}',
      );
    }
    if (response.statusCode == 200) {
      return json.encode(jsonResponse['data']);
    } else {
      throw Exception(
        'Failed to download schema: ${response.statusCode}. Response: ${response.body}',
      );
    }
  }
}
