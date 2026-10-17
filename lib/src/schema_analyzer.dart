/// Schema analysis utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'code_utils.dart';
import 'config_context.dart';
import 'naming.dart';

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
            typeName != 'Decimal' &&
            // Mapped scalars use the configured Dart type, no wrapper class.
            !CodegenConfigContext.scalarMapping.containsKey(typeName)) {
          TypeRegistry.addCustomScalar(typeName);
        } else if (definition is EnumTypeDefinitionNode) {
          TypeRegistry.addEnumType(typeName);
        } else if (definition is ObjectTypeDefinitionNode) {
          TypeRegistry.addObjectType(typeName);
        } else if (definition is InterfaceTypeDefinitionNode) {
          TypeRegistry.addInterfaceType(typeName);
        } else if (definition is UnionTypeDefinitionNode) {
          TypeRegistry.addUnionType(typeName);
        } else if (definition is InputObjectTypeDefinitionNode) {
          TypeRegistry.addInputType(typeName);
        }
      }
    }

    // Second pass: relationships between concrete and abstract types.
    for (final definition in schemaDoc.definitions) {
      if (definition is ObjectTypeDefinitionNode) {
        final typeName = definition.name.value;
        for (final iface in definition.interfaces) {
          final ifaceName = iface.name.value;
          if (!TypeRegistry.interfaceTypes.contains(ifaceName)) continue;
          TypeRegistry.addSupertype(typeName, ifaceName);
          TypeRegistry.addPossibleType(ifaceName, typeName);
        }
      } else if (definition is InterfaceTypeDefinitionNode) {
        for (final iface in definition.interfaces) {
          final ifaceName = iface.name.value;
          if (!TypeRegistry.interfaceTypes.contains(ifaceName)) continue;
          TypeRegistry.addSupertype(definition.name.value, ifaceName);
        }
      } else if (definition is UnionTypeDefinitionNode) {
        final unionName = definition.name.value;
        for (final member in definition.types) {
          final memberName = member.name.value;
          if (!TypeRegistry.objectTypes.contains(memberName)) continue;
          TypeRegistry.addSupertype(memberName, unionName);
          TypeRegistry.addPossibleType(unionName, memberName);
        }
      }
    }
  }

  /// Extracts custom scalars from the schema document
  @Deprecated('Not used by the generator; will be removed in 3.0.')
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
    if (operationType.startsWith('operationtype.')) {
      operationType = operationType.substring('operationtype.'.length);
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
  @Deprecated('Not used by the generator; will be removed in 3.0.')
  static String getSchemaType(TypeNode type) {
    if (type is NamedTypeNode) {
      return '${type.name.value}?';
    } else if (type is ListTypeNode) {
      return 'List<${getSchemaType(type.type)}>?';
    }
    return 'dynamic';
  }

  /// Maps schema type to Dart type
  @Deprecated('Not used by the generator; will be removed in 3.0.')
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
  @Deprecated('Not used by the generator; will be removed in 3.0.')
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
  @Deprecated('Not used by the generator; will be removed in 3.0.')
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

  /// The Dart name of a type the generator declares for schema type
  /// [graphqlName]: names in [reservedTypeNames] get a trailing underscore.
  static String dartTypeName(String graphqlName) =>
      TypeRegistry.declaresType(graphqlName) &&
              reservedTypeNames.contains(graphqlName)
          ? '${graphqlName}_'
          : graphqlName;

  /// Gets the Dart type from a TypeNode
  static String getDartType(TypeNode type) {
    if (type is NamedTypeNode) {
      final original = type.name.value;
      final String mapped;
      if (TypeRegistry.objectTypes.contains(original)) {
        mapped = dartTypeName(original);
      } else {
        // Allow scalar mapping override from config
        mapped = CodegenConfigContext.scalarMapping[original] ??
            (TypeRegistry.declaresType(original)
                ? dartTypeName(original)
                : GraphQLConstants.scalarToDartType[original] ?? original);
      }
      // Respect schema NonNull exactly
      return type.isNonNull ? mapped : '$mapped?';
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
