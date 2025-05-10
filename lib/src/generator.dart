import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'dart:developer' as developer;

class GraphQLCodeGenerator {
  static Set<String> _customScalars = Set<String>();
  static Set<String> _enumTypes = Set<String>();

  static final Set<String> _builtInScalars = {
    'Int',
    'Float',
    'String',
    'Boolean',
    'ID'
  };
  static final Map<String, String> _scalarToDartType = {
    'Int': 'int',
    'Float': 'double',
    'String': 'String',
    'Boolean': 'bool',
    'ID': 'String',
  };

  static void _extractCustomTypesAndEnums(DocumentNode schemaDoc) {
    _customScalars.clear();
    _enumTypes.clear();
    for (final definition in schemaDoc.definitions) {
      if (definition is TypeDefinitionNode) {
        final typeName = definition.name.value;
        if (definition is ScalarTypeDefinitionNode &&
            !_builtInScalars.contains(typeName) &&
            typeName != 'Decimal') {
          _customScalars.add(typeName);
        } else if (definition is EnumTypeDefinitionNode) {
          _enumTypes.add(typeName);
        }
      }
    }
  }

  static String generateTypesFile(String schema) {
    final schemaDoc = gql_lang.parseString(schema);
    _extractCustomTypesAndEnums(schemaDoc);
    final scalarConverters = _generateScalarConverters(_customScalars);
    final enumDefinitions = _generateEnumDefinitions(schemaDoc);
    final enumConverters = _generateEnumConverters(schemaDoc);
    final typeDefinitions = _generateAllTypeDefinitions(schemaDoc);

    // Проверяем, содержит ли схема тип Decimal
    final hasDecimalType = _customScalars.contains('Decimal') ||
        schemaDoc.definitions.any((def) =>
            def is ScalarTypeDefinitionNode && def.name.value == 'Decimal');

    return '''
import 'package:json_annotation/json_annotation.dart';

part 'types.g.dart';

class Decimal {
  final String value;
  Decimal(this.value);

  @override
  String toString() => value;

  static Decimal parse(String value) => Decimal(value);
}

class DecimalConverter implements JsonConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromJson(String json) => Decimal(json);

  @override
  String toJson(Decimal object) => object.toString();
}


class DateTimeConverter implements JsonConverter<DateTime, String> {
  const DateTimeConverter();

  @override
  DateTime fromJson(String json) => DateTime.parse(json);

  @override
  String toJson(DateTime object) => object.toString();
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
''';
  }

  static String generateCode(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
    String typesContent,
  ) {
    final schemaDoc = gql_lang.parseString(schema);

    final customScalars = _extractCustomScalars(schemaDoc);
    final scalarConverters = _generateScalarConverters(customScalars);
    final typeDefinitions = _generateTypeDefinitions(schemaDoc);
    final definedTypes = extractDefinedTypes(typesContent);
    final clientExtension = _generateClientExtension(
        operationName, operationType, documentContent, schemaDoc, definedTypes);

    return '''
import 'dart:developer' as developer;
import 'package:graphql/client.dart' as graphql;
import 'types.dart';

$clientExtension
''';
  }

  static String generateOperationFile(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
    String typesContent,
  ) {
    final schemaDoc = gql_lang.parseString(schema);

    final definedTypes = extractDefinedTypes(typesContent);
    final clientExtension = _generateClientExtension(
        operationName, operationType, documentContent, schemaDoc, definedTypes);

    return '''
import 'dart:developer' as developer;
import 'package:graphql/client.dart' as graphql;
import 'package:raduga_flutter_application/graphql/generated/types.dart';

$clientExtension
''';
  }

  static Set<String> _extractCustomScalars(DocumentNode schemaDoc) {
    final customScalars = <String>{};
    for (final definition in schemaDoc.definitions) {
      if (definition is TypeDefinitionNode) {
        final typeName = definition.name.value;
        if (definition is ScalarTypeDefinitionNode &&
            !_builtInScalars.contains(typeName) &&
            typeName != 'Decimal') {
          customScalars.add(typeName);
        }
      }
    }
    return customScalars;
  }

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

  static String _generateTypeDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in schemaDoc.definitions) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(_generateClassForType(definition));
      }
    }

    return buffer.toString();
  }

  static String _generateClassForType(ObjectTypeDefinitionNode type) {
    final className = type.name.value;
    final fields = type.fields;

    final classBuffer = StringBuffer();
    classBuffer.writeln('@JsonSerializable()');
    classBuffer.writeln('class $className {');

    for (final field in fields) {
      final fieldName = field.name.value;
      final fieldType = _getDartType(field.type);
      final baseType = fieldType
          .replaceAll('?', '')
          .replaceAll('List<', '')
          .replaceAll('>', '');

      if (baseType == 'DateTime') {
        classBuffer.writeln('  @DateTimeConverter()');
      } else if (baseType == 'Decimal') {
        classBuffer.writeln('  @DecimalConverter()');
      } else if (_isEnum(baseType)) {
        classBuffer.writeln('  @${baseType}Converter()');
      } else if (!_builtInScalars.contains(baseType) &&
          !_scalarToDartType.containsKey(baseType) &&
          _customScalars.contains(baseType) &&
          baseType != 'Decimal') {
        classBuffer.writeln('  @${baseType}Converter()');
      }

      classBuffer.writeln('  final $fieldType ${fieldName.toCamelCase()};');
    }

    classBuffer.writeln();
    classBuffer.writeln('  $className({');
    for (final field in fields) {
      final isRequired = field.type.isNonNull;
      final requiredKeyword = isRequired ? 'required ' : '';
      classBuffer.writeln(
          '    ${requiredKeyword}this.${field.name.value.toCamelCase()},');
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

  static bool _isEnum(String typeName) {
    return _enumTypes.contains(typeName);
  }

  static String _getDartType(TypeNode type) {
    if (type is NamedTypeNode) {
      final typeName = _scalarToDartType[type.name.value] ?? type.name.value;
      return type.isNonNull ? typeName : '$typeName?';
    } else if (type is ListTypeNode) {
      final innerType = _getDartType(type.type);
      return type.isNonNull ? 'List<$innerType>' : 'List<$innerType>?';
    }
    return 'dynamic';
  }

  static String _generateClientExtension(
      String operationName,
      String operationType,
      String operationDocumentContent,
      DocumentNode schemaDoc,
      Set<String> definedTypes) {
    final methodName =
        operationType.toLowerCase() == 'mutation' ? 'mutate' : 'query';
    final optionsType = '${operationType.capitalize()}Options';
    final operationDoc = gql_lang.parseString(operationDocumentContent);

    final returnType =
        _getOperationReturnType(operationDoc, schemaDoc, definedTypes);
    final fieldName = _getOperationFieldName(operationDoc);

    // Проверяем, является ли тип nullable
    final isNullable = returnType.endsWith('?');
    // Всегда используем Future<ReturnType> для методов *Data
    // Если тип nullable в схеме, сохраняем его nullable и в возвращаемом типе
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

      ${_generateDataConversion(returnType, fieldName)}
    
    } catch (e, stackTrace) {
      developer.log('Error in ${operationName}Data: \$e');
      developer.log('Stack trace: \$stackTrace');
      ${isNullable ? 'return null;' : 'throw Exception("An error occurred while fetching data in $operationName: \$e");'}
    }
  }
}
''';
  }

  static String _generateDataConversion(String returnType, String fieldName) {
    final isNullable = returnType.endsWith('?');
    final baseType = isNullable
        ? returnType.substring(0, returnType.length - 1)
        : returnType;

    // Обработка списков
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
    // Обработка примитивных типов
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
    // Явная обработка для dynamic baseType
    else if (baseType == 'dynamic') {
      return """
      try {
        final data = result.data!;
        if (!data.containsKey('$fieldName') || data['$fieldName'] == null) {
          ${isNullable ? 'return null;' : 'throw Exception("Field \'$fieldName\' is null in GraphQL response for dynamic type");'}
        }
        // Поле само по себе должно быть динамическими данными (например, Map или примитив)
        return data['$fieldName']; 
      } catch (e, stackTrace) {
        developer.log('Error converting GraphQL response for dynamic field $fieldName: \$e');
        developer.log('Stack trace: \$stackTrace');
        ${isNullable ? 'return null;' : 'throw Exception("Error converting GraphQL response for dynamic field $fieldName: \$e");'}
      }
        """;
    }
    // Обработка объектов
    else {
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
      // Явная обработка для dynamic элементов списка
      return """
          // Предполагается, что 'item' уже имеет правильный динамический тип (например, Map, если это был объект)
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

  static String _getOperationReturnType(DocumentNode operationDoc,
      DocumentNode schemaDoc, Set<String> definedTypes) {
    print('Entering _getOperationReturnType');
    print('Operation document: ${operationDoc.toString()}');
    print('Schema document: ${schemaDoc.toString()}');
    print('Defined types: $definedTypes');

    for (final definition in operationDoc.definitions) {
      print('Processing definition: ${definition.runtimeType}');
      if (definition is OperationDefinitionNode) {
        final operationType = definition.type.toString().toLowerCase();
        //print('Operation type: $operationType');
        final rootType = _findRootType(schemaDoc, operationType);
        //print('Root type: ${rootType?.name.value}');
        if (rootType != null) {
          if (definition.selectionSet.selections.isNotEmpty) {
            final firstSelection = definition.selectionSet.selections.first;
            //print('First selection: ${firstSelection.runtimeType}');
            if (firstSelection is FieldNode) {
              final fieldName = firstSelection.name.value;
              //print('Field name: $fieldName');
              final field = rootType.fields.firstWhere(
                (f) => f.name.value == fieldName,
                orElse: () => throw StateError('Field not found: $fieldName'),
              );

              if (field == null) {
                print(
                    'Warning: Field $fieldName not found in root type ${rootType.name.value}');
                return 'dynamic';
              }

              final schemaType = _getSchemaType(field.type);
              //print('Schema type: $schemaType');
              final dartType =
                  _mapSchemaTypeToDartType(schemaType, definedTypes);
              // print('Dart type: $dartType');
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

  static ObjectTypeDefinitionNode? _findRootType(
      DocumentNode schemaDoc, String operationType) {
    print('Entering _findRootType');
    print('Operation type: $operationType');

    operationType = operationType.toLowerCase();
    if (operationType == 'operationtype.mutation') {
      operationType = 'mutation';
    } else if (operationType == 'operationtype.query') {
      operationType = 'query';
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

  static String _getSchemaType(TypeNode type) {
    if (type is NamedTypeNode) {
      return '${type.name.value}?';
    } else if (type is ListTypeNode) {
      return 'List<${_getSchemaType(type.type)}>?';
    }
    return 'dynamic';
  }

  static String _mapSchemaTypeToDartType(
      String schemaType, Set<String> definedTypes) {
    final isNullable = schemaType.endsWith('?');
    final baseType = isNullable
        ? schemaType.substring(0, schemaType.length - 1)
        : schemaType;

    if (baseType.startsWith('List<')) {
      final innerType = baseType.substring(5, baseType.length - 1);
      final mappedInnerType = _mapSchemaTypeToDartType(innerType, definedTypes);
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
      case 'Decimal':
        return isNullable ? 'Decimal?' : 'Decimal';
      default:
        if (definedTypes.contains(baseType) ||
            (_customScalars.contains(baseType) && baseType != 'Decimal') ||
            _enumTypes.contains(baseType)) {
          return isNullable ? '$baseType?' : baseType;
        }
        print('Warning: Unknown type $baseType');
        return isNullable ? 'dynamic?' : 'dynamic';
    }
  }

  static bool _isScalarType(String typeName) {
    final scalarTypes = [
      'Int',
      'Float',
      'String',
      'Boolean',
      'ID',
      'DateTime',
      'Decimal',
      ...GraphQLCodeGenerator._customScalars.where((s) => s != 'Decimal')
    ];
    return scalarTypes.contains(typeName);
  }

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

  static String _getOperationFieldName(DocumentNode operationDoc) {
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

  static Set<String> extractDefinedTypes(String typesContent) {
    final definedTypes = Set<String>();
    final classRegex = RegExp(r'class\s+(\w+)');
    final matches = classRegex.allMatches(typesContent);
    for (final match in matches) {
      definedTypes.add(match.group(1)!);
    }
    return definedTypes;
  }

  static String _generateAllTypeDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in schemaDoc.definitions) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(_generateTypeDefinition(definition));
      }
    }

    return buffer.toString();
  }

  static String _generateTypeDefinition(ObjectTypeDefinitionNode typeNode) {
    final typeName = typeNode.name.value;
    final fields = typeNode.fields;

    final buffer = StringBuffer();
    buffer.writeln('@JsonSerializable()');
    buffer.writeln('class $typeName {');

    for (final field in fields) {
      final fieldName = field.name.value;
      final fieldType = _getDartType(field.type);
      final baseType = fieldType
          .replaceAll('?', '')
          .replaceAll('List<', '')
          .replaceAll('>', '');

      if (baseType == 'DateTime') {
        buffer.writeln('  @DateTimeConverter()');
      } else if (baseType == 'Decimal') {
        buffer.writeln('  @DecimalConverter()');
      } else if (_isEnum(baseType)) {
        buffer.writeln('  @${baseType}Converter()');
      } else if (_customScalars.contains(baseType) && baseType != 'Decimal') {
        buffer.writeln('  @${baseType}Converter()');
      }

      buffer.writeln('  $fieldType $fieldName;');
    }

    buffer.writeln();
    buffer.writeln('  $typeName({');
    for (final field in fields) {
      final fieldName = field.name.value;
      buffer.writeln('    required this.$fieldName,');
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

  static String _mapGraphQLTypeToDartType(String graphqlType) {
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
      default:
        return graphqlType;
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }

  String toCamelCase() {
    if (length < 2) {
      return toLowerCase();
    }
    return "${this[0].toLowerCase()}${substring(1)}";
  }
}
