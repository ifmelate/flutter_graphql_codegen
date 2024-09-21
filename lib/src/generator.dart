import 'package:graphql/client.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

class GraphQLCodeGenerator {
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
    final clientExtension =
        _generateClientExtension(operationName, operationType, operationDoc);

    return '''
import 'package:graphql/client.dart' as graphql;
import 'package:json_annotation/json_annotation.dart';

part '${operationName.toLowerCase()}.g.dart';

$scalarConverters

$typeDefinitions

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
      if (!_builtInScalars.contains(baseType) &&
          !_scalarToDartType.containsKey(baseType)) {
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
      String operationName, String operationType, DocumentNode operationDoc) {
    final methodName =
        operationType.toLowerCase() == 'mutation' ? 'mutate' : 'query';
    final optionsType = '${operationType.capitalize()}Options';
    final returnType = _getOperationReturnType(operationDoc);

    return '''
extension ${operationName}Extension on GraphQLClient {
  Future<QueryResult<$returnType>> ${operationName.decapitalize()}([Map<String, dynamic>? variables]) async {
    final options = $optionsType(
      document: gql(r"""
${operationDoc.toString()}
      """),
      variables: variables ?? const {},
    );

    final result = await this.$methodName(options);

    if (result.hasException) {
      throw result.exception!;
    }

    return QueryResult(
      data: result.data != null ? $returnType.fromJson(result.data!) : null,
      exception: result.exception,
      context: result.context,
    );
  }

  Future<$returnType?> ${operationName.decapitalize()}Data([Map<String, dynamic>? variables]) async {
    final result = await ${operationName.decapitalize()}(variables);
    return result.data;
  }
}
''';
  }

  static String _getOperationReturnType(DocumentNode operationDoc) {
    // This is a placeholder. You'll need to implement the logic to determine the return type
    // based on the operation and schema.
    return 'dynamic';
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }

  String decapitalize() {
    return "${this[0].toLowerCase()}${this.substring(1)}";
  }

  String toCamelCase() {
    if (length < 2) {
      return toLowerCase();
    }
    return "${this[0].toLowerCase()}${substring(1)}";
  }
}
