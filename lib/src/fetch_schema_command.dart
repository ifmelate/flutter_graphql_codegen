/// `dart run flutter_graphql_codegen:fetch_schema`: downloads the schema from
/// an endpoint into a local file, so builds work offline and the schema is
/// versioned with the code.
library;

import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'diagnostics.dart';
import 'schema_downloader.dart';

/// Exit code for wrong usage or configuration.
const int _usageError = 64;

/// Runs the command with [args]; returns the process exit code.
Future<int> runFetchSchema(
  List<String> args, {
  StringSink? stdout,
  StringSink? stderr,
}) async {
  final out = stdout ?? io.stdout;
  final err = stderr ?? io.stderr;

  final parser = ArgParser()
    ..addOption('config',
        defaultsTo: 'graphql_codegen.yaml',
        help: 'Config file with schema_endpoint, schema_url and '
            'schema_headers.')
    ..addOption('endpoint',
        help: 'GraphQL endpoint to download from (overrides '
            'schema_endpoint).')
    ..addOption('output',
        help: 'File to write the schema to (overrides schema_url).')
    ..addMultiOption('header',
        help: 'Extra HTTP header as "Name: value"; \${ENV_VAR} is expanded.',
        splitCommas: false)
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  void usage(String message) {
    err
      ..writeln(message)
      ..writeln()
      ..writeln('Usage: dart run flutter_graphql_codegen:fetch_schema '
          '[options]')
      ..writeln(parser.usage);
  }

  final ArgResults options;
  try {
    options = parser.parse(args);
  } on FormatException catch (e) {
    usage(e.message);
    return _usageError;
  }
  if (options['help'] as bool) {
    out
      ..writeln('Downloads the GraphQL schema into a local file.')
      ..writeln()
      ..writeln(parser.usage);
    return 0;
  }

  final configPath = options['config'] as String;
  GraphQLCodegenConfig? config;
  if (io.File(configPath).existsSync()) {
    try {
      config =
          GraphQLCodegenConfig.fromYaml(io.File(configPath).readAsStringSync());
    } on CodegenException catch (e) {
      err.writeln(e.toString());
      return _usageError;
    }
  }

  final configUrl = config?.schemaUrl;
  final configIsRemote = configUrl != null && _isHttp(configUrl);
  final endpoint = options['endpoint'] as String? ??
      config?.schemaEndpoint ??
      (configIsRemote ? configUrl : null);
  final output =
      options['output'] as String? ?? (configIsRemote ? null : configUrl);

  if (endpoint == null) {
    usage(config == null
        ? 'No endpoint: $configPath not found and --endpoint not given.'
        : 'No endpoint: set schema_endpoint in $configPath or pass '
            '--endpoint.');
    return _usageError;
  }
  if (!_isHttp(endpoint)) {
    usage('The endpoint must be an http(s) URL: $endpoint');
    return _usageError;
  }
  if (options['output'] == null &&
      output != null &&
      output.startsWith('package:')) {
    usage('schema_url in $configPath is a package: URI ($output); fetch the '
        'schema in that package or pass --output.');
    return _usageError;
  }
  if (output == null) {
    usage(config == null
        ? 'No output file: pass --output.'
        : 'No output file: schema_url in $configPath is a URL; pass --output '
            'or point schema_url to a local file and set schema_endpoint.');
    return _usageError;
  }

  final headers = {...?config?.schemaHeaders};
  for (final header in options['header'] as List<String>) {
    final colon = header.indexOf(':');
    if (colon <= 0) {
      usage('Invalid --header "$header": expected "Name: value".');
      return _usageError;
    }
    try {
      headers[header.substring(0, colon).trim()] =
          GraphQLCodegenConfig.expandEnvironmentVariables(
              header.substring(colon + 1).trim());
    } on CodegenException catch (e) {
      usage(e.message);
      return _usageError;
    }
  }

  final String schema;
  try {
    schema = await SchemaDownloader.downloadSchema(endpoint, headers: headers);
  } on CodegenException catch (e) {
    err.writeln(e.toString());
    return 1;
  }

  final file = io.File(
      output.startsWith('file://') ? p.fromUri(Uri.parse(output)) : output);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(schema.endsWith('\n') ? schema : '$schema\n');

  final types = gql_lang
      .parseString(schema)
      .definitions
      .whereType<TypeDefinitionNode>()
      .length;
  out.writeln('Wrote the schema from $endpoint to $output ($types types).');
  return 0;
}

bool _isHttp(String url) =>
    url.startsWith('http://') || url.startsWith('https://');
