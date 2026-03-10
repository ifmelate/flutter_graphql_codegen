/// Schema analysis utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'code_utils.dart';
import 'config_context.dart';

/// Utility class for analyzing GraphQL schemas
class SchemaAnalyzer {
  /// Extracts custom types and enums from the schema document
  static void extractCustomTypesAndEnums(DocumentNode schemaDoc) {
    TypeRegistry.clear();

    for (final definition in schemaDoc.definitions) {
      if (definition is TypeDefinitionNode) {
        final typeName = definition.name.value;
        if (definition is ScalarTypeDefinitionNode &&
            !GraphQLConstants.builtInScalars.contains(typeName) &&
            typeName != 'Decimal') {
          TypeRegistry.addCustomScalar(typeName);
        } else if (definition is EnumTypeDefinitionNode) {
          TypeRegistry.addEnumType(typeName);
        } else if (definition is ObjectTypeDefinitionNode) {
          TypeRegistry.addObjectType(typeName);
        }
      }
    }
  }

  /// Extracts custom scalars from the schema document
  static Set<String> extractCustomScalars(DocumentNode schemaDoc) {
    final customScalars = <String>{};
    for (final definition in schemaDoc.definitions) {
      if (definition is TypeDefinitionNode) {
        final typeName = definition.name.value;
        if (definition is ScalarTypeDefinitionNode &&
            !GraphQLConstants.builtInScalars.contains(typeName) &&
            typeName != 'Decimal') {
          customScalars.add(typeName);
        }
      }
    }
    return customScalars;
  }

  /// Finds the root type for a given operation type
  static ObjectTypeDefinitionNode? findRootType(
      DocumentNode schemaDoc, String operationType) {
    operationType = operationType.toLowerCase();
    if (operationType == 'operationtype.mutation') {
      operationType = 'mutation';
    } else if (operationType == 'operationtype.query') {
      operationType = 'query';
    } else if (operationType == 'operationtype.subscription') {
      operationType = 'subscription';
    }

    for (final definition in schemaDoc.definitions) {
      if (definition is SchemaDefinitionNode) {
        for (final operationTypeDefinition in definition.operationTypes) {
          if (operationTypeDefinition.operation.name == operationType) {
            final typeName = operationTypeDefinition.type.name.value;
            return schemaDoc.definitions.firstWhere(
              (def) =>
                  def is ObjectTypeDefinitionNode && def.name.value == typeName,
              orElse: () => throw StateError('Type not found: $typeName'),
            ) as ObjectTypeDefinitionNode?;
          }
        }
      }
    }

    final rootTypeName = operationType.capitalize();
    return schemaDoc.definitions.firstWhere(
      (def) =>
          def is ObjectTypeDefinitionNode && def.name.value == rootTypeName,
      orElse: () => throw StateError('Root type not found: $rootTypeName'),
    ) as ObjectTypeDefinitionNode?;
  }

  /// Gets the schema type string from a TypeNode
  static String getSchemaType(TypeNode type) {
    if (type is NamedTypeNode) {
      return '${type.name.value}?';
    } else if (type is ListTypeNode) {
      return 'List<${getSchemaType(type.type)}>?';
    }
    return 'dynamic';
  }

  /// Maps schema type to Dart type
  static String mapSchemaTypeToDartType(
      String schemaType, Set<String> definedTypes) {
    final isNullable = schemaType.endsWith('?');
    final baseType = isNullable
        ? schemaType.substring(0, schemaType.length - 1)
        : schemaType;

    if (baseType.startsWith('List<')) {
      final innerType = baseType.substring(5, baseType.length - 1);
      final mappedInnerType = mapSchemaTypeToDartType(innerType, definedTypes);
      return isNullable ? 'List<$mappedInnerType>?' : 'List<$mappedInnerType>';
    }

    switch (baseType) {
      case 'Int':
        return isNullable ? 'int?' : 'int';
      case 'Float':
        return isNullable ? 'double?' : 'double';
      case 'String':
        return isNullable ? 'String?' : 'String';
      case 'Boolean':
        return isNullable ? 'bool?' : 'bool';
      case 'ID':
        return isNullable ? 'String?' : 'String';
      case 'DateTime':
        return isNullable ? 'DateTime?' : 'DateTime';
      case 'LocalDate':
        return isNullable ? 'DateTime?' : 'DateTime';
      case 'Decimal':
        return isNullable ? 'Decimal?' : 'Decimal';
      case 'Short':
        return isNullable ? 'int?' : 'int';
      default:
        if (definedTypes.contains(baseType) ||
            (TypeRegistry.isCustomScalar(baseType) && baseType != 'Decimal') ||
            TypeRegistry.isEnum(baseType)) {
          return isNullable ? '$baseType?' : baseType;
        }
        return isNullable ? 'dynamic?' : 'dynamic';
    }
  }

  /// Checks if a type is a scalar type
  static bool isScalarType(String typeName) {
    final scalarTypes = [
      'Int',
      'Float',
      'String',
      'Boolean',
      'ID',
      'DateTime',
      'LocalDate',
      'Decimal',
      'Short',
      ...TypeRegistry.customScalars.where((s) => s != 'Decimal')
    ];
    return scalarTypes.contains(typeName);
  }

  /// Maps GraphQL type to Dart type for basic types
  static String mapGraphQLTypeToDartType(String graphqlType) {
    switch (graphqlType) {
      case 'Int':
        return 'int';
      case 'Float':
        return 'double';
      case 'String':
        return 'String';
      case 'Boolean':
        return 'bool';
      case 'ID':
        return 'String';
      case 'Short':
        return 'int';
      default:
        return graphqlType;
    }
  }

  /// Gets the Dart type from a TypeNode
  static String getDartType(TypeNode type) {
    if (type is NamedTypeNode) {
      final original = type.name.value;
      // Allow scalar mapping override from config
      final mapped = CodegenConfigContext.scalarMapping[original] ??
          GraphQLConstants.scalarToDartType[original] ??
          original;

      final isObjectType = TypeRegistry.objectTypes.contains(original);

      // Respect schema NonNull exactly for scalars/enums/custom scalars
      if (!isObjectType) {
        return type.isNonNull ? mapped : '$mapped?';
      }

      // For object types: we still respect NonNull, but mapping keeps class name
      return type.isNonNull ? original : '$original?';
    } else if (type is ListTypeNode) {
      // Compute element Dart type first (it will include '?' if nullable)
      final innerType = getDartType(type.type);
      final listType = 'List<$innerType>';
      // When strictNullability is off, lists are always nullable (legacy behavior).
      // When on, respect the NonNull flag from the schema exactly.
      if (!CodegenConfigContext.strictNullability) {
        return '$listType?';
      }
      return type.isNonNull ? listType : '$listType?';
    }
    return 'dynamic';
  }
}
