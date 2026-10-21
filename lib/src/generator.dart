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

  /// Generates code for a GraphQL operation.
  ///
  /// Same as [generateOperationFile].
  @Deprecated('Use generateOperationFile; will be removed in 3.0.')
  static String generateCode(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
    String typesContent, {
    Map<String, FragmentDefinitionNode> fragments = const {},
  }) {
    return generateOperationFile(
      schema,
      documentContent,
      operationName,
      operationType,
      typesContent,
      fragments: fragments,
    );
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

  /// Generates `fragments.dart` (`result_types: operation`): per fragment its
  /// document, an interface with its fields and a `<Fragment>Data` class.
  ///
  /// Returns null when [fragments] is empty.
  static String? generateFragmentsFile(
      String schema, Map<String, FragmentDefinitionNode> fragments) {
    return ClientExtensionGenerator.generateFragmentsFile(
        gql_lang.parseString(schema), fragments);
  }

  /// Extracts defined types from types content
  static Set<String> extractDefinedTypes(String typesContent) {
    return OperationAnalyzer.extractDefinedTypes(typesContent);
  }
}
