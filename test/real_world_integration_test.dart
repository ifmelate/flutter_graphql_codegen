import 'dart:io';
import 'package:test/test.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/schema_downloader.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/utils.dart';
import 'package:path/path.dart' as path;

void main() {
  group('Real World Integration Tests', () {
    late String testDir;
    late String configPath;
    late String schemaPath;
    late GraphQLCodegenConfig config;

    setUpAll(() async {
      testDir = Directory.current.path;
      configPath =
          path.join(testDir, 'test', 'fixtures', 'graphql_codegen.yaml');
      schemaPath = path.join(testDir, 'test', 'fixtures', 'schema.graphql');

      // Verify test files exist
      expect(File(configPath).existsSync(), true,
          reason: 'Config file should exist');
      expect(File(schemaPath).existsSync(), true,
          reason: 'Schema file should exist');

      // Load configuration
      final configFile = File(configPath);
      final yamlString = await configFile.readAsString();
      config = GraphQLCodegenConfig.fromYaml(yamlString);
    });

    test('should load configuration correctly', () {
      expect(config.schemaUrl, equals('test/fixtures/schema.graphql'));
      expect(config.outputDir, equals('test/generated'));
      expect(config.documentPaths, contains('test/fixtures/*.graphql'));
    });

    test('should download/read schema from local file', () async {
      final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);

      expect(schema, isNotEmpty);
      expect(schema, contains('scalar DateTime'));
      expect(schema, contains('scalar Decimal'));
      expect(schema, contains('scalar Long'));
      expect(schema, contains('scalar Byte'));
      expect(schema, contains('scalar JSON'));
      expect(schema, contains('enum UserRole'));
      expect(schema, contains('enum UserStatus'));
      expect(schema, contains('enum PostStatus'));
      expect(schema, contains('interface Node'));
      expect(schema, contains('interface Timestamped'));
      expect(schema, contains('union SearchResult'));
      expect(schema, contains('type User'));
      expect(schema, contains('type Post'));
      expect(schema, contains('type Comment'));
      expect(schema, contains('type Query'));
      expect(schema, contains('type Mutation'));
      expect(schema, contains('type Subscription'));
    });

    test('should generate types file from real schema', () async {
      final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);
      final typesCode = TypeGenerator.generateTypesFile(schema);

      expect(typesCode, isNotEmpty);

      // Check for generated warning comment
      expect(typesCode, contains('// THIS FILE IS GENERATED AUTOMATICALLY'));
      expect(typesCode, contains('// Any manual changes will be overwritten'));

      // Check for custom scalar converters
      expect(typesCode, contains('class DateTimeConverter'));
      expect(typesCode, contains('class DecimalConverter'));
      expect(typesCode, contains('class LongConverter'));
      expect(typesCode, contains('class ByteConverter'));

      // Check for safe converters
      expect(typesCode, contains('class SafeStringConverter'));
      expect(typesCode, contains('class SafeBoolConverter'));
      expect(typesCode, contains('class SafeIntConverter'));
      expect(typesCode, contains('class SafeDoubleConverter'));

      // Check for enum converters
      expect(typesCode, contains('class UserRoleConverter'));
      expect(typesCode, contains('class UserStatusConverter'));
      expect(typesCode, contains('class PostStatusConverter'));

      // Check for generated types
      expect(typesCode, contains('class User'));
      expect(typesCode, contains('class Post'));
      expect(typesCode, contains('class Comment'));
      expect(typesCode, contains('class CreateUserInput'));
      expect(typesCode, contains('class UpdateUserInput'));
      expect(typesCode, contains('class CreatePostInput'));

      // Check for JSON annotations
      expect(typesCode, contains('@JsonSerializable'));
      expect(typesCode, contains('fromJson'));
      expect(typesCode, contains('toJson'));
    });

    test('should process GetUser query operation', () async {
      final queryFile =
          File(path.join(testDir, 'test', 'fixtures', 'GetUser.graphql'));
      expect(queryFile.existsSync(), true,
          reason: 'GetUser.graphql should exist');

      final queryContent = await queryFile.readAsString();
      final operations = parseOperations(queryContent);

      expect(operations, hasLength(1));
      expect(operations.first.name, equals('GetUser'));
      expect(operations.first.type, equals('query'));

      // Test operation code generation
      final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);
      final typesCode = TypeGenerator.generateTypesFile(schema);

      final operationCode = GraphQLCodeGenerator.generateOperationFile(
        schema,
        queryContent,
        'GetUser',
        'query',
        typesCode,
      );

      expect(operationCode, isNotEmpty);
      expect(
          operationCode, contains('// THIS FILE IS GENERATED AUTOMATICALLY'));
      expect(operationCode, contains('extension GetUserExtension'));
      expect(operationCode, contains('getUser'));
      expect(operationCode, contains('getUserData'));
    });

    test('should process CreateUser mutation operation', () async {
      final mutationFile =
          File(path.join(testDir, 'test', 'fixtures', 'CreateUser.graphql'));
      expect(mutationFile.existsSync(), true,
          reason: 'CreateUser.graphql should exist');

      final mutationContent = await mutationFile.readAsString();
      final operations = parseOperations(mutationContent);

      expect(operations, hasLength(1));
      expect(operations.first.name, equals('CreateUser'));
      expect(operations.first.type, equals('mutation'));

      // Test operation code generation
      final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);
      final typesCode = TypeGenerator.generateTypesFile(schema);

      final operationCode = GraphQLCodeGenerator.generateOperationFile(
        schema,
        mutationContent,
        'CreateUser',
        'mutation',
        typesCode,
      );

      expect(operationCode, isNotEmpty);
      expect(
          operationCode, contains('// THIS FILE IS GENERATED AUTOMATICALLY'));
      expect(operationCode, contains('extension CreateUserExtension'));
      expect(operationCode, contains('createUser'));
      expect(operationCode, contains('createUserData'));
    });

    test('should process UserUpdated subscription operation', () async {
      final subscriptionFile =
          File(path.join(testDir, 'test', 'fixtures', 'UserUpdated.graphql'));
      expect(subscriptionFile.existsSync(), true,
          reason: 'UserUpdated.graphql should exist');

      final subscriptionContent = await subscriptionFile.readAsString();
      final operations = parseOperations(subscriptionContent);

      expect(operations, hasLength(1));
      expect(operations.first.name, equals('UserUpdated'));
      expect(operations.first.type, equals('subscription'));

      // Test operation code generation
      final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);
      final typesCode = TypeGenerator.generateTypesFile(schema);

      final operationCode = GraphQLCodeGenerator.generateOperationFile(
        schema,
        subscriptionContent,
        'UserUpdated',
        'subscription',
        typesCode,
      );

      expect(operationCode, isNotEmpty);
      expect(
          operationCode, contains('// THIS FILE IS GENERATED AUTOMATICALLY'));
      expect(operationCode, contains('extension UserUpdatedExtension'));
      expect(operationCode, contains('userUpdated'));
      expect(operationCode, contains('userUpdatedData'));
    });

    test('should process SearchContent query with fragments', () async {
      final queryFile =
          File(path.join(testDir, 'test', 'fixtures', 'SearchContent.graphql'));
      expect(queryFile.existsSync(), true,
          reason: 'SearchContent.graphql should exist');

      final queryContent = await queryFile.readAsString();

      // Check fragments are present
      expect(queryContent, contains('fragment UserFragment'));
      expect(queryContent, contains('fragment PostFragment'));
      expect(queryContent, contains('fragment CommentFragment'));

      // Check directives are present
      expect(queryContent, contains('@include(if: false)'));
      expect(queryContent, contains('@skip(if: true)'));

      final operations = parseOperations(queryContent);
      expect(operations, hasLength(1));
      expect(operations.first.name, equals('SearchContent'));
      expect(operations.first.type, equals('query'));
    });

    test('should handle complex pagination query', () async {
      final queryFile =
          File(path.join(testDir, 'test', 'fixtures', 'GetPosts.graphql'));
      expect(queryFile.existsSync(), true,
          reason: 'GetPosts.graphql should exist');

      final queryContent = await queryFile.readAsString();
      final operations = parseOperations(queryContent);

      expect(operations, hasLength(1));
      expect(operations.first.name, equals('GetPosts'));
      expect(operations.first.type, equals('query'));

      // Check for complex input types
      expect(queryContent, contains('PaginationInput'));
      expect(queryContent, contains('SortInput'));
      expect(queryContent, contains('PostStatus'));

      // Check for connection pattern
      expect(queryContent, contains('edges'));
      expect(queryContent, contains('node'));
      expect(queryContent, contains('cursor'));
      expect(queryContent, contains('pageInfo'));
      expect(queryContent, contains('hasNextPage'));
      expect(queryContent, contains('totalCount'));
    });

    test('should resolve document paths correctly', () {
      final resolvedPaths = config.resolveDocumentPaths();

      expect(resolvedPaths, isNotEmpty);

      // Check that all our test GraphQL files are found
      final pathStrings = resolvedPaths.map((p) => p.toString()).toList();
      expect(pathStrings.any((p) => p.contains('GetUser.graphql')), true);
      expect(pathStrings.any((p) => p.contains('CreateUser.graphql')), true);
      expect(pathStrings.any((p) => p.contains('CreatePost.graphql')), true);
      expect(pathStrings.any((p) => p.contains('UserUpdated.graphql')), true);
      expect(pathStrings.any((p) => p.contains('SearchContent.graphql')), true);
      expect(pathStrings.any((p) => p.contains('GetPosts.graphql')), true);
    });

    test('should generate complete workflow end-to-end', () async {
      print('=== Real World Integration Test ===');

      // Step 1: Load schema
      print('Loading schema...');
      final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);
      expect(schema, isNotEmpty);
      print('✅ Schema loaded successfully (${schema.length} chars)');

      // Step 2: Generate types
      print('Generating types...');
      final typesCode = TypeGenerator.generateTypesFile(schema);
      expect(typesCode, isNotEmpty);
      print('✅ Types generated successfully (${typesCode.length} chars)');

      // Step 3: Process each GraphQL operation file
      final resolvedPaths = config.resolveDocumentPaths();
      print('Processing ${resolvedPaths.length} GraphQL files...');

      for (final filePath in resolvedPaths) {
        final file = File(filePath.toString());
        if (file.path.endsWith('.graphql') && file.path != schemaPath) {
          print('Processing: ${path.basename(file.path)}');

          final content = await file.readAsString();
          final operations = parseOperations(content);

          if (operations.isNotEmpty) {
            final operation = operations.first;
            final operationCode = GraphQLCodeGenerator.generateOperationFile(
              schema,
              content,
              operation.name,
              operation.type,
              typesCode,
            );

            expect(operationCode, isNotEmpty);
            print(
                '  ✅ ${operation.type} ${operation.name} (${operationCode.length} chars)');
          }
        }
      }

      print('✅ All operations processed successfully');
      print('=== Integration test completed ===');
    });

    test('should handle all GraphQL features', () async {
      final schema = await SchemaDownloader.downloadSchema(config.schemaUrl);
      final typesCode = TypeGenerator.generateTypesFile(schema);

      // Test for comprehensive feature support
      final features = <String, List<String>>{
        'Custom Scalars': ['DateTime', 'Decimal', 'Long', 'Byte', 'JSON'],
        'Enums': ['UserRole', 'UserStatus', 'PostStatus'],
        'Generated Features': ['@JsonSerializable', 'fromJson', 'toJson'],
        'Union Types': ['SearchResult'],
        'Input Types': [
          'CreateUserInput',
          'UpdateUserInput',
          'PaginationInput'
        ],
        'Connection Types': ['UserConnection', 'PostConnection'],
        'Error Types': ['UserError', 'PostError', 'CommentError'],
        'Payload Types': ['CreateUserPayload', 'UpdateUserPayload'],
      };

      for (final entry in features.entries) {
        final featureName = entry.key;
        final expectedTypes = entry.value;

        for (final expectedType in expectedTypes) {
          expect(
            typesCode,
            contains(expectedType),
            reason: '$featureName should include $expectedType',
          );
        }
      }
    });
  });
}
