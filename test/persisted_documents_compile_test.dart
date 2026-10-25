// End-to-end check of `persisted_documents`: the builder writes the ids, the
// manifest and the documents directory, and a GraphQLClient with
// PersistedDocumentsSerializer sends ids that a server holding only the
// manifest can run.
//
// Slow (creates a package and runs a script); skip locally with
// `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_graphql_codegen/src/builder.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/compile_harness.dart';

const _schema = r'''
type Query { user(id: ID!): User }
type Mutation { rename(id: ID!, name: String!): User }
type User { id: ID! name: String }
''';

const _documents = {
  'lib/graphql/user_bits.graphql': 'fragment UserBits on User { id name }',
  'lib/graphql/user.graphql': r'''
query GetUser($id: ID!) { user(id: $id) { ...UserBits } }
mutation Rename($id: ID!, $name: String!) { rename(id: $id, name: $name) { id name } }
''',
};

/// A server that only runs the documents of the manifest, and a client per
/// format; checks what is sent.
const _main = r'''
import 'dart:convert';
import 'dart:io';

import 'package:fgc_compile_check/gen/index.dart';
import 'package:graphql/client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

Future<void> main() async {
  final manifest = (jsonDecode(File('persisted_documents.json')
          .readAsStringSync()) as Map<String, dynamic>)
      .cast<String, String>();
  final bodies = <Map<String, dynamic>>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join())
        as Map<String, dynamic>;
    bodies.add(body);
    final id = body['extensions']?['persistedQuery']?['sha256Hash'] ??
        body['documentId'] ??
        body['id'];
    final document = id == null ? body['query'] : manifest[id];
    final variables = body['variables'] as Map<String, dynamic>;
    final user = {'__typename': 'User', 'id': variables['id'], 'name': 'Ann'};
    final Object? data = switch (document) {
      String d when d.contains('query GetUser') => {
          '__typename': 'Query',
          'user': user,
        },
      String d when d.contains('mutation Rename') => {
          '__typename': 'Mutation',
          'rename': {...user, 'name': variables['name']},
        },
      _ => null,
    };
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data == null
          ? {
              'errors': [
                {'message': 'PersistedQueryNotFound'},
              ],
            }
          : {'data': data}));
    await request.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}/graphql';
  GraphQLClient client(PersistedDocumentsSerializer serializer) =>
      GraphQLClient(
        link: HttpLink(url, serializer: serializer),
        cache: GraphQLCache(),
        defaultPolicies: DefaultPolicies(
          query: Policies(fetch: FetchPolicy.networkOnly),
        ),
      );

  check(persistedDocumentIds['GetUser'] == getUserDocumentId, 'ids');
  check(manifest.containsKey(getUserDocumentId), 'id in the manifest');

  final apollo = client(const PersistedDocumentsSerializer());
  final user =
      await apollo.getUserData(const GetUserVariables(id: '1').toJson());
  check(user?.name == 'Ann', 'query by id');
  check(!bodies.last.containsKey('query'), 'no document sent');
  check(
      bodies.last['extensions']['persistedQuery']['sha256Hash'] ==
              getUserDocumentId &&
          bodies.last['extensions']['persistedQuery']['version'] == 1,
      'Apollo format');
  check(bodies.last['operationName'] == 'GetUser', 'operation name');

  final hive = client(const PersistedDocumentsSerializer(
      format: PersistedDocumentFormat.documentId));
  final renamed = await hive.renameData(
      const RenameVariables(id: '1', name: 'Bea').toJson());
  check(renamed?.name == 'Bea', 'mutation by documentId');
  check(bodies.last['documentId'] == renameDocumentId, 'documentId format');

  final chilli =
      client(const PersistedDocumentsSerializer(format: PersistedDocumentFormat.id));
  await chilli.getUserData(const GetUserVariables(id: '2').toJson());
  check(bodies.last['id'] == getUserDocumentId, 'id format');

  // The document sent is the manifest's, so its hash is the id.
  final both = client(const PersistedDocumentsSerializer(sendDocument: true));
  await both.getUserData(const GetUserVariables(id: '3').toJson());
  check(bodies.last['query'] == manifest[getUserDocumentId],
      'sent document matches the manifest');

  // Documents without an id are sent as usual.
  final other = await apollo.query(QueryOptions(
      document: gql('query Other { user(id: "4") { id } }')));
  check(bodies.last['query'] != null && bodies.last['extensions'] == null,
      'unknown operation sent as is');
  check(other.hasException, 'the server only runs known documents');

  await server.close(force: true);
  print('PERSISTED OK');
}
''';

void main() {
  test('persisted documents are written and sent by id', () async {
    final out = await Directory.systemTemp.createTemp('fgc_persisted_');
    final errors = <String>[];
    CodegenConfigContext.reset();
    CodegenConfigContext.strictNullability = true;
    CodegenConfigContext.persistedDocumentsAlgorithm = 'sha256';
    try {
      final gen = p.join(out.path, 'gen');
      await testBuilder(
        GraphQLCodegenBuilder(GraphQLCodegenConfig(
          schemaUrl: 'lib/schema.graphql',
          outputDir: gen,
          documentPaths: ['lib/graphql/**.graphql'],
          strictNullability: true,
          persistedDocuments: PersistedDocumentsConfig(
            manifest: p.join(out.path, 'persisted_documents.json'),
            directory: p.join(out.path, 'operations'),
          ),
        )),
        {
          'a|lib/schema.graphql': _schema,
          for (final MapEntry(:key, :value) in _documents.entries)
            'a|$key': value,
        },
        rootPackage: 'a',
        onLog: (r) {
          if (r.level.name == 'SEVERE') errors.add(r.message);
        },
      );
      expect(errors, isEmpty);

      final manifestText =
          File(p.join(out.path, 'persisted_documents.json')).readAsStringSync();
      final manifest = (jsonDecode(manifestText) as Map<String, dynamic>)
          .cast<String, String>();
      expect(manifest, hasLength(2));
      for (final MapEntry(key: id, value: text) in manifest.entries) {
        expect(sha256.convert(utf8.encode(text)).toString(), id);
        // What the link sends: the document printed again.
        expect(gql_lang.printNode(gql_lang.parseString(text)), text);
        expect(
            File(p.join(out.path, 'operations', '$id.graphql'))
                .readAsStringSync(),
            text);
      }
      final getUser = manifest.values.singleWhere((t) => t.contains('GetUser'));
      expect(getUser, contains('fragment UserBits on User'));

      final files = {
        for (final file in Directory(gen).listSync().whereType<File>())
          'lib/gen/${p.basename(file.path)}': file.readAsStringSync(),
        'persisted_documents.json': manifestText,
        'bin/persisted.dart': _main,
      };
      expect(files['lib/gen/index.dart'],
          contains("export 'persisted_documents.dart';"));

      final result =
          await compileGenerated(files, runScripts: ['bin/persisted.dart']);
      expect(result.errors, isEmpty, reason: result.log);
    } finally {
      CodegenConfigContext.reset();
      await out.delete(recursive: true);
    }
  });
}
