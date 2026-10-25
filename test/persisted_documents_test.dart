import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/persisted_documents.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

const _config = '''
schema_url: schema.graphql
output_dir: lib/gen/
document_paths: [lib/graphql/**.graphql]
''';

GraphQLCodegenConfig _parse(String extra) =>
    GraphQLCodegenConfig.fromYaml('$_config$extra');

const _schema = 'type Query { version: String }';

String _operation({String? algorithm}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.persistedDocumentsAlgorithm = algorithm;
  try {
    final types = TypeGenerator.generateTypesFile(_schema);
    return GraphQLCodeGenerator.generateOperationFile(
        _schema, 'query GetVersion { version }', 'GetVersion', 'query', types);
  } finally {
    CodegenConfigContext.reset();
  }
}

void main() {
  group('persisted_documents config', () {
    test('is off by default', () {
      expect(_parse('').persistedDocuments, isNull);
      expect(_parse('persisted_documents: false').persistedDocuments, isNull);
    });

    test('true writes the manifest next to the generated code', () {
      final options = _parse('persisted_documents: true').persistedDocuments!;
      expect(options.algorithm, 'sha256');
      expect(options.manifest, 'lib/gen/persisted_documents.json');
      expect(options.directory, isNull);
    });

    test('takes an algorithm, manifest and directory', () {
      final config = _parse('''
persisted_documents:
  algorithm: md5
  manifest: build/documents.json
  directory: persisted_operations
  extra: 1
''');
      final options = config.persistedDocuments!;
      expect(options.algorithm, 'md5');
      expect(options.manifest, 'build/documents.json');
      expect(options.directory, 'persisted_operations');
      expect(config.warnings.join(), contains('"extra"'));
    });

    test('rejects an unknown algorithm', () {
      expect(() => _parse('persisted_documents: {algorithm: crc32}'),
          throwsA(isA<CodegenException>()));
    });

    test('rejects a directory the documents glob matches', () {
      expect(() => _parse('persisted_documents: {directory: lib/graphql/ids}'),
          throwsA(isA<CodegenException>()));
    });
  });

  group('persisted document ids', () {
    test('are hex hashes of the text', () {
      expect(persistedDocumentId('query A { a }', 'sha256'), hasLength(64));
      expect(persistedDocumentId('query A { a }', 'sha1'), hasLength(40));
      expect(persistedDocumentId('query A { a }', 'md5'), hasLength(32));
    });

    test('hash the document as the client sends it', () {
      final text = persistedDocumentText('query A { a { b } }');
      expect(text, contains('__typename'));
      expect(text, startsWith('query A {\n  __typename'));
    });

    test('go into the operation file when enabled', () {
      final id = persistedDocumentId(
          persistedDocumentText('query GetVersion {\n  version\n}'), 'sha1');
      expect(_operation(algorithm: 'sha1'),
          contains("const String getVersionDocumentId = '$id';"));
      expect(_operation(), isNot(contains('DocumentId')));
    });

    test('the manifest is sorted by id', () {
      expect(persistedDocumentsManifest({'b': 'query B', 'a': 'query A'}),
          '{\n  "a": "query A",\n  "b": "query B"\n}\n');
    });
  });
}
