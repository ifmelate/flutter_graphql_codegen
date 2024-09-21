import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

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
            !_builtInScalars.contains(typeName)) {
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

    return '''
import 'package:json_annotation/json_annotation.dart';
import 'package:intl/intl.dart';
import 'package:decimal/decimal.dart';

part 'types.g.dart';

class DateTimeConverter implements JsonConverter<DateTime, String> {
  const DateTimeConverter();

  @override
  DateTime fromJson(String json) => DateTime.parse(json);

  @override
  String toJson(DateTime object) => object.toIso8601String();
}

class DecimalConverter implements JsonConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromJson(String json) => Decimal.parse(json);

  @override
  String toJson(Decimal object) => object.toString();
}

$scalarConverters

$enumDefinitions

$enumConverters

$typeDefinitions
''';
  }

  static String _generateAllTypeDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in schemaDoc.definitions) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(_generateClassForType(definition));
      }
    }

    return buffer.toString();
  }

  static String generateCode(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
  ) {
    final schemaDoc = gql_lang.parseString(schema);
    final operationDoc = gql_lang.parseString(documentContent);

    final customScalars = _extractCustomScalars(schemaDoc);
    final scalarConverters = _generateScalarConverters(customScalars);
    final typeDefinitions = _generateTypeDefinitions(schemaDoc);
    final clientExtension = _generateClientExtension(
        operationName, operationType, operationDoc, schemaDoc);

    return '''
import 'package:graphql/client.dart' as graphql;
import 'package:json_annotation/json_annotation.dart';

part '${operationName.toLowerCase()}.g.dart';

$scalarConverters

$typeDefinitions

$clientExtension
''';
  }

  static String generateOperationFile(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
  ) {
    final schemaDoc = gql_lang.parseString(schema);
    final operationDoc = gql_lang.parseString(documentContent);
    final clientExtension = _generateClientExtension(
        operationName, operationType, operationDoc, schemaDoc);

    return '''
import 'package:graphql/client.dart' as graphql;
import 'types.dart';

$clientExtension
''';
  }

  static Set<String> _extractCustomScalars(DocumentNode schemaDoc) {
    final customScalars = <String>{};
    for (final definition in schemaDoc.definitions) {
      if (definition is TypeDefinitionNode) {
        final typeName = definition.name.value;
        if (definition is ScalarTypeDefinitionNode &&
            !_builtInScalars.contains(typeName)) {
          customScalars.add(typeName);
        }
      }
    }
    return customScalars;
  }

  static String _generateScalarConverters(Set<String> customScalars) {
    final buffer = StringBuffer();
    for (final scalar in customScalars) {
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
          _customScalars.contains(baseType)) {
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

  static String _generateClientExtension(String operationName,
      String operationType, DocumentNode operationDoc, DocumentNode schemaDoc) {
    final methodName =
        operationType.toLowerCase() == 'mutation' ? 'mutate' : 'query';
    final optionsType = '${operationType.capitalize()}Options';
    final returnType = _getOperationReturnType(operationDoc, schemaDoc);

    return '''
extension ${operationName}Extension on graphql.GraphQLClient {
  Future<graphql.QueryResult<$returnType>> ${operationName.toCamelCase()}([Map<String, dynamic>? variables]) async {
    final options = graphql.$optionsType(
      document: graphql.gql(r"""
${operationDoc.toString()}
      """),
      variables: variables ?? const {},
    );

    final result = await this.$methodName(options);

    if (result.hasException) {
      throw result.exception!;
    }

    return graphql.QueryResult(
      data: result.data != null ? $returnType.fromJson(result.data!) : null,
      exception: result.exception,
      context: result.context,
    );
  }

  Future<$returnType?> ${operationName.toCamelCase()}Data([Map<String, dynamic>? variables]) async {
    final result = await ${operationName.toCamelCase()}(variables);
    return result.data;
  }
}
''';
  }

  static String _getOperationReturnType(
      DocumentNode operationDoc, DocumentNode schemaDoc) {
    for (final definition in operationDoc.definitions) {
      if (definition is OperationDefinitionNode) {
        final operationType = definition.type.toString().toLowerCase();
        final rootType = _findRootType(schemaDoc, operationType);
        if (rootType != null) {
          for (final field in rootType.fields) {
            if (field.name.value == definition.name?.value) {
              return _getDartType(field.type);
            }
          }
        }
      }
    }
    return 'dynamic';
  }

  static ObjectTypeDefinitionNode? _findRootType(
      DocumentNode schemaDoc, String operationType) {
    for (final definition in schemaDoc.definitions) {
      if (definition is ObjectTypeDefinitionNode) {
        if (definition.name.value.toLowerCase() == operationType) {
          return definition;
        }
      }
    }
    return null;
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
