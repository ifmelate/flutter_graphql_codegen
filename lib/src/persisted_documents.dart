/// Persisted documents (`persisted_documents`): an id per operation
/// document, a manifest mapping the ids to the documents for the server, and
/// a request serializer that sends the id instead of the document.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:graphql/client.dart' as graphql;

import 'code_utils.dart';

/// Name of the generated library with the ids and the serializer.
const persistedDocumentsLibrary = 'persisted_documents.dart';

/// The text a GraphQLClient sends for the generated document [document]:
/// the generated code parses it with `graphql.gql`, which adds `__typename`
/// to every selection set, the operation's included.
String persistedDocumentText(String document) =>
    gql_lang.printNode(graphql.gql(document));

/// Id of the document [text] (from [persistedDocumentText]): its hash with
/// [algorithm] (`sha256`, `sha1` or `md5`), in lowercase hex.
String persistedDocumentId(String text, String algorithm) {
  final hash = switch (algorithm) {
    'sha1' => sha1,
    'md5' => md5,
    _ => sha256,
  };
  return hash.convert(utf8.encode(text)).toString();
}

/// The manifest: document by id, sorted by id.
String persistedDocumentsManifest(Map<String, String> documents) {
  final ids = documents.keys.toList()..sort();
  return '${const JsonEncoder.withIndent('  ').convert({
        for (final id in ids) id: documents[id],
      })}\n';
}

/// The generated library: [ids] maps operation names to document ids.
String persistedDocumentsCode(Map<String, String> ids, String algorithm) {
  final names = ids.keys.toList()..sort();
  return '''${CodeGenerationConstants.generatedFileWarning}
// Persisted documents
${CodeGenerationConstants.ignoreForFile}

import 'package:graphql/client.dart' as graphql;

/// Id of each operation's document by operation name: the $algorithm hash of
/// the document, as in the manifest the server is given.
const persistedDocumentIds = <String, String>{
${names.map((n) => "  '$n': '${ids[n]}',").join('\n')}
};

/// Where a [PersistedDocumentsSerializer] puts the document id.
enum PersistedDocumentFormat {
  /// `extensions.persistedQuery.sha256Hash`, as Apollo's persisted queries
  /// (Apollo Router, GraphQL Hive, graphql-java, Hot Chocolate with a
  /// SHA-256 hash provider).
  apollo,

  /// A top-level `documentId`, as in the GraphQL over HTTP persisted
  /// documents proposal (GraphQL Hive).
  documentId,

  /// A top-level `id` (Hot Chocolate, with any hash provider).
  id,
}

/// Sends the id of an operation's persisted document instead of the
/// document. Operations without an id in [persistedDocumentIds] are sent as
/// usual.
///
/// ```dart
/// final link = HttpLink(url, serializer: const PersistedDocumentsSerializer());
/// ```
class PersistedDocumentsSerializer extends graphql.RequestSerializer {
  const PersistedDocumentsSerializer({
    this.format = PersistedDocumentFormat.apollo,
    this.sendDocument = false,
  });

  /// Where the id goes.
  final PersistedDocumentFormat format;

  /// Also sends the document, for servers that register documents on first
  /// use (automatic persisted queries).
  final bool sendDocument;

  @override
  Map<String, dynamic> serializeRequest(graphql.Request request) {
    final body = super.serializeRequest(request);
    final id = persistedDocumentIds[request.operation.operationName];
    if (id == null) return body;
    if (!sendDocument) body.remove('query');
    switch (format) {
      case PersistedDocumentFormat.apollo:
        body['extensions'] = <String, dynamic>{
          ...?body['extensions'] as Map<String, dynamic>?,
          'persistedQuery': <String, dynamic>{'version': 1, 'sha256Hash': id},
        };
      case PersistedDocumentFormat.documentId:
        body['documentId'] = id;
      case PersistedDocumentFormat.id:
        body['id'] = id;
    }
    return body;
  }
}
''';
}
