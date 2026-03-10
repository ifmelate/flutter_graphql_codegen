import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

class GraphQLOperation {
  final String name;
  final String type; // query | mutation | subscription
  final String content; // full SDL of the operation

  GraphQLOperation(
      {required this.name, required this.type, required this.content});
}

class GraphQLParser {
  /// Parses GraphQL operations using the official gql AST parser for reliability
  static List<GraphQLOperation> parseOperations(String document) {
    final doc = gql_lang.parseString(document);
    final operations = <GraphQLOperation>[];

    for (final def in doc.definitions) {
      if (def is OperationDefinitionNode) {
        final typeString = _operationTypeToString(def.type);
        final opName = def.name?.value ?? 'Anonymous';

        // Reconstruct the SDL for this operation using the original text slice when possible
        // Since gql AST does not preserve location text by default, we serialize back
        final serialized = _serializeOperation(def);

        operations.add(GraphQLOperation(
          name: opName,
          type: typeString,
          content: serialized,
        ));
      }
    }

    return operations;
  }

  static String _serializeOperation(OperationDefinitionNode def) {
    final buffer = StringBuffer();
    final typeString = _operationTypeToString(def.type);
    final name = def.name?.value != null ? ' ${def.name!.value}' : '';
    final vars = _serializeVariableDefs(def.variableDefinitions);
    buffer.writeln('$typeString$name$vars {');
    buffer.writeln(_serializeSelectionSet(def.selectionSet, 2));
    buffer.writeln('}');
    return buffer.toString();
  }

  static String _serializeVariableDefs(List<VariableDefinitionNode> defs) {
    if (defs.isEmpty) return '';
    final parts = defs.map((d) {
      final varName = d.variable.name.value;
      final typeStr = _typeToString(d.type);
      String defaultVal = '';
      final dv = d.defaultValue;
      if (dv != null && dv.value != null) {
        // DefaultValueNode wraps a ValueNode in gql AST
        final ValueNode valueNode = dv.value!;
        defaultVal = ' = ${_valueToString(valueNode)}';
      }
      return '\$${varName}: $typeStr$defaultVal';
    }).join(', ');
    return '($parts)';
  }

  static String _serializeSelectionSet(SelectionSetNode set, int indent) {
    final pad = ' ' * indent;
    final lines = <String>[];
    for (final sel in set.selections) {
      if (sel is FieldNode) {
        final alias = sel.alias != null ? '${sel.alias!.value}: ' : '';
        final name = sel.name.value;
        final args = _serializeArguments(sel.arguments);
        if (sel.selectionSet != null) {
          lines.add('$pad$alias$name$args {');
          lines.add(_serializeSelectionSet(sel.selectionSet!, indent + 2));
          lines.add('$pad}');
        } else {
          lines.add('$pad$alias$name$args');
        }
      } else if (sel is FragmentSpreadNode) {
        lines.add('$pad...${sel.name.value}');
      } else if (sel is InlineFragmentNode) {
        final typeCond = sel.typeCondition != null
            ? ' on ${sel.typeCondition!.on.name.value}'
            : '';
        lines.add('$pad...$typeCond {');
        lines.add(_serializeSelectionSet(sel.selectionSet, indent + 2));
        lines.add('$pad}');
      }
    }
    return lines.join('\n');
  }

  static String _serializeArguments(List<ArgumentNode> args) {
    if (args.isEmpty) return '';
    final inner = args
        .map((a) => '${a.name.value}: ${_valueToString(a.value)}')
        .join(', ');
    return '($inner)';
  }

  static String _valueToString(ValueNode value) {
    if (value is StringValueNode) {
      final escaped = value.value
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"')
          .replaceAll('\n', r'\n')
          .replaceAll('\r', r'\r')
          .replaceAll('\t', r'\t');
      return '"$escaped"';
    }
    if (value is IntValueNode) return value.value;
    if (value is FloatValueNode) return value.value;
    if (value is BooleanValueNode) return value.value.toString();
    if (value is EnumValueNode) return value.name.value;
    if (value is VariableNode) return '\$${value.name.value}';
    if (value is NullValueNode) return 'null';
    if (value is ListValueNode) {
      return '[${value.values.map(_valueToString).join(', ')}]';
    }
    if (value is ObjectValueNode) {
      final fields = value.fields
          .map((f) => '${f.name.value}: ${_valueToString(f.value)}')
          .join(', ');
      return '{ $fields }';
    }
    return 'null';
  }

  static String _typeToString(TypeNode type) {
    if (type is ListTypeNode) {
      final inner = _typeToString(type.type);
      return '[$inner]' + (type.isNonNull ? '!' : '');
    }
    if (type is NamedTypeNode) {
      return type.name.value + (type.isNonNull ? '!' : '');
    }
    return 'Unknown';
  }

  static String _operationTypeToString(OperationType t) {
    switch (t) {
      case OperationType.query:
        return 'query';
      case OperationType.mutation:
        return 'mutation';
      case OperationType.subscription:
        return 'subscription';
    }
  }
}
