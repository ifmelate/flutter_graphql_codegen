/// Operation analysis utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'schema_analyzer.dart';
import 'code_utils.dart';

/// Utility class for analyzing GraphQL operations
class OperationAnalyzer {
  /// Gets the return type for a GraphQL operation
  static String getOperationReturnType(
    DocumentNode operationDoc,
    DocumentNode schemaDoc,
    Set<String> definedTypes,
  ) {
    print('Entering getOperationReturnType');
    print('Operation document: ${operationDoc.toString()}');
    print('Schema document: ${schemaDoc.toString()}');
    print('Defined types: $definedTypes');

    for (final definition in operationDoc.definitions) {
      print('Processing definition: ${definition.runtimeType}');
      if (definition is OperationDefinitionNode) {
        final operationType = definition.type.toString().toLowerCase();
        final rootType = SchemaAnalyzer.findRootType(schemaDoc, operationType);

        if (rootType != null) {
          if (definition.selectionSet.selections.isNotEmpty) {
            final firstSelection = definition.selectionSet.selections.first;
            if (firstSelection is FieldNode) {
              final fieldName = firstSelection.name.value;
              final field = rootType.fields.firstWhere(
                (f) => f.name.value == fieldName,
                orElse: () => throw StateError('Field not found: $fieldName'),
              );

              final schemaType = SchemaAnalyzer.getSchemaType(field.type);
              final dartType = SchemaAnalyzer.mapSchemaTypeToDartType(
                  schemaType, definedTypes);
              return dartType;
            }
          } else {
            print('Selection set is empty');
          }
        } else {
          print('Root type is null, falling back to dynamic');
          return 'dynamic';
        }
      }
    }
    print('Unable to determine return type for operation');
    return 'dynamic';
  }

  /// Gets the field name from the first selection in an operation
  static String getOperationFieldName(DocumentNode operationDoc) {
    for (final definition in operationDoc.definitions) {
      if (definition is OperationDefinitionNode) {
        if (definition.selectionSet.selections.isNotEmpty) {
          final firstSelection = definition.selectionSet.selections.first;
          if (firstSelection is FieldNode) {
            return firstSelection.name.value;
          }
        }
      }
    }
    return '';
  }

  /// Checks if a field has a @skip directive
  static bool hasSkipDirective(FieldNode field) {
    return field.directives.any((directive) => directive.name.value == 'skip');
  }

  /// Analyzes operation and finds fields with @skip directives
  static Set<String> getSkippableFields(DocumentNode operationDoc) {
    final skippableFields = <String>{};

    void analyzeSelectionSet(SelectionSetNode selectionSet, String prefix) {
      for (final selection in selectionSet.selections) {
        if (selection is FieldNode) {
          final fieldName = selection.name.value;
          final fullFieldName =
              prefix.isEmpty ? fieldName : '$prefix.$fieldName';

          if (hasSkipDirective(selection)) {
            skippableFields.add(fullFieldName);
          }

          if (selection.selectionSet != null) {
            analyzeSelectionSet(selection.selectionSet!, fullFieldName);
          }
        }
      }
    }

    for (final definition in operationDoc.definitions) {
      if (definition is OperationDefinitionNode) {
        analyzeSelectionSet(definition.selectionSet, '');
      }
    }

    return skippableFields;
  }

  /// Extracts defined types from generated types content
  static Set<String> extractDefinedTypes(String typesContent) {
    final definedTypes = <String>{};
    final classRegex = RegExp(r'class\s+(\w+)');
    final matches = classRegex.allMatches(typesContent);
    for (final match in matches) {
      definedTypes.add(match.group(1)!);
    }
    return definedTypes;
  }
}
