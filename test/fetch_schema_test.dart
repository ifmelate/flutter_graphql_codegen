import 'dart:io';

import 'package:flutter_graphql_codegen/src/fetch_schema_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _sdl = 'type Query { hello: String }\n';

void main() {
  late HttpServer server;
  late Directory dir;
  late List<HttpHeaders> requests;
  late StringBuffer out;
  late StringBuffer err;
  late String endpoint;
  var status = 200;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fgc_fetch_');
    requests = [];
    out = StringBuffer();
    err = StringBuffer();
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = 'http://127.0.0.1:${server.port}/graphql';
    server.listen((request) {
      requests.add(request.headers);
      request.response
        ..statusCode = status
        ..write(status == 200 ? _sdl : 'nope')
        ..close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  String writeConfig(String body) {
    final path = p.join(dir.path, 'graphql_codegen.yaml');
    File(path).writeAsStringSync(body);
    return path;
  }

  Future<int> run(List<String> args) =>
      runFetchSchema(args, stdout: out, stderr: err);

  test('downloads from schema_endpoint into schema_url with schema_headers',
      () async {
    final output = p.join(dir.path, 'lib', 'schema.graphql');
    final config = writeConfig('''
schema_url: $output
schema_endpoint: $endpoint
schema_headers:
  Authorization: Bearer abc
document_paths: [lib/**.graphql]
''');

    expect(await run(['--config', config]), 0, reason: '$err');
    expect(File(output).readAsStringSync(), _sdl);
    expect(requests.single.value('authorization'), 'Bearer abc');
    expect(out.toString(), allOf(contains(endpoint), contains(output)));
  });

  test('--endpoint, --output and --header work without a config file',
      () async {
    final output = p.join(dir.path, 'schema.graphql');
    expect(
      await run([
        '--config', p.join(dir.path, 'missing.yaml'), //
        '--endpoint', endpoint,
        '--output', output,
        '--header', 'X-Api-Key: secret',
      ]),
      0,
      reason: '$err',
    );
    expect(File(output).readAsStringSync(), _sdl);
    expect(requests.single.value('x-api-key'), 'secret');
  });

  test('fails with usage help when there is no endpoint', () async {
    final config = writeConfig('''
schema_url: ${p.join(dir.path, 'schema.graphql')}
document_paths: [lib/**.graphql]
''');
    expect(await run(['--config', config]), 64);
    expect(err.toString(), contains('schema_endpoint'));
  });

  test('fails when schema_url is a URL and there is no --output', () async {
    final config = writeConfig('''
schema_url: $endpoint
document_paths: [lib/**.graphql]
''');
    expect(await run(['--config', config]), 64);
    expect(err.toString(), contains('--output'));
  });

  test('reports download failures', () async {
    status = 500;
    final output = p.join(dir.path, 'schema.graphql');
    expect(await run(['--endpoint', endpoint, '--output', output]), 1);
    expect(err.toString(), contains('SCH500'));
    expect(File(output).existsSync(), isFalse);
  });

  test('rejects malformed --header values', () async {
    expect(
        await run([
          '--endpoint', endpoint, //
          '--output', p.join(dir.path, 's.graphql'),
          '--header', 'no-colon',
        ]),
        64);
    expect(err.toString(), contains('no-colon'));
  });
}
