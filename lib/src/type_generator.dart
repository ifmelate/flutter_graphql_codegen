/// Type generation utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'code_utils.dart';
import 'document_utils.dart';
import 'naming.dart';
import 'schema_analyzer.dart';

/// Utility class for generating types, enums, and converters
class TypeGenerator {
  /// Generates a complete types file with all necessary components
  static String generateTypesFile(String schema) {
    final schemaDoc =
        DocumentUtils.mergeSchemaExtensions(gql_lang.parseString(schema));
    SchemaAnalyzer.extractCustomTypesAndEnums(schemaDoc);
    final needsConvert = _wrappedScalars(TypeRegistry.customScalars).isNotEmpty;
    final scalarConverters =
        _generateScalarConverters(TypeRegistry.customScalars);
    final enumDefinitions = _generateEnumDefinitions(schemaDoc);
    final enumConverters = _generateEnumConverters(schemaDoc);
    final typeDefinitions = _generateAllTypeDefinitions(schemaDoc, schema);

    return '''${CodeGenerationConstants.generatedFileWarning}
${CodeGenerationConstants.ignoreForFile}, unused_element

${needsConvert ? "import 'dart:convert';\n\n" : ''}import 'package:json_annotation/json_annotation.dart';

part 'types.g.dart';

class Decimal {
  final String value;
  Decimal(this.value);

  @override
  String toString() => value;

  static Decimal parse(String value) => Decimal(value);

  @override
  bool operator ==(Object other) => other is Decimal && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class Long {
  final String value;
  Long(this.value);

  @override
  String toString() => value;

  static Long parse(String value) => Long(value);

  @override
  bool operator ==(Object other) => other is Long && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class DecimalConverter implements JsonConverter<Decimal, dynamic> {
  const DecimalConverter();

  @override
  Decimal fromJson(dynamic json) {
    if (json == null) return Decimal('0');
    if (json is String) return Decimal(json);
    if (json is int) return Decimal(json.toString());
    if (json is double) return Decimal(json.toString());
    return Decimal(json.toString());
  }

  @override
  dynamic toJson(Decimal object) => object.toString();
}

class DateTimeConverter implements JsonConverter<DateTime, dynamic> {
  const DateTimeConverter();

  @override
  DateTime fromJson(dynamic json) {
    if (json == null) return DateTime.now();
    if (json is String) return DateTime.parse(json);
    return DateTime.now();
  }

  @override
  dynamic toJson(DateTime object) {
    // Always convert to UTC to ensure GraphQL-compatible format with timezone
    // GraphQL DateTime scalar requires full ISO-8601 format with timezone
    return object.toUtc().toIso8601String();
  }
}

class LocalDateConverter implements JsonConverter<DateTime, dynamic> {
  const LocalDateConverter();

  @override
  DateTime fromJson(dynamic json) {
    if (json == null) return DateTime.now();
    if (json is String) return DateTime.parse(json);
    return DateTime.now();
  }

  @override
  dynamic toJson(DateTime object) => object.toIso8601String().split('T').first;
}

class LongConverter implements JsonConverter<Long, dynamic> {
  const LongConverter();

  @override
  Long fromJson(dynamic json) {
    if (json == null) return Long('0');
    if (json is String) return Long(json);
    if (json is int) return Long(json.toString());
    if (json is double) return Long(json.toInt().toString());
    return Long(json.toString());
  }

  @override
  dynamic toJson(Long object) => object.toString();
}

class Byte {
  final int value;
  Byte(this.value);

  @override
  String toString() => value.toString();

  static Byte parse(dynamic value) {
    if (value is int) return Byte(value);
    if (value is String) return Byte(int.tryParse(value) ?? 0);
    if (value is double) return Byte(value.toInt());
    return Byte(0);
  }

  @override
  bool operator ==(Object other) => other is Byte && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class ByteConverter implements JsonConverter<Byte, dynamic> {
  const ByteConverter();

  @override
  Byte fromJson(dynamic json) {
    if (json == null) return Byte(0);
    if (json is int) return Byte(json);
    if (json is String) return Byte(int.tryParse(json) ?? 0);
    if (json is double) return Byte(json.toInt());
    return Byte(0);
  }

  @override
  dynamic toJson(Byte object) => object.value;
}

class SafeStringConverter implements JsonConverter<String, dynamic> {
  const SafeStringConverter();

  @override
  String fromJson(dynamic json) {
    if (json == null) return '';
    return json.toString();
  }

  @override
  dynamic toJson(String object) => object;
}

// Safe converters that handle null values correctly
class SafeBoolConverter implements JsonConverter<bool, dynamic> {
  const SafeBoolConverter();

  @override
  bool fromJson(dynamic json) {
    if (json == null) return false;
    if (json is bool) return json;
    if (json is String) {
      final lower = json.toLowerCase();
      return lower == 'true' || lower == '1';
    }
    if (json is num) return json != 0;
    return false;
  }

  @override
  dynamic toJson(bool object) => object;
}

class SafeIntConverter implements JsonConverter<int, dynamic> {
  const SafeIntConverter();

  @override
  int fromJson(dynamic json) {
    if (json == null) return 0;
    if (json is int) return json;
    if (json is double) return json.toInt();
    if (json is String) {
      return int.tryParse(json) ?? 0;
    }
    return 0;
  }

  @override
  dynamic toJson(int object) => object;
}

class SafeDoubleConverter implements JsonConverter<double, dynamic> {
  const SafeDoubleConverter();

  @override
  double fromJson(dynamic json) {
    if (json == null) return 0.0;
    if (json is double) return json;
    if (json is int) return json.toDouble();
    if (json is String) {
      return double.tryParse(json) ?? 0.0;
    }
    return 0.0;
  }

  @override
  dynamic toJson(double object) => object;
}

class SafeDecimalConverter implements JsonConverter<Decimal, dynamic> {
  const SafeDecimalConverter();

  @override
  Decimal fromJson(dynamic json) {
    if (json == null) return Decimal('0');
    if (json is String) return Decimal(json);
    if (json is int) return Decimal(json.toString());
    if (json is double) return Decimal(json.toString());
    return Decimal(json.toString());
  }

  @override
  dynamic toJson(Decimal object) => object.toString();
}

class EnumConverter<T> implements JsonConverter<T, String> {
  const EnumConverter(this.valueMap);

  final Map<String, T> valueMap;

  @override
  T fromJson(String json) => valueMap[json]!;

  @override
  String toJson(T object) => object.toString().split('.').last;
}

$scalarConverters

$enumDefinitions

$enumConverters

$typeDefinitions

// Helper functions for list conversions
${_generateListConverterHelpers(TypeRegistry.customScalars)}
''';
  }

  /// Custom scalars that get the generic generated wrapper class + converter.
  static Iterable<String> _wrappedScalars(Set<String> customScalars) =>
      customScalars.where((scalar) =>
          scalar != 'Decimal' &&
          scalar != 'DateTime' &&
          scalar != 'Short' &&
          scalar != 'Byte' &&
          scalar != 'Long' &&
          scalar != 'LocalDate');

  /// Generates scalar converters for custom scalar types
  static String _generateScalarConverters(Set<String> customScalars) {
    final buffer = StringBuffer();

    for (final scalar in _wrappedScalars(customScalars)) {
      buffer.writeln('''
/// Wrapper for the custom GraphQL scalar `$scalar`.
///
/// [raw] holds the JSON value exactly as received (string, number, map, ...).
class $scalar {
  final Object? raw;
  const $scalar(this.raw);

  /// String form of the value; non-string JSON values are JSON-encoded.
  String get value => raw is String ? raw as String : jsonEncode(raw);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is $scalar && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class ${scalar}Converter implements JsonConverter<$scalar, dynamic> {
  const ${scalar}Converter();

  @override
  $scalar fromJson(dynamic json) => $scalar(json);

  @override
  dynamic toJson($scalar object) => object.raw;
}
''');
    }
    return buffer.toString();
  }

  /// Generates enum definitions from schema
  static String _generateEnumDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in _sortedDefinitions(schemaDoc)) {
      if (definition is EnumTypeDefinitionNode) {
        final enumName = definition.name.value;
        buffer.writeln('enum $enumName {');
        // Sort enum values for determinism
        for (final value in _sortedEnumValues(definition)) {
          buffer.writeln('  ${dartEnumValueName(value.name.value)},');
        }
        buffer.writeln('}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Generates enum converters from schema
  static String _generateEnumConverters(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in _sortedDefinitions(schemaDoc)) {
      if (definition is EnumTypeDefinitionNode) {
        final enumName = definition.name.value;
        final values = _sortedEnumValues(definition);
        buffer.writeln(
            'class ${enumName}Converter extends JsonConverter<$enumName, String> {');
        buffer.writeln('  const ${enumName}Converter();');
        buffer.writeln();
        buffer.writeln('  @override');
        buffer.writeln('  $enumName fromJson(String json) {');
        buffer.writeln('    switch (json) {');
        for (final value in values) {
          buffer.writeln(
              "      case '${value.name.value}': return $enumName.${dartEnumValueName(value.name.value)};");
        }
        buffer.writeln(
            "      default: throw ArgumentError.value(json, 'json', 'Unknown $enumName value');");
        buffer.writeln('    }');
        buffer.writeln('  }');
        buffer.writeln();
        buffer.writeln('  @override');
        final needsMapping =
            values.any((v) => dartEnumValueName(v.name.value) != v.name.value);
        if (needsMapping) {
          buffer.writeln('  String toJson($enumName object) {');
          buffer.writeln('    switch (object) {');
          for (final value in values) {
            buffer.writeln(
                "      case $enumName.${dartEnumValueName(value.name.value)}: return '${value.name.value}';");
          }
          buffer.writeln('    }');
          buffer.writeln('  }');
        } else {
          buffer.writeln(
              '  String toJson($enumName object) => object.toString().split(".").last;');
        }
        buffer.writeln('}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  static List<DefinitionNode> _sortedDefinitions(DocumentNode schemaDoc) {
    final defs = List<DefinitionNode>.from(schemaDoc.definitions);
    defs.sort((a, b) {
      final an = (a is TypeDefinitionNode) ? a.name.value : '';
      final bn = (b is TypeDefinitionNode) ? b.name.value : '';
      return an.compareTo(bn);
    });
    return defs;
  }

  static List<EnumValueDefinitionNode> _sortedEnumValues(
      EnumTypeDefinitionNode definition) {
    return [...definition.values]
      ..sort((a, b) => a.name.value.compareTo(b.name.value));
  }

  /// Generates all type definitions from schema
  static String _generateAllTypeDefinitions(
      DocumentNode schemaDoc, String schema) {
    final buffer = StringBuffer();

    final interfaces = <String, InterfaceTypeDefinitionNode>{
      for (final def
          in schemaDoc.definitions.whereType<InterfaceTypeDefinitionNode>())
        def.name.value: def,
    };

    for (final definition in _sortedDefinitions(schemaDoc)) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(_generateTypeDefinition(definition, schema, interfaces));
      } else if (definition is InputObjectTypeDefinitionNode) {
        buffer.writeln(_generateInputTypeDefinition(definition, schema));
      } else if (definition is InterfaceTypeDefinitionNode) {
        buffer.writeln(_generateInterfaceDefinition(definition, interfaces));
      } else if (definition is UnionTypeDefinitionNode) {
        buffer.writeln(_generateUnionDefinition(definition));
      }
    }

    return buffer.toString();
  }

  /// Names of all fields declared by [typeName]'s interfaces (transitively).
  static Set<String> _inheritedFieldNames(
    String typeName,
    Map<String, InterfaceTypeDefinitionNode> interfaces, [
    Set<String>? visited,
  ]) {
    visited ??= <String>{};
    final names = <String>{};
    for (final superName in TypeRegistry.supertypes(typeName)) {
      final iface = interfaces[superName];
      if (iface == null || !visited.add(superName)) continue;
      names.addAll(iface.fields.map((f) => f.name.value));
      names.addAll(_inheritedFieldNames(superName, interfaces, visited));
    }
    return names;
  }

  /// Generates a type definition for a specific object type
  static String _generateTypeDefinition(ObjectTypeDefinitionNode typeNode,
      [String schema = '',
      Map<String, InterfaceTypeDefinitionNode> interfaces = const {}]) {
    final typeName = typeNode.name.value;
    return _generateJsonClass(
      className: typeName,
      fields: [for (final f in typeNode.fields) (f.name.value, f.type)],
      supertypes: TypeRegistry.supertypes(typeName),
      overriddenFields: _inheritedFieldNames(typeName, interfaces),
    );
  }

  /// Generates a type definition for a specific input type
  static String _generateInputTypeDefinition(
      InputObjectTypeDefinitionNode inputNode,
      [String schema = '']) {
    return _generateJsonClass(
      className: inputNode.name.value,
      fields: [for (final f in inputNode.fields) (f.name.value, f.type)],
    );
  }

  /// Generates an abstract class for a GraphQL interface plus an `Unknown*`
  /// fallback implementation used for unrecognised `__typename` values.
  static String _generateInterfaceDefinition(
    InterfaceTypeDefinitionNode node,
    Map<String, InterfaceTypeDefinitionNode> interfaces,
  ) {
    final name = node.name.value;
    final supertypes = TypeRegistry.supertypes(name);
    final inherited = _inheritedFieldNames(name, interfaces);
    final unknownName = 'Unknown$name';
    final sortedFields = [...node.fields]
      ..sort((a, b) => a.name.value.compareTo(b.name.value));

    final buffer = StringBuffer();
    buffer.writeln('/// GraphQL interface `$name`.');
    final impl =
        supertypes.isEmpty ? '' : ' implements ${supertypes.join(', ')}';
    buffer.writeln('abstract class $name$impl {');
    for (final field in sortedFields) {
      final fieldName = field.name.value;
      if (inherited.contains(fieldName)) buffer.writeln('  @override');
      buffer.writeln(
          '  ${SchemaAnalyzer.getDartType(field.type)} get ${dartFieldName(fieldName, className: name)};');
    }
    buffer.writeln();
    buffer.writeln(
        '  /// Creates the concrete implementation matching `__typename`.');
    buffer.writeln('  factory $name.fromJson(Map<String, dynamic> json) {');
    buffer.write(_typenameDispatch(name, '$unknownName.fromJson(json)'));
    buffer.writeln('  }');
    buffer.writeln();
    if (supertypes.isNotEmpty) buffer.writeln('  @override');
    buffer.writeln('  Map<String, dynamic> toJson();');
    buffer.writeln('}');
    buffer.writeln();

    buffer.writeln(
        '/// Fallback for `$name` implementations unknown at generation time.');
    buffer.write(_generateJsonClass(
      className: unknownName,
      fields: [for (final f in node.fields) (f.name.value, f.type)],
      supertypes: [name],
      overriddenFields: node.fields.map((f) => f.name.value).toSet(),
      fieldNameClassName: name,
    ));
    return buffer.toString();
  }

  /// Generates an abstract class for a GraphQL union plus an `Unknown*`
  /// fallback that keeps the raw JSON.
  static String _generateUnionDefinition(UnionTypeDefinitionNode node) {
    final name = node.name.value;
    final unknownName = 'Unknown$name';
    return '''
/// GraphQL union `$name`.
abstract class $name {
  /// Creates the concrete member type matching `__typename`.
  factory $name.fromJson(Map<String, dynamic> json) {
${_typenameDispatch(name, '$unknownName(json)')}  }

  Map<String, dynamic> toJson();
}

/// Fallback for `$name` members unknown at generation time.
class $unknownName implements $name {
  const $unknownName(this.json);

  final Map<String, dynamic> json;

  String? get typename => json['__typename'] as String?;

  @override
  Map<String, dynamic> toJson() => json;
}

''';
  }

  static String _typenameDispatch(String abstractType, String fallback) {
    final buffer = StringBuffer();
    buffer.writeln("    switch (json['__typename']) {");
    for (final concrete in TypeRegistry.possibleTypes(abstractType)) {
      buffer.writeln("      case '$concrete':");
      buffer.writeln('        return $concrete.fromJson(json);');
    }
    buffer.writeln('      default:');
    buffer.writeln('        return $fallback;');
    buffer.writeln('    }');
    return buffer.toString();
  }

  /// Generates a json_serializable class with the given fields.
  ///
  /// [fieldNameClassName] is the class name used to detect member/class name
  /// clashes; it defaults to [className] (but `Unknown*` classes must use the
  /// interface name so field names match the interface getters).
  static String _generateJsonClass({
    required String className,
    required List<(String, TypeNode)> fields,
    List<String> supertypes = const [],
    Set<String> overriddenFields = const {},
    String? fieldNameClassName,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
        '@JsonSerializable(includeIfNull: false, explicitToJson: true, fieldRename: FieldRename.none)');
    final impl =
        supertypes.isEmpty ? '' : ' implements ${supertypes.join(', ')}';
    buffer.writeln('class $className$impl {');

    // Sort fields deterministically by name
    final sortedFields = [...fields]..sort((a, b) => a.$1.compareTo(b.$1));

    for (final (fieldName, type) in sortedFields) {
      final dartName =
          dartFieldName(fieldName, className: fieldNameClassName ?? className);
      if (overriddenFields.contains(fieldName)) buffer.writeln('  @override');
      for (final line in _fieldAnnotations(fieldName, dartName, type)) {
        buffer.writeln(line);
      }
      buffer.writeln('  ${SchemaAnalyzer.getDartType(type)} $dartName;');
    }

    buffer.writeln();
    buffer.writeln('  $className({');
    for (final (fieldName, type) in sortedFields) {
      final dartName =
          dartFieldName(fieldName, className: fieldNameClassName ?? className);
      final fieldType = SchemaAnalyzer.getDartType(type);
      if (fieldType.startsWith('List<')) {
        // For list fields, provide empty list as default
        buffer.writeln('    this.$dartName = const [],');
      } else if (fieldType.endsWith('?')) {
        buffer.writeln('    this.$dartName,');
      } else {
        buffer.writeln('    required this.$dartName,');
      }
    }
    buffer.writeln('  });');

    buffer.writeln();
    buffer.writeln(
        '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');
    if (supertypes.isNotEmpty) buffer.writeln('  @override');
    buffer.writeln(
        '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');

    buffer.writeln('}');
    buffer.writeln();

    return buffer.toString();
  }

  /// Annotation lines (indented) for a generated field.
  static List<String> _fieldAnnotations(
      String fieldName, String dartName, TypeNode type) {
    final fieldType = SchemaAnalyzer.getDartType(type);
    final baseType = fieldType
        .replaceAll('?', '')
        .replaceAll('List<', '')
        .replaceAll('>', '');
    final isListField = fieldType.startsWith('List<');
    final isNullable = fieldType.endsWith('?');

    // Add @JsonKey annotation for field name preservation so json_serializable
    // never renames GraphQL fields (and escaped Dart names map back).
    final needsJsonKeyName =
        _needsJsonKeyForFieldName(fieldName) || dartName != fieldName;
    final nameArg = needsJsonKeyName ? "name: '$fieldName', " : '';
    final nameKey = "  @JsonKey(name: '$fieldName')";

    List<String> withName(String converter) =>
        [if (needsJsonKeyName) nameKey, converter];

    if (isListField) {
      // Check if the list contains custom types that need converters
      final innerType = fieldType.substring(
          5, fieldType.length - (fieldType.endsWith('>?') ? 2 : 1));
      final cleanInnerType = innerType.replaceAll('?', '');

      if (TypeRegistry.isCustomScalar(cleanInnerType) &&
          cleanInnerType != 'Decimal' &&
          cleanInnerType != 'Short' &&
          cleanInnerType != 'Byte') {
        // For lists of custom scalars, use JsonKey with converter
        final helper = cleanInnerType.toLowerCase();
        return [
          '  @JsonKey(${nameArg}defaultValue: const <$cleanInnerType>[], fromJson: _${helper}ListFromJson, toJson: _${helper}ListToJson)'
        ];
      }
      if (cleanInnerType == 'DateTime') {
        // Distinguish between DateTime and LocalDate list elements
        final helper = getOriginalGraphQLType(type) == 'LocalDate'
            ? 'localDate'
            : 'dateTime';
        return [
          '  @JsonKey(${nameArg}defaultValue: const <DateTime>[], fromJson: _${helper}ListFromJson, toJson: _${helper}ListToJson)'
        ];
      }
      if (cleanInnerType == 'LocalDate') {
        return [
          '  @JsonKey(${nameArg}defaultValue: const <DateTime>[], fromJson: _localDateListFromJson, toJson: _localDateListToJson)'
        ];
      }
      if (cleanInnerType == 'Decimal') {
        return [
          '  @JsonKey(${nameArg}defaultValue: const <Decimal>[], fromJson: _decimalListFromJson, toJson: _decimalListToJson)'
        ];
      }
      if (cleanInnerType == 'Byte') {
        return [
          '  @JsonKey(${nameArg}defaultValue: const <Byte>[], fromJson: _byteListFromJson, toJson: _byteListToJson)'
        ];
      }
      // Regular lists (enums, objects, built-in scalars): default value only
      return ['  @JsonKey(${nameArg}defaultValue: const <$cleanInnerType>[])'];
    }

    if (baseType == 'DateTime') {
      // Distinguish between DateTime and LocalDate
      return withName(getOriginalGraphQLType(type) == 'LocalDate'
          ? '  @LocalDateConverter()'
          : '  @DateTimeConverter()');
    }
    if (baseType == 'LocalDate') return withName('  @LocalDateConverter()');
    if (baseType == 'Decimal') return withName('  @SafeDecimalConverter()');
    if (baseType == 'Long') return withName('  @LongConverter()');
    if (baseType == 'Byte') return withName('  @ByteConverter()');
    if (TypeRegistry.isEnum(baseType)) {
      return withName('  @${baseType}Converter()');
    }
    if (TypeRegistry.isCustomScalar(baseType) &&
        baseType != 'Decimal' &&
        baseType != 'Long' &&
        baseType != 'Short' &&
        baseType != 'Byte') {
      return withName('  @${baseType}Converter()');
    }
    // Safe converters for non-nullable primitives
    if (baseType == 'bool' && !isNullable) {
      return withName('  @SafeBoolConverter()');
    }
    if (baseType == 'int' && !isNullable) {
      return withName('  @SafeIntConverter()');
    }
    if (baseType == 'double' && !isNullable) {
      return withName('  @SafeDoubleConverter()');
    }
    return [if (needsJsonKeyName) nameKey];
  }

  /// Determines if a field name needs explicit JsonKey annotation to preserve naming
  /// This prevents json_serializable from converting camelCase to snake_case
  static bool _needsJsonKeyForFieldName(String fieldName) {
    // Check if the field name contains uppercase letters (indicating camelCase)
    // We preserve all field names to maintain consistency with GraphQL responses
    return fieldName.contains(RegExp(r'[A-Z]')) || fieldName.length > 1;
  }

  /// Generates a class for an object type (legacy method, kept for compatibility)
  static String generateClassForType(ObjectTypeDefinitionNode type) {
    final className = type.name.value;
    final fields = type.fields;

    final classBuffer = StringBuffer();
    classBuffer.writeln('@JsonSerializable()');
    classBuffer.writeln('class $className {');

    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);
      final baseType = fieldType
          .replaceAll('?', '')
          .replaceAll('List<', '')
          .replaceAll('>', '');

      // Check if this is a list field
      final isListField = fieldType.startsWith('List<');

      if (isListField) {
        // Check if the list contains custom types that need converters
        final innerType = fieldType.substring(
            5, fieldType.length - (fieldType.endsWith('>?') ? 2 : 1));
        final cleanInnerType = innerType.replaceAll('?', '');

        // Add converter annotation for custom scalar types in lists
        if (TypeRegistry.isCustomScalar(cleanInnerType) &&
            cleanInnerType != 'Decimal' &&
            cleanInnerType != 'Short' &&
            cleanInnerType != 'Byte') {
          // For lists of custom scalars, use JsonKey with converter
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _${cleanInnerType.toLowerCase()}ListFromJson, toJson: _${cleanInnerType.toLowerCase()}ListToJson)');
        } else if (cleanInnerType == 'DateTime') {
          // Get original GraphQL type for list element to distinguish between DateTime and LocalDate
          final originalListType = getOriginalGraphQLType(field.type);
          if (originalListType == 'LocalDate') {
            classBuffer.writeln(
                '  @JsonKey(defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
          } else {
            classBuffer.writeln(
                '  @JsonKey(defaultValue: [], fromJson: _dateTimeListFromJson, toJson: _dateTimeListToJson)');
          }
        } else if (cleanInnerType == 'LocalDate') {
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
        } else if (cleanInnerType == 'Decimal') {
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _decimalListFromJson, toJson: _decimalListToJson)');
        } else if (cleanInnerType == 'Byte') {
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _byteListFromJson, toJson: _byteListToJson)');
        } else if (TypeRegistry.isEnum(cleanInnerType)) {
          classBuffer.writeln('  @JsonKey(defaultValue: [])');
        } else {
          // For regular lists (including object lists), just use default value
          classBuffer.writeln('  @JsonKey(defaultValue: [])');
        }
      } else if (baseType == 'DateTime') {
        // Get original GraphQL type to distinguish between DateTime and LocalDate
        final originalType = getOriginalGraphQLType(field.type);
        if (originalType == 'LocalDate') {
          classBuffer.writeln('  @LocalDateConverter()');
        } else {
          classBuffer.writeln('  @DateTimeConverter()');
        }
      } else if (baseType == 'Decimal') {
        classBuffer.writeln('  @SafeDecimalConverter()');
      } else if (baseType == 'Long') {
        classBuffer.writeln('  @LongConverter()');
      } else if (baseType == 'Byte') {
        classBuffer.writeln('  @ByteConverter()');
      } else if (TypeRegistry.isEnum(baseType)) {
        classBuffer.writeln('  @${baseType}Converter()');
      } else if (!GraphQLConstants.builtInScalars.contains(baseType) &&
          !GraphQLConstants.scalarToDartType.containsKey(baseType) &&
          TypeRegistry.isCustomScalar(baseType) &&
          baseType != 'Decimal' &&
          baseType != 'Long' &&
          baseType != 'Short' &&
          baseType != 'Byte') {
        classBuffer.writeln('  @${baseType}Converter()');
      }

      classBuffer.writeln('  final $fieldType ${fieldName.toCamelCase()};');
    }

    classBuffer.writeln();
    classBuffer.writeln('  $className({');
    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);

      final isNullable = fieldType.endsWith('?');
      final isListField = fieldType.startsWith('List<');

      // Special handling for boolean fields that we made nullable for safety
      final isBooleanMadeNullable = fieldType == 'bool' && !isNullable;
      // Special handling for numeric fields that we made nullable for safety
      final isNumericMadeNullable =
          (fieldType == 'int' || fieldType == 'double') && !isNullable;

      // Lists are now always nullable, so they don't need 'required'
      // Other nullable fields also don't need 'required'
      if (isListField) {
        // For list fields, provide empty list as default
        classBuffer.writeln('    this.$fieldName = const [],');
      } else if (isBooleanMadeNullable) {
        // Boolean fields made nullable for safety don't need 'required'
        classBuffer.writeln('    this.$fieldName,');
      } else if (isNumericMadeNullable) {
        // Numeric fields made nullable for safety don't need 'required'
        classBuffer.writeln('    this.$fieldName,');
      } else if (isNullable) {
        classBuffer.writeln('    this.$fieldName,');
      } else {
        classBuffer.writeln('    required this.$fieldName,');
      }
    }
    classBuffer.writeln('  });');

    classBuffer.writeln();
    classBuffer.writeln(
        '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');
    classBuffer.writeln(
        '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');

    classBuffer.writeln('}');

    return classBuffer.toString();
  }

  /// Generates type definitions for older API compatibility
  static String generateTypeDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    // Sort deterministically
    final defs = List<DefinitionNode>.from(schemaDoc.definitions);
    defs.sort((a, b) {
      final an = (a is TypeDefinitionNode) ? a.name.value : '';
      final bn = (b is TypeDefinitionNode) ? b.name.value : '';
      return an.compareTo(bn);
    });

    for (final definition in defs) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(generateClassForType(definition));
      }
    }

    return buffer.toString();
  }

  /// Generates helper functions for list conversions
  static String _generateListConverterHelpers(Set<String> customScalars) {
    final buffer = StringBuffer();

    // Generate helpers for each custom scalar type
    for (final scalar in _wrappedScalars(customScalars)) {
      buffer.writeln('''
// Helper functions for $scalar list conversion
List<$scalar>? _${scalar.toLowerCase()}ListFromJson(List<dynamic>? json) {
  if (json == null) return null;
  return json.map((item) => $scalar(item)).toList();
}

List<dynamic>? _${scalar.toLowerCase()}ListToJson(List<$scalar>? list) {
  if (list == null) return null;
  return list.map((item) => item.raw).toList();
}
''');
    }

    // Helper for DateTime lists
    buffer.writeln('''
// Helper functions for DateTime list conversion
List<DateTime>? _dateTimeListFromJson(List<dynamic>? json) {
  if (json == null) return null;
  return json.map((item) => DateTime.parse(item.toString())).toList();
}

List<String>? _dateTimeListToJson(List<DateTime>? list) {
  if (list == null) return null;
  // Same wire format as DateTimeConverter: UTC ISO-8601 with timezone.
  return list.map((item) => item.toUtc().toIso8601String()).toList();
}

// Helper functions for LocalDate list conversion
List<DateTime>? _localDateListFromJson(List<dynamic>? json) {
  if (json == null) return null;
  return json.map((item) => DateTime.parse(item.toString())).toList();
}

List<String>? _localDateListToJson(List<DateTime>? list) {
  if (list == null) return null;
  return list.map((item) => item.toIso8601String().split('T').first).toList();
}
''');

    // Helper for Decimal lists
    buffer.writeln('''
// Helper functions for Decimal list conversion
List<Decimal>? _decimalListFromJson(List<dynamic>? json) {
  if (json == null) return null;
  return json.map((item) => Decimal(item.toString())).toList();
}

List<String>? _decimalListToJson(List<Decimal>? list) {
  if (list == null) return null;
  return list.map((item) => item.toString()).toList();
}

// Helper functions for Byte list conversion
List<Byte> _byteListFromJson(List<dynamic>? json) {
  if (json == null) return const <Byte>[];
  return json.map((item) => Byte.parse(item)).toList();
}

List<dynamic>? _byteListToJson(List<Byte>? list) {
  if (list == null) return null;
  return list.map((item) => item.value).toList();
}
''');

    return buffer.toString();
  }

  // Method removed - was unused

  /// Gets the original GraphQL type name from a TypeNode without mapping
  static String getOriginalGraphQLType(TypeNode type) {
    if (type is NamedTypeNode) {
      return type.name.value;
    } else if (type is ListTypeNode) {
      return getOriginalGraphQLType(type.type);
    }
    return 'dynamic';
  }

  /// Gets the Dart type from a TypeNode but preserves original type name for converter logic
  static String getDartTypeFromOriginal(
      String originalType, bool isNullable, bool isList) {
    String dartType;

    switch (originalType) {
      case 'Int':
        dartType = 'int';
        break;
      case 'Float':
        dartType = 'double';
        break;
      case 'String':
        dartType = 'String';
        break;
      case 'Boolean':
        dartType = 'bool';
        break;
      case 'ID':
        dartType = 'String';
        break;
      case 'Short':
        dartType = 'int';
        break;
      case 'DateTime':
      case 'LocalDate':
        dartType = 'DateTime';
        break;
      case 'Decimal':
        dartType = 'Decimal';
        break;
      case 'Long':
        dartType = 'Long';
        break;
      case 'Byte':
        dartType = 'Byte';
        break;
      default:
        dartType = originalType;
        break;
    }

    if (isList) {
      return isNullable ? 'List<$dartType>?' : 'List<$dartType>';
    }

    return isNullable ? '$dartType?' : dartType;
  }
}
