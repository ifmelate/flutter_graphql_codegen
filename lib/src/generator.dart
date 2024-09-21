import 'package:graphql/client.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

class GraphQLCodeGenerator {
  static String generateCode(
    String schema,
    String documentContent,
    String operationName,
    String operationType,
  ) {
    final schemaDoc = gql_lang.parseString(schema);
    final operationDoc = gql_lang.parseString(documentContent);

    final typeDefinitions = _generateTypeDefinitions(schemaDoc);
    final clientExtension =
        _generateClientExtension(operationName, operationType, operationDoc);

    return '''
import 'package:graphql/client.dart' as graphql;
import 'package:json_annotation/json_annotation.dart';

part '${operationName.toLowerCase()}.g.dart';

$typeDefinitions

$clientExtension
''';
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
    final fields = type.fields ?? [];

    final classBuffer = StringBuffer();
    classBuffer.writeln('@JsonSerializable()');
    classBuffer.writeln('class $className {');

    for (final field in fields) {
      final fieldName = field.name.value;
      final fieldType = _getDartType(field.type);
      classBuffer.writeln('  final $fieldType $fieldName;');
    }

    classBuffer.writeln();
    classBuffer.writeln('  $className({');
    for (final field in fields) {
      classBuffer.writeln('    required this.${field.name.value},');
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

  static String _getDartType(TypeNode type, {bool isNonNull = false}) {
    if (type is NamedTypeNode) {
      final typeName = _getBasicDartType(type.name.value);
      return isNonNull ? typeName : '$typeName?';
    } else if (type is ListTypeNode) {
      final innerType = _getDartType(type.type, isNonNull: false);
      return isNonNull ? 'List<$innerType>' : 'List<$innerType>?';
    } else {
      return isNonNull ? 'dynamic' : 'dynamic?';
    }
  }

  static String _getBasicDartType(String graphqlType) {
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
}
