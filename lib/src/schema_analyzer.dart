/// Schema analysis utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'code_utils.dart';
import 'config_context.dart';
import 'enum_settings.dart';
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
      } else if (EnumSettings.customType(original) case final custom?) {
        mapped = custom;
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
