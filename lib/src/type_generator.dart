/// Type generation utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'code_utils.dart';
import 'schema_analyzer.dart';

/// Utility class for generating types, enums, and converters
class TypeGenerator {
  /// Generates a complete types file with all necessary components
  static String generateTypesFile(String schema) {
    final schemaDoc = gql_lang.parseString(schema);
    SchemaAnalyzer.extractCustomTypesAndEnums(schemaDoc);
    final scalarConverters =
        _generateScalarConverters(TypeRegistry.customScalars);
    final enumDefinitions = _generateEnumDefinitions(schemaDoc);
    final enumConverters = _generateEnumConverters(schemaDoc);
    final typeDefinitions = _generateAllTypeDefinitions(schemaDoc, schema);

    return '''${CodeGenerationConstants.generatedFileWarning}

import 'package:json_annotation/json_annotation.dart';

part 'types.g.dart';

class Decimal {
  final String value;
  Decimal(this.value);

  @override
  String toString() => value;

  static Decimal parse(String value) => Decimal(value);
}

class Long {
  final String value;
  Long(this.value);

  @override
  String toString() => value;

  static Long parse(String value) => Long(value);
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
  String toJson(DateTime object) {
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
  String toJson(DateTime object) => object.toIso8601String().split('T').first;
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

  /// Generates scalar converters for custom scalar types
  static String _generateScalarConverters(Set<String> customScalars) {
    final buffer = StringBuffer();

    for (final scalar in customScalars) {
      if (scalar != 'Decimal' &&
          scalar != 'DateTime' &&
          scalar != 'Short' &&
          scalar != 'Byte' &&
          scalar != 'Long' &&
          scalar != 'LocalDate') {
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

  /// Generates enum definitions from schema
  static String _generateEnumDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in schemaDoc.definitions) {
      if (definition is EnumTypeDefinitionNode) {
        final enumName = definition.name.value;
        buffer.writeln('enum $enumName {');
        for (final value in definition.values) {
          buffer.writeln('  ${value.name.value},');
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

    for (final definition in schemaDoc.definitions) {
      if (definition is EnumTypeDefinitionNode) {
        final enumName = definition.name.value;
        buffer.writeln(
            'class ${enumName}Converter extends JsonConverter<$enumName, String> {');
        buffer.writeln('  const ${enumName}Converter();');
        buffer.writeln();
        buffer.writeln('  @override');
        buffer.writeln('  $enumName fromJson(String json) {');
        buffer.writeln('    switch (json) {');
        for (final value in definition.values) {
          buffer.writeln(
              "      case '${value.name.value}': return $enumName.${value.name.value};");
        }
        buffer.writeln(
            "      default: throw Exception('Unknown enum value \$json for $enumName');");
        buffer.writeln('    }');
        buffer.writeln('  }');
        buffer.writeln();
        buffer.writeln('  @override');
        buffer.writeln(
            '  String toJson($enumName object) => object.toString().split(".").last;');
        buffer.writeln('}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Generates all type definitions from schema
  static String _generateAllTypeDefinitions(
      DocumentNode schemaDoc, String schema) {
    final buffer = StringBuffer();

    for (final definition in schemaDoc.definitions) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(_generateTypeDefinition(definition, schema));
      } else if (definition is InputObjectTypeDefinitionNode) {
        buffer.writeln(_generateInputTypeDefinition(definition, schema));
      }
    }

    return buffer.toString();
  }

  /// Generates a type definition for a specific object type
  static String _generateTypeDefinition(ObjectTypeDefinitionNode typeNode,
      [String schema = '']) {
    final typeName = typeNode.name.value;
    final fields = typeNode.fields;

    final buffer = StringBuffer();
    buffer.writeln(
        '@JsonSerializable(includeIfNull: false, explicitToJson: true, fieldRename: FieldRename.none)');
    buffer.writeln('class $typeName {');

    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);
      final baseType = fieldType
          .replaceAll('?', '')
          .replaceAll('List<', '')
          .replaceAll('>', '');

      // Check if this is a list field
      final isListField = fieldType.startsWith('List<');
      final isNullable = fieldType.endsWith('?');

      // Add @JsonKey annotation for field name preservation
      // This ensures that camelCase field names from GraphQL are preserved
      // instead of being converted to snake_case by json_serializable
      final needsJsonKeyName = _needsJsonKeyForFieldName(fieldName);

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
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _${cleanInnerType.toLowerCase()}ListFromJson, toJson: _${cleanInnerType.toLowerCase()}ListToJson)');
        } else if (cleanInnerType == 'DateTime') {
          // Get original GraphQL type for list element to distinguish between DateTime and LocalDate
          final originalListType = getOriginalGraphQLType(field.type);
          if (originalListType == 'LocalDate') {
            buffer.writeln(
                '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
          } else {
            buffer.writeln(
                '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _dateTimeListFromJson, toJson: _dateTimeListToJson)');
          }
        } else if (cleanInnerType == 'LocalDate') {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
        } else if (cleanInnerType == 'Decimal') {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _decimalListFromJson, toJson: _decimalListToJson)');
        } else if (cleanInnerType == 'Byte') {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _byteListFromJson, toJson: _byteListToJson)');
        } else if (TypeRegistry.isEnum(cleanInnerType)) {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [])');
        } else {
          // For regular lists (including object lists), just use default value
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [])');
        }
      } else if (baseType == 'DateTime') {
        // Get original GraphQL type to distinguish between DateTime and LocalDate
        final originalType = getOriginalGraphQLType(field.type);
        print(
            'DEBUG: Field $fieldName - baseType: $baseType, originalType: $originalType');
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        if (originalType == 'LocalDate') {
          buffer.writeln('  @LocalDateConverter()');
        } else {
          buffer.writeln('  @DateTimeConverter()');
        }
      } else if (baseType == 'LocalDate') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @LocalDateConverter()');
      } else if (baseType == 'Decimal') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeDecimalConverter()');
      } else if (baseType == 'Long') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @LongConverter()');
      } else if (baseType == 'Byte') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @ByteConverter()');
      } else if (TypeRegistry.isEnum(baseType)) {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @${baseType}Converter()');
      } else if (TypeRegistry.isCustomScalar(baseType) &&
          baseType != 'Decimal' &&
          baseType != 'Long' &&
          baseType != 'Short' &&
          baseType != 'Byte') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @${baseType}Converter()');
      } else if (baseType == 'bool' && !isNullable) {
        // Use safe bool converter for non-nullable boolean fields
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeBoolConverter()');
      } else if (baseType == 'int' && !isNullable) {
        // Use safe int converter for non-nullable integer fields
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeIntConverter()');
      } else if (baseType == 'double' && !isNullable) {
        // Use safe double converter for non-nullable double fields
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeDoubleConverter()');
      } else if (needsJsonKeyName) {
        // For any other field that needs name preservation
        buffer.writeln('  @JsonKey(name: \'$fieldName\')');
      }

      buffer.writeln('  $fieldType $fieldName;');
    }

    buffer.writeln();
    buffer.writeln('  $typeName({');
    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);

      final isNullable = fieldType.endsWith('?');
      final isListField = fieldType.startsWith('List<');

      // Lists are now always nullable, so they don't need 'required'
      // Other nullable fields also don't need 'required'
      if (isListField) {
        // For list fields, provide empty list as default
        buffer.writeln('    this.$fieldName = const [],');
      } else if (isNullable) {
        buffer.writeln('    this.$fieldName,');
      } else {
        buffer.writeln('    required this.$fieldName,');
      }
    }
    buffer.writeln('  });');

    buffer.writeln();
    buffer.writeln(
        '  factory $typeName.fromJson(Map<String, dynamic> json) => _\$${typeName}FromJson(json);');
    buffer.writeln(
        '  Map<String, dynamic> toJson() => _\$${typeName}ToJson(this);');

    buffer.writeln('}');
    buffer.writeln();

    return buffer.toString();
  }

  /// Determines if a field name needs explicit JsonKey annotation to preserve naming
  /// This prevents json_serializable from converting camelCase to snake_case
  static bool _needsJsonKeyForFieldName(String fieldName) {
    // Check if the field name contains uppercase letters (indicating camelCase)
    // We preserve all field names to maintain consistency with GraphQL responses
    return fieldName.contains(RegExp(r'[A-Z]')) || fieldName.length > 1;
  }

  /// Generates a type definition for a specific input type
  static String _generateInputTypeDefinition(
      InputObjectTypeDefinitionNode inputNode,
      [String schema = '']) {
    final typeName = inputNode.name.value;
    final fields = inputNode.fields;

    final buffer = StringBuffer();
    buffer.writeln(
        '@JsonSerializable(includeIfNull: false, explicitToJson: true, fieldRename: FieldRename.none)');
    buffer.writeln('class $typeName {');

    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);
      final baseType = fieldType
          .replaceAll('?', '')
          .replaceAll('List<', '')
          .replaceAll('>', '');

      // Check if this is a list field
      final isListField = fieldType.startsWith('List<');
      final isNullable = fieldType.endsWith('?');

      // Add @JsonKey annotation for field name preservation (same as in object types)
      final needsJsonKeyName = _needsJsonKeyForFieldName(fieldName);

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
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _${cleanInnerType.toLowerCase()}ListFromJson, toJson: _${cleanInnerType.toLowerCase()}ListToJson)');
        } else if (cleanInnerType == 'DateTime') {
          // Get original GraphQL type for list element to distinguish between DateTime and LocalDate
          final originalListType = getOriginalGraphQLType(field.type);
          if (originalListType == 'LocalDate') {
            buffer.writeln(
                '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
          } else {
            buffer.writeln(
                '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _dateTimeListFromJson, toJson: _dateTimeListToJson)');
          }
        } else if (cleanInnerType == 'LocalDate') {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
        } else if (cleanInnerType == 'Decimal') {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _decimalListFromJson, toJson: _decimalListToJson)');
        } else if (cleanInnerType == 'Byte') {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [], fromJson: _byteListFromJson, toJson: _byteListToJson)');
        } else if (TypeRegistry.isEnum(cleanInnerType)) {
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [])');
        } else {
          // For regular lists (including object lists), just use default value
          buffer.writeln(
              '  @JsonKey(${needsJsonKeyName ? 'name: \'$fieldName\', ' : ''}defaultValue: [])');
        }
      } else if (baseType == 'DateTime') {
        // Get original GraphQL type to distinguish between DateTime and LocalDate
        final originalType = getOriginalGraphQLType(field.type);
        print(
            'DEBUG: Field $fieldName - baseType: $baseType, originalType: $originalType');
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        if (originalType == 'LocalDate') {
          buffer.writeln('  @LocalDateConverter()');
        } else {
          buffer.writeln('  @DateTimeConverter()');
        }
      } else if (baseType == 'LocalDate') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @LocalDateConverter()');
      } else if (baseType == 'Decimal') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeDecimalConverter()');
      } else if (baseType == 'Long') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @LongConverter()');
      } else if (baseType == 'Byte') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @ByteConverter()');
      } else if (TypeRegistry.isEnum(baseType)) {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @${baseType}Converter()');
      } else if (TypeRegistry.isCustomScalar(baseType) &&
          baseType != 'Decimal' &&
          baseType != 'Long' &&
          baseType != 'Short' &&
          baseType != 'Byte') {
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @${baseType}Converter()');
      } else if (baseType == 'bool' && !isNullable) {
        // Use safe bool converter for non-nullable boolean fields
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeBoolConverter()');
      } else if (baseType == 'int' && !isNullable) {
        // Use safe int converter for non-nullable integer fields
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeIntConverter()');
      } else if (baseType == 'double' && !isNullable) {
        // Use safe double converter for non-nullable double fields
        if (needsJsonKeyName) {
          buffer.writeln('  @JsonKey(name: \'$fieldName\')');
        }
        buffer.writeln('  @SafeDoubleConverter()');
      } else if (needsJsonKeyName) {
        // For any other field that needs name preservation
        buffer.writeln('  @JsonKey(name: \'$fieldName\')');
      }

      buffer.writeln('  $fieldType $fieldName;');
    }

    buffer.writeln();
    buffer.writeln('  $typeName({');
    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);

      final isNullable = fieldType.endsWith('?');
      final isListField = fieldType.startsWith('List<');

      // Lists are now always nullable, so they don't need 'required'
      // Other nullable fields also don't need 'required'
      if (isListField) {
        // For list fields, provide empty list as default
        buffer.writeln('    this.$fieldName = const [],');
      } else if (isNullable) {
        buffer.writeln('    this.$fieldName,');
      } else {
        buffer.writeln('    required this.$fieldName,');
      }
    }
    buffer.writeln('  });');

    buffer.writeln();
    buffer.writeln(
        '  factory $typeName.fromJson(Map<String, dynamic> json) => _\$${typeName}FromJson(json);');
    buffer.writeln(
        '  Map<String, dynamic> toJson() => _\$${typeName}ToJson(this);');

    buffer.writeln('}');
    buffer.writeln();

    return buffer.toString();
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

    for (final definition in schemaDoc.definitions) {
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
    for (final scalar in customScalars) {
      if (scalar != 'Decimal' &&
          scalar != 'DateTime' &&
          scalar != 'Short' &&
          scalar != 'Byte' &&
          scalar != 'Long' &&
          scalar != 'LocalDate') {
        buffer.writeln('''
// Helper functions for $scalar list conversion
List<$scalar>? _${scalar.toLowerCase()}ListFromJson(List<dynamic>? json) {
  if (json == null) return null;
  return json.map((item) => $scalar(item.toString())).toList();
}

List<dynamic>? _${scalar.toLowerCase()}ListToJson(List<$scalar>? list) {
  if (list == null) return null;
  return list.map((item) => item.toString()).toList();
}
''');
      }
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
  return list.map((item) => item.toIso8601String()).toList();
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
List<Byte>? _byteListFromJson(List<dynamic>? json) {
  if (json == null) return null;
  return json.map((item) => Byte.parse(item)).toList();
}

List<dynamic>? _byteListToJson(List<Byte>? list) {
  if (list == null) return null;
  return list.map((item) => item.value).toList();
}
''');

    return buffer.toString();
  }

  /// Returns the appropriate DateTime converter for all fields
  /// Always uses DateTimeConverter with full ISO string format
  static String _getDateTimeConverterForField(
      String fieldName, String typeName, String schema,
      [Map<String, String>? dateConverterConfig]) {
    // Always use DateTimeConverter - let the backend parse the ISO format appropriately
    return 'DateTimeConverter';
  }

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
