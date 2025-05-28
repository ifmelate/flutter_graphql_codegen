/// Client extension generation utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'dart:developer' as developer;
import 'code_utils.dart';
import 'operation_analyzer.dart';
import 'schema_analyzer.dart';

/// Utility class for generating client extensions
class ClientExtensionGenerator {
  /// Generates a client extension for a GraphQL operation
  static String generateClientExtension(
    String operationName,
    String operationType,
    String operationDocumentContent,
    DocumentNode schemaDoc,
    Set<String> definedTypes,
  ) {
    final methodName =
        operationType.toLowerCase() == 'mutation' ? 'mutate' : 'query';
    final optionsType = '${operationType.capitalize()}Options';
    final operationDoc = gql_lang.parseString(operationDocumentContent);

    final returnType = OperationAnalyzer.getOperationReturnType(
      operationDoc,
      schemaDoc,
      definedTypes,
    );
    final fieldName = OperationAnalyzer.getOperationFieldName(operationDoc);

    // Analyze skippable fields
    final skippableFields = OperationAnalyzer.getSkippableFields(operationDoc);

    // Check if the type is nullable
    final isNullable = returnType.endsWith('?');
    // Always use Future<ReturnType> for *Data methods
    // If type is nullable in schema, keep it nullable in return type
    final methodReturnType =
        isNullable ? 'Future<$returnType>' : 'Future<$returnType>';

    return '''
extension ${operationName}Extension on graphql.GraphQLClient {
  Future<graphql.QueryResult<Map<String, dynamic>>> ${operationName.toCamelCase()}([Map<String, dynamic>? variables]) async {
    final options = graphql.$optionsType<Map<String, dynamic>>(
      document: graphql.gql(r"""
$operationDocumentContent
      """),
      variables: variables ?? const {},
    );

    try {
      final result = await this.$methodName(options);

      if (result.hasException) {
        developer.log('GraphQL error in $operationName: \${result.exception}');
        throw result.exception!;
      }

      return result;
    } catch (e) {
      developer.log('Error executing GraphQL query $operationName: \$e');
      rethrow;
    }
  }

  $methodReturnType ${operationName.toCamelCase()}Data([Map<String, dynamic>? variables]) async {
    try {
      final result = await ${operationName.toCamelCase()}(variables);

      if (result.data == null) {
        developer.log('Error: result.data is null in $operationName');
        ${isNullable ? 'return null;' : 'throw Exception("Error: result.data is null in $operationName");'}
      }

      ${_generateDataConversion(returnType, fieldName, skippableFields)}
    
    } catch (e, stackTrace) {
      developer.log('Error in ${operationName}Data: \$e');
      developer.log('Stack trace: \$stackTrace');
      ${isNullable ? 'return null;' : 'throw Exception("An error occurred while fetching data in $operationName: \$e");'}
    }
  }
}
''';
  }

  /// Generates data conversion logic for different return types
  static String _generateDataConversion(
    String returnType,
    String fieldName, [
    Set<String>? skippableFields,
  ]) {
    final isNullable = returnType.endsWith('?');
    final baseType = isNullable
        ? returnType.substring(0, returnType.length - 1)
        : returnType;

    // Handle lists
    if (baseType.startsWith('List<') && baseType.endsWith('>')) {
      final innerType = baseType.substring(5, baseType.length - 1);
      final innerIsNullable = innerType.endsWith('?');
      final innerBaseType = innerIsNullable
          ? innerType.substring(0, innerType.length - 1)
          : innerType;

      return """
      try {
        final data = result.data!;
        if (!data.containsKey('$fieldName') || data['$fieldName'] == null) {
          return ${isNullable ? 'null' : '[]'};
        }
        
        final jsonList = data['$fieldName'];
        if (jsonList is! List<dynamic>) {
          throw Exception("Field '$fieldName' is not a list in GraphQL response");
        }
        
        return jsonList.map((item) {
          ${_generateItemConversion(innerBaseType, innerIsNullable)}
        }).toList();
      } catch (e, stackTrace) {
        developer.log('Error converting GraphQL response to $returnType: \$e');
        developer.log('Stack trace: \$stackTrace');
        ${isNullable ? 'return null;' : 'throw Exception("Error converting GraphQL response to $returnType: \$e");'}
      }
      """;
    }
    // Handle primitive types
    else if (baseType == 'int' ||
        baseType == 'bool' ||
        baseType == 'double' ||
        baseType == 'String') {
      return """
      try {
        final data = result.data!;
        if (!data.containsKey('$fieldName') || data['$fieldName'] == null) {
          ${isNullable ? 'return null;' : 'throw Exception("Field \'$fieldName\' is null in GraphQL response");'}
        }
        
        final value = data['$fieldName'];
        ${_generatePrimitiveTypeConversion(baseType, isNullable)}
      } catch (e, stackTrace) {
        developer.log('Error converting GraphQL response to $returnType: \$e');
        developer.log('Stack trace: \$stackTrace');
        ${isNullable ? 'return null;' : 'throw Exception("Error converting GraphQL response to $returnType: \$e");'}
      }
      """;
    }
    // Explicit handling for dynamic baseType
    else if (baseType == 'dynamic') {
      return """
      try {
        final data = result.data!;
        if (!data.containsKey('$fieldName') || data['$fieldName'] == null) {
          ${isNullable ? 'return null;' : 'throw Exception("Field \'$fieldName\' is null in GraphQL response for dynamic type");'}
        }
        // The field itself should be dynamic data (e.g., Map or primitive)
        return data['$fieldName']; 
      } catch (e, stackTrace) {
        developer.log('Error converting GraphQL response for dynamic field $fieldName: \$e');
        developer.log('Stack trace: \$stackTrace');
        ${isNullable ? 'return null;' : 'throw Exception("Error converting GraphQL response for dynamic field $fieldName: \$e");'}
      }
        """;
    }
    // Handle objects
    else {
      // Check if there are skippable fields for this type
      final hasSkippableFields =
          skippableFields?.any((field) => field.startsWith(fieldName + '.')) ??
              false;

      if (hasSkippableFields && baseType == 'SymptomsListDTO') {
        // Special handling for SymptomsListDTO with @skip directive for repGlav
        return """
        try {
          final data = result.data!;
          if (!data.containsKey('$fieldName') || data['$fieldName'] == null) {
            ${isNullable ? 'return null;' : 'throw Exception("Field \'$fieldName\' is null in GraphQL response");'}
          }
          
          final json = data['$fieldName'];
          if (json is! Map<String, dynamic>) {
            throw Exception("Field '$fieldName' is not an object in GraphQL response");
          }
          
          // Create modified JSON for SymptomsListDTO, setting repGlav to null if missing
          final modifiedJson = Map<String, dynamic>.from(json);
          if (!modifiedJson.containsKey('repGlav')) {
            modifiedJson['repGlav'] = null;
          }
          
          return $baseType.fromJson(modifiedJson);
        } catch (e, stackTrace) {
          developer.log('Error converting GraphQL response to $returnType: \$e');
          developer.log('Stack trace: \$stackTrace');
          ${isNullable ? 'return null;' : 'throw Exception("Error converting GraphQL response to $returnType: \$e");'}
        }
        """;
      } else {
        return """
        try {
          final data = result.data!;
          if (!data.containsKey('$fieldName') || data['$fieldName'] == null) {
            ${isNullable ? 'return null;' : 'throw Exception("Field \'$fieldName\' is null in GraphQL response");'}
          }
          
          final json = data['$fieldName'];
          if (json is! Map<String, dynamic>) {
            throw Exception("Field '$fieldName' is not an object in GraphQL response");
          }
          
          return $baseType.fromJson(json);
        } catch (e, stackTrace) {
          developer.log('Error converting GraphQL response to $returnType: \$e');
          developer.log('Stack trace: \$stackTrace');
          ${isNullable ? 'return null;' : 'throw Exception("Error converting GraphQL response to $returnType: \$e");'}
        }
        """;
      }
    }
  }

  /// Generates item conversion logic for list elements
  static String _generateItemConversion(String type, bool isNullable) {
    if (type == 'int') {
      return """
          if (item is int) return item;
          if (item is num) return item.toInt();
          if (item is String) {
            final parsed = int.tryParse(item);
            if (parsed != null) return parsed;
          }
          ${isNullable ? 'return null;' : 'throw Exception("Cannot convert item to int");'}
      """;
    } else if (type == 'bool') {
      return """
          if (item is bool) return item;
          if (item is String) {
            if (item.toLowerCase() == 'true') return true;
            if (item.toLowerCase() == 'false') return false;
          }
          if (item is num) return item != 0;
          ${isNullable ? 'return null;' : 'throw Exception("Cannot convert item to bool");'}
      """;
    } else if (type == 'double') {
      return """
          if (item is double) return item;
          if (item is num) return item.toDouble();
          if (item is String) {
            final parsed = double.tryParse(item);
            if (parsed != null) return parsed;
          }
          ${isNullable ? 'return null;' : 'throw Exception("Cannot convert item to double");'}
      """;
    } else if (type == 'String') {
      return """
          if (item is String) return item;
          return item.toString();
      """;
    } else if (type == 'dynamic') {
      // Explicit handling for dynamic list elements
      return """
          // Assumes 'item' already has the correct dynamic type (e.g., Map if it was an object)
          return item; 
      """;
    } else {
      return """
          if (item == null) { ${isNullable ? 'return null;' : 'throw Exception("Null item in non-nullable list for type $type");'} }
          if (item is! Map<String, dynamic>) { throw Exception("Item is not a map for type $type, actual: \${item.runtimeType}"); }
          return $type.fromJson(item as Map<String, dynamic>);
      """;
    }
  }

  /// Generates primitive type conversion logic
  static String _generatePrimitiveTypeConversion(String type, bool isNullable) {
    if (type == 'int') {
      return '''
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
        ${isNullable ? 'return null;' : 'throw Exception("Cannot convert value to int");'}
      ''';
    } else if (type == 'bool') {
      return '''
        if (value is bool) return value;
        if (value is String) {
          if (value.toLowerCase() == 'true') return true;
          if (value.toLowerCase() == 'false') return false;
        }
        if (value is num) return value != 0;
        ${isNullable ? 'return null;' : 'throw Exception("Cannot convert value to bool");'}
      ''';
    } else if (type == 'double') {
      return '''
        if (value is double) return value;
        if (value is num) return value.toDouble();
        if (value is String) {
          final parsed = double.tryParse(value);
          if (parsed != null) return parsed;
        }
        ${isNullable ? 'return null;' : 'throw Exception("Cannot convert value to double");'}
      ''';
    } else if (type == 'String') {
      return '''
        if (value is String) return value;
        return value.toString();
      ''';
    } else {
      return '''
        return $type.fromJson(value as Map<String, dynamic>);
      ''';
    }
  }
}
