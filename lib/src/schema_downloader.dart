import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart' show log;
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'diagnostics.dart';

class SchemaDownloader {
  /// Default timeout for every HTTP request made while fetching a schema.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Downloads GraphQL schema from URL or reads from local file
  /// Supports:
  /// - HTTP/HTTPS URLs: http://example.com/graphql, https://api.example.com/graphql
  /// - Local file paths: schema.graphql, lib/graphql/schema.graphql
  /// - File URLs: file:///path/to/schema.graphql
  ///
  /// For HTTP(S) sources the SDL is requested directly first, then with a
  /// `?sdl` query parameter, and finally via an introspection query whose
  /// result is converted to SDL. [headers] are sent with every request.
  static Future<String> downloadSchema(
    String schemaSource, {
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
  }) async {
    log.fine('Loading GraphQL schema from: $schemaSource');

    // Handle HTTP/HTTPS URLs
    if (schemaSource.startsWith('http://') ||
        schemaSource.startsWith('https://')) {
      return await _downloadFromUrl(schemaSource, headers, timeout);
    }

    // Handle local files (both file:// URLs and direct paths)
    return await _readFromLocalFile(schemaSource);
  }

  /// Downloads schema from HTTP/HTTPS URL
  static Future<String> _downloadFromUrl(
      String url, Map<String, String> headers, Duration timeout) async {
    final uri = Uri.parse(url);
    final failures = <String>[];

    Future<String?> trySdl(Uri target) async {
      try {
        final response =
            await http.get(target, headers: headers).timeout(timeout);
        if (response.statusCode == 200 &&
            _isValidGraphQLSchema(response.body)) {
          return response.body;
        }
        failures.add('GET $target -> HTTP ${response.statusCode}'
            '${response.statusCode == 200 ? ' (not SDL)' : ''}');
      } on TimeoutException {
        failures.add('GET $target -> timed out after ${timeout.inSeconds}s');
      } catch (e) {
        failures.add('GET $target -> $e');
      }
      return null;
    }

    final direct = await trySdl(uri);
    if (direct != null) return direct;

    final withSdl = await trySdl(
        uri.replace(queryParameters: {...uri.queryParameters, 'sdl': ''}));
    if (withSdl != null) return withSdl;

    try {
      final data = await _runIntrospection(url, headers, timeout);
      log.fine('Downloaded schema via introspection from $url');
      return introspectionToSdl(data);
    } catch (e) {
      failures.add('POST introspection -> $e');
    }

    throw CodegenException(
      CodegenErrorCodes.schemaDownloadFailed,
      'Could not download a GraphQL schema from $url:\n'
      '  ${failures.join('\n  ')}',
    );
  }

  /// Reads schema from local file
  static Future<String> _readFromLocalFile(String filePath) async {
    // Handle file:// URLs and normalize cross-platform paths
    final actualPath = filePath.startsWith('file://')
        ? p.fromUri(Uri.parse(filePath))
        : p.normalize(filePath);

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

    return content;
  }

  /// True if [content] parses as GraphQL and declares at least one type
  /// system definition (an HTML error page or a JSON body does not).
  static bool _isValidGraphQLSchema(String content) {
    if (content.trim().isEmpty) return false;
    try {
      final doc = gql_lang.parseString(content);
      return doc.definitions.any((d) => d is TypeSystemDefinitionNode);
    } catch (_) {
      return false;
    }
  }

  /// Runs the standard introspection query against [url] and returns the
  /// result's `data` encoded as JSON.
  static Future<String> downloadSchemaUsingIntrospectionQuery(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = defaultTimeout,
  }) async {
    return json.encode(await _runIntrospection(url, headers, timeout));
  }

  static Future<Map<String, dynamic>> _runIntrospection(
      String url, Map<String, String> headers, Duration timeout) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            ...headers,
          },
          body: json.encode({'query': introspectionQuery}),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw HttpException(
          'HTTP ${response.statusCode}: ${_truncate(response.body)}',
          uri: Uri.parse(url));
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Introspection response is not an object');
    }
    if (decoded['errors'] != null) {
      throw FormatException('Introspection errors: ${decoded['errors']}');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic> || data['__schema'] == null) {
      throw const FormatException('Introspection response has no __schema');
    }
    return data;
  }

  static String _truncate(String s) =>
      s.length <= 200 ? s : '${s.substring(0, 200)}...';

  /// Converts the `data` of an introspection query result into SDL.
  static String introspectionToSdl(Map<String, dynamic> data) {
    final schema = data['__schema'] as Map<String, dynamic>;
    final buffer = StringBuffer();

    String? rootName(String key) =>
        (schema[key] as Map<String, dynamic>?)?['name'] as String?;

    final roots = {
      'query': rootName('queryType'),
      'mutation': rootName('mutationType'),
      'subscription': rootName('subscriptionType'),
    }..removeWhere((_, v) => v == null);
    buffer.writeln('schema {');
    roots.forEach((op, name) => buffer.writeln('  $op: $name'));
    buffer.writeln('}');

    const builtInScalars = {'String', 'Int', 'Float', 'Boolean', 'ID'};
    final types = (schema['types'] as List).cast<Map<String, dynamic>>();

    for (final type in types) {
      final name = type['name'] as String;
      if (name.startsWith('__') || builtInScalars.contains(name)) continue;
      buffer.writeln();

      switch (type['kind']) {
        case 'SCALAR':
          buffer.writeln('scalar $name');
        case 'OBJECT':
        case 'INTERFACE':
          final keyword = type['kind'] == 'OBJECT' ? 'type' : 'interface';
          final interfaces = ((type['interfaces'] as List?) ?? const [])
              .map((i) => (i as Map<String, dynamic>)['name'])
              .toList();
          buffer.write('$keyword $name');
          if (interfaces.isNotEmpty) {
            buffer.write(' implements ${interfaces.join(' & ')}');
          }
          final fields = ((type['fields'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          if (fields.isEmpty) {
            buffer.writeln();
            break;
          }
          buffer.writeln(' {');
          for (final field in fields) {
            final args = ((field['args'] as List?) ?? const [])
                .cast<Map<String, dynamic>>();
            final argsSdl = args.isEmpty
                ? ''
                : '(${args.map(_inputValueToSdl).join(', ')})';
            buffer.writeln('  ${field['name']}$argsSdl: '
                '${_typeRefToSdl(field['type'] as Map<String, dynamic>)}'
                '${_deprecated(field)}');
          }
          buffer.writeln('}');
        case 'UNION':
          final members = ((type['possibleTypes'] as List?) ?? const [])
              .map((t) => (t as Map<String, dynamic>)['name'])
              .join(' | ');
          buffer.writeln('union $name = $members');
        case 'ENUM':
          buffer.writeln('enum $name {');
          for (final value in ((type['enumValues'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()) {
            buffer.writeln('  ${value['name']}${_deprecated(value)}');
          }
          buffer.writeln('}');
        case 'INPUT_OBJECT':
          final fields = ((type['inputFields'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          if (fields.isEmpty) {
            buffer.writeln('input $name');
            break;
          }
          buffer.writeln('input $name {');
          for (final field in fields) {
            buffer.writeln('  ${_inputValueToSdl(field)}');
          }
          buffer.writeln('}');
      }
    }

    return buffer.toString();
  }

  static String _inputValueToSdl(Map<String, dynamic> value) {
    final defaultValue = value['defaultValue'];
    return '${value['name']}: '
        '${_typeRefToSdl(value['type'] as Map<String, dynamic>)}'
        '${defaultValue != null ? ' = $defaultValue' : ''}';
  }

  static String _typeRefToSdl(Map<String, dynamic> ref) {
    switch (ref['kind']) {
      case 'NON_NULL':
        return '${_typeRefToSdl(ref['ofType'] as Map<String, dynamic>)}!';
      case 'LIST':
        return '[${_typeRefToSdl(ref['ofType'] as Map<String, dynamic>)}]';
      default:
        return ref['name'] as String;
    }
  }

  static String _deprecated(Map<String, dynamic> node) {
    if (node['isDeprecated'] != true) return '';
    final reason = node['deprecationReason'] as String?;
    if (reason == null) return ' @deprecated';
    return ' @deprecated(reason: ${json.encode(reason)})';
  }

  /// The standard introspection query.
  static const String introspectionQuery = '''
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
}
