/// Dart types and JSON conversion expressions for GraphQL types, shared by
/// the generators.
library;

import 'package:gql/ast.dart';

import 'code_utils.dart';
import 'config_context.dart';
import 'schema_analyzer.dart';

/// Builds Dart type names and the expressions converting values from and to
/// JSON.
class JsonExprs {
  /// Dart type of an input value, respecting the schema's nullability.
  static String inputDartType(TypeNode type, {bool forceNullable = false}) {
    final nullable = forceNullable || !type.isNonNull;
    final base = type is ListTypeNode
        ? 'List<${inputDartType(type.type)}>'
        : namedDartType((type as NamedTypeNode).name.value);
    return withNullability(base, nullable);
  }

  /// Expression serialising the non-null value [v] of GraphQL [type].
  static String toJsonExpr(TypeNode type, String v) {
    if (type is ListTypeNode) {
      final inner = type.type;
      final item = toJsonExpr(inner, 'e');
      if (item == 'e') return v;
      final itemExpr = inner.isNonNull ? item : '(e == null ? null : $item)';
      return '$v.map((e) => $itemExpr).toList()';
    }

    final name = (type as NamedTypeNode).name.value;
    final mapped = CodegenConfigContext.scalarMapping[name];
    if (mapped != null) {
      final converter = CodegenConfigContext.scalarConverters[name];
      if (converter != null) return 'const $converter().toJson($v)';
      if (mapped == 'DateTime') return 'const DateTimeConverter().toJson($v)';
      return isJsonNative(mapped) ? v : '$v.toJson()';
    }
    // A schema type named like a built-in scalar (e.g. `type Decimal`) is
    // handled as the type the generator declares for it.
    switch (TypeRegistry.declaresType(name) ? '' : name) {
      case 'Int':
      case 'Float':
      case 'String':
      case 'Boolean':
      case 'ID':
      case 'Short':
        return v;
      case 'DateTime':
        return 'const DateTimeConverter().toJson($v)';
      case 'LocalDate':
        return 'const LocalDateConverter().toJson($v)';
      case 'Decimal':
        return 'const SafeDecimalConverter().toJson($v)';
      case 'Long':
        return 'const LongConverter().toJson($v)';
      case 'Byte':
        return 'const ByteConverter().toJson($v)';
    }
    if (TypeRegistry.isEnum(name) || TypeRegistry.isCustomScalar(name)) {
      return 'const ${SchemaAnalyzer.dartTypeName(name)}Converter().toJson($v)';
    }
    if (TypeRegistry.inputTypes.contains(name)) return '$v.toJson()';
    return v;
  }

  /// Dart type for a GraphQL output type. In legacy (non-strict) mode every
  /// level is nullable, matching previous releases.
  static String outputDartType(TypeNode type,
      {required bool legacy, bool forceNullable = false}) {
    final nullable = forceNullable || legacy || !type.isNonNull;
    final base = type is ListTypeNode
        ? 'List<${outputDartType(type.type, legacy: legacy)}>'
        : namedDartType((type as NamedTypeNode).name.value);
    return withNullability(base, nullable);
  }

  static String namedDartType(String name) {
    final known = CodegenConfigContext.scalarMapping.containsKey(name) ||
        GraphQLConstants.scalarToDartType.containsKey(name) ||
        const {'Decimal', 'Long', 'Byte'}.contains(name) ||
        TypeRegistry.isEnum(name) ||
        TypeRegistry.isCustomScalar(name) ||
        TypeRegistry.objectTypes.contains(name) ||
        TypeRegistry.isAbstract(name) ||
        TypeRegistry.inputTypes.contains(name);
    if (!known) return 'dynamic';
    return SchemaAnalyzer.getDartType(
        NamedTypeNode(name: NameNode(value: name), isNonNull: true));
  }

  /// Dart types a JSON value can be used as directly.
  static bool isJsonNative(String type) =>
      const {'String', 'int', 'double', 'num', 'bool', 'Object', 'dynamic'}
          .contains(type.replaceAll('?', '')) ||
      type.startsWith('Map<') ||
      type.startsWith('List<');

  static String withNullability(String type, bool nullable) =>
      nullable && type != 'dynamic' ? '$type?' : type;

  /// Expression converting the JSON value [v] into the Dart value of [type].
  static String fromJsonExpr(TypeNode type, String v,
      {required bool legacy,
      required Set<String> definedTypes,
      bool forceNullable = false}) {
    final nullable = forceNullable || legacy || !type.isNonNull;
    final String inner;
    if (type is ListTypeNode) {
      final item = fromJsonExpr(type.type, 'e',
          legacy: legacy, definedTypes: definedTypes);
      inner = '($v as List<dynamic>).map((e) => $item).toList()';
    } else {
      inner =
          namedFromJson((type as NamedTypeNode).name.value, v, definedTypes);
    }
    return nullable ? '($v == null ? null : $inner)' : inner;
  }

  static String namedFromJson(String name, String v, Set<String> definedTypes) {
    final mapped = CodegenConfigContext.scalarMapping[name];
    if (mapped != null) {
      final converter = CodegenConfigContext.scalarConverters[name];
      if (converter != null) return 'const $converter().fromJson($v)';
      switch (mapped) {
        case 'int':
          return 'const SafeIntConverter().fromJson($v)';
        case 'double':
          return 'const SafeDoubleConverter().fromJson($v)';
        case 'bool':
          return 'const SafeBoolConverter().fromJson($v)';
        case 'String':
          return 'const SafeStringConverter().fromJson($v)';
        case 'DateTime':
          return 'const DateTimeConverter().fromJson($v)';
        default:
          return isJsonNative(mapped)
              ? '$v as $mapped'
              : '$mapped.fromJson($v)';
      }
    }
    // A schema type named like a built-in scalar (e.g. `type Decimal`) is
    // handled as the type the generator declares for it.
    switch (TypeRegistry.declaresType(name) ? '' : name) {
      case 'Int':
      case 'Short':
        return 'const SafeIntConverter().fromJson($v)';
      case 'Float':
        return 'const SafeDoubleConverter().fromJson($v)';
      case 'Boolean':
        return 'const SafeBoolConverter().fromJson($v)';
      case 'String':
      case 'ID':
        return 'const SafeStringConverter().fromJson($v)';
      case 'DateTime':
        return 'const DateTimeConverter().fromJson($v)';
      case 'LocalDate':
        return 'const LocalDateConverter().fromJson($v)';
      case 'Decimal':
        return 'const SafeDecimalConverter().fromJson($v)';
      case 'Long':
        return 'const LongConverter().fromJson($v)';
      case 'Byte':
        return 'const ByteConverter().fromJson($v)';
    }
    final dartName = SchemaAnalyzer.dartTypeName(name);
    if (TypeRegistry.isEnum(name)) {
      return 'const ${dartName}Converter().fromJson($v as String)';
    }
    if (TypeRegistry.isCustomScalar(name)) {
      return 'const ${dartName}Converter().fromJson($v)';
    }
    if (TypeRegistry.objectTypes.contains(name) ||
        TypeRegistry.isAbstract(name) ||
        definedTypes.contains(name)) {
      return '$dartName.fromJson($v as Map<String, dynamic>)';
    }
    return v;
  }
}
