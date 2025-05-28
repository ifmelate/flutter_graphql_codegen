/// This file provides the public API for generating GraphQL-related code.
/// The actual generation logic has been refactored into separate modules
/// for better maintainability and separation of concerns.
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:json_annotation/json_annotation.dart';
import 'dart:developer' as developer;

// Import the refactored modules
import 'code_utils.dart';
import 'schema_analyzer.dart';
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
    final customScalars = SchemaAnalyzer.extractCustomScalars(schemaDoc);
    final scalarConverters = _generateScalarConverters(customScalars);
    final typeDefinitions = TypeGenerator.generateTypeDefinitions(schemaDoc);
    final definedTypes = OperationAnalyzer.extractDefinedTypes(typesContent);
    final clientExtension = ClientExtensionGenerator.generateClientExtension(
        operationName, operationType, documentContent, schemaDoc, definedTypes);

    return '''${CodeGenerationConstants.generatedFileWarning}

import 'dart:developer' as developer;
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

import 'dart:developer' as developer;
import 'package:graphql/client.dart' as graphql;
import 'package:raduga_flutter_application/graphql/generated/types.dart';

$clientExtension
''';
  }

  /// Extracts defined types from types content
  static Set<String> extractDefinedTypes(String typesContent) {
    return OperationAnalyzer.extractDefinedTypes(typesContent);
  }

  /// Legacy method for generating scalar converters
  static String _generateScalarConverters(Set<String> customScalars) {
    final buffer = StringBuffer();

    for (final scalar in customScalars) {
      if (scalar != 'DateTime' && scalar != 'Decimal') {
        buffer.writeln('''
class $scalar {
  final String value;
  $scalar(this.value);

  @override
  String toString() => value;
}

class ${scalar}Converter implements JsonConverter<$scalar, String> {
  const ${scalar}Converter();

  @override
  $scalar fromJson(String json) => $scalar(json);

  @override
  String toJson($scalar object) => object.toString();
}
''');
      }
    }
    return buffer.toString();
  }
}
