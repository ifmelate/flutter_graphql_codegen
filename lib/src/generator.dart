/// This file provides the public API for generating GraphQL-related code.
/// The actual generation logic has been refactored into separate modules
/// for better maintainability and separation of concerns.
library;

import 'package:gql/language.dart' as gql_lang;

// Import the refactored modules
import 'code_utils.dart';

import 'operation_analyzer.dart';
import 'type_generator.dart';
import 'client_extension_generator.dart';

/// Main GraphQL code generator class
///
/// This class provides the public API for generating GraphQL-related code.
/// The actual generation logic has been refactored into separate modules
/// for better maintainability and separation of concerns.
class GraphQLCodeGenerator {
  /// Generates a complete types file with all necessary components
  static String generateTypesFile(String schema) {
    return TypeGenerator.generateTypesFile(schema);
  }

  /// Generates code for a GraphQL operation
  static String generateCode(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
    String typesContent,
  ) {
    final schemaDoc = gql_lang.parseString(schema);
    final definedTypes = OperationAnalyzer.extractDefinedTypes(typesContent);
    final clientExtension = ClientExtensionGenerator.generateClientExtension(
        operationName, operationType, documentContent, schemaDoc, definedTypes);

    return '''${CodeGenerationConstants.generatedFileWarning}

import 'package:graphql/client.dart' as graphql;
import 'types.dart';

$clientExtension
''';
  }

  /// Generates an operation file
  static String generateOperationFile(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
    String typesContent,
  ) {
    final schemaDoc = gql_lang.parseString(schema);
    final definedTypes = OperationAnalyzer.extractDefinedTypes(typesContent);
    final clientExtension = ClientExtensionGenerator.generateClientExtension(
        operationName, operationType, documentContent, schemaDoc, definedTypes);

    return '''${CodeGenerationConstants.generatedFileWarning}

import 'package:graphql/client.dart' as graphql;
import 'types.dart';

$clientExtension
''';
  }

  /// Extracts defined types from types content
  static Set<String> extractDefinedTypes(String typesContent) {
    return OperationAnalyzer.extractDefinedTypes(typesContent);
  }
}
