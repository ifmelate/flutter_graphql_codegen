/// This file provides the public API for generating GraphQL-related code.
/// The actual generation logic lives in separate modules.
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

import 'client_extension_generator.dart';
import 'document_utils.dart';
import 'operation_analyzer.dart';
import 'type_generator.dart';
import 'type_usage.dart';

/// Main GraphQL code generator class
///
/// This class provides the public API for generating GraphQL-related code.
class GraphQLCodeGenerator {
  /// Generates a complete types file with all necessary components.
  ///
  /// With [only] (see [usedTypes]), enums, input types, custom scalars and
  /// `possibleTypes` entries are limited to those schema types (operation
  /// result types only).
  static String generateTypesFile(String schema, {Set<String>? only}) {
    return TypeGenerator.generateTypesFile(schema, only: only);
  }

  /// The schema types that the operations and fragments of [documents]
  /// use, for `generateTypesFile(only: ...)` (what `prune_types` does in the
  /// builder).
  static Set<String> usedTypes(String schema, Iterable<String> documents) {
    final docs = documents.map(gql_lang.parseString).toList();
    return TypeUsage.collect(
      gql_lang.parseString(schema),
      [
        for (final doc in docs)
          ...doc.definitions.whereType<OperationDefinitionNode>(),
      ],
      DocumentUtils.collectFragments(docs),
    );
  }

  /// Generates an operation file.
  ///
  /// [fragments] supplies fragment definitions that live outside
  /// [documentContent] (e.g. in other `.graphql` files). [fragmentLibraries]
  /// maps those declared by another package (`fragment_imports`) to the URI
  /// of their `fragments.dart`.
  static String generateOperationFile(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
    String typesContent, {
    Map<String, FragmentDefinitionNode> fragments = const {},
    Map<String, String> fragmentLibraries = const {},
  }) {
    return ClientExtensionGenerator.generateOperationFile(
      operationName,
      operationType,
      documentContent,
      gql_lang.parseString(schema),
      OperationAnalyzer.extractDefinedTypes(typesContent),
      fragments: fragments,
      fragmentLibraries: fragmentLibraries,
    );
  }

  /// Generates `fragments.dart` (`result_types: operation`): per fragment its
  /// document, an interface with its fields and a `<Fragment>Data` class.
  /// Fragments in [fragmentLibraries] (declared by another package, name ->
  /// library URI) are only used, not declared.
  ///
  /// Returns null when [fragments] has no fragment to declare.
  static String? generateFragmentsFile(
      String schema, Map<String, FragmentDefinitionNode> fragments,
      {Map<String, String> fragmentLibraries = const {}}) {
    return ClientExtensionGenerator.generateFragmentsFile(
        gql_lang.parseString(schema), fragments,
        fragmentLibraries: fragmentLibraries);
  }

  /// Extracts defined types from types content
  static Set<String> extractDefinedTypes(String typesContent) {
    return OperationAnalyzer.extractDefinedTypes(typesContent);
  }
}
