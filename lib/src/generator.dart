/// This file provides the public API for generating GraphQL-related code.
/// The actual generation logic lives in separate modules.
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

import 'client_extension_generator.dart';
import 'operation_analyzer.dart';
import 'type_generator.dart';

/// Main GraphQL code generator class
///
/// This class provides the public API for generating GraphQL-related code.
class GraphQLCodeGenerator {
  /// Generates a complete types file with all necessary components
  static String generateTypesFile(String schema) {
    return TypeGenerator.generateTypesFile(schema);
  }

  /// Generates an operation file.
  ///
  /// [fragments] supplies fragment definitions that live outside
  /// [documentContent] (e.g. in other `.graphql` files).
  static String generateOperationFile(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
    String typesContent, {
    Map<String, FragmentDefinitionNode> fragments = const {},
  }) {
    return ClientExtensionGenerator.generateOperationFile(
      operationName,
      operationType,
      documentContent,
      gql_lang.parseString(schema),
      OperationAnalyzer.extractDefinedTypes(typesContent),
      fragments: fragments,
    );
  }

  /// Extracts defined types from types content
  static Set<String> extractDefinedTypes(String typesContent) {
    return OperationAnalyzer.extractDefinedTypes(typesContent);
  }
}
