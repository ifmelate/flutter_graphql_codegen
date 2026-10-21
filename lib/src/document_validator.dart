/// Validation of operations against the schema.
library;

import 'package:gql/ast.dart';

import 'code_utils.dart';
import 'diagnostics.dart';
import 'schema_analyzer.dart';

/// A problem found in an operation.
class ValidationProblem {
  final String code;
  final String message;

  const ValidationProblem(this.code, this.message);

  @override
  String toString() => '[$code] $message';
}

/// Checks operations against a schema: fields, arguments, variables and
/// selection sets.
///
/// Only definite errors are reported (documents a GraphQL server rejects);
/// argument value types and field merging are not checked.
class DocumentValidator {
  DocumentValidator(DocumentNode schema)
      : _schema = schema,
        _types = {
          for (final def in schema.definitions.whereType<TypeDefinitionNode>())
            def.name.value: def,
        };

  final DocumentNode _schema;
  final Map<String, TypeDefinitionNode> _types;

  /// Returns the problems in [operation]; [fragments] are the fragment
  /// definitions it may spread (missing ones are reported elsewhere).
  List<ValidationProblem> validate(
    OperationDefinitionNode operation,
    Map<String, FragmentDefinitionNode> fragments,
  ) {
    final ObjectTypeDefinitionNode? root;
    try {
      root = SchemaAnalyzer.findRootType(_schema, operation.type.name);
    } on StateError {
      return const []; // reported by the generator
    }
    if (root == null) return const [];

    final run = _Run(this, operation, fragments);
    run.selectionSet(operation.selectionSet, root, '', null);
    run.checkVariables();
    return run.problems;
  }

  /// Throws a [CodegenException] listing every problem in [operation].
  void check(
    OperationDefinitionNode operation,
    Map<String, FragmentDefinitionNode> fragments,
  ) {
    final problems = validate(operation, fragments);
    if (problems.isEmpty) return;
    final name = operation.name?.value ?? '<anonymous>';
    throw CodegenException(
      problems.first.code,
      'Invalid operation "$name":\n${problems.map((p) => '  $p').join('\n')}',
    );
  }

  static bool _isComposite(TypeDefinitionNode? type) =>
      type is ObjectTypeDefinitionNode ||
      type is InterfaceTypeDefinitionNode ||
      type is UnionTypeDefinitionNode;

  static String _namedType(TypeNode type) => type is ListTypeNode
      ? _namedType(type.type)
      : (type as NamedTypeNode).name.value;
}

/// State of validating one operation.
class _Run {
  _Run(this.validator, this.operation, this.fragments);

  final DocumentValidator validator;
  final OperationDefinitionNode operation;
  final Map<String, FragmentDefinitionNode> fragments;
  final problems = <ValidationProblem>[];
  final _usedVariables = <String, Node>{};
  final _visitedFragments = <String>{};

  Map<String, TypeDefinitionNode> get _types => validator._types;

  void selectionSet(SelectionSetNode set, TypeDefinitionNode parent,
      String path, String? fragment) {
    for (final selection in set.selections) {
      if (selection is FieldNode) {
        _field(selection, parent, path, fragment);
      } else if (selection is InlineFragmentNode) {
        _directives(selection.directives);
        final condition = selection.typeCondition?.on.name.value;
        final target = condition == null
            ? parent
            : _fragmentType(condition, selection, path, fragment);
        if (target != null) {
          selectionSet(selection.selectionSet, target, path, fragment);
        }
      } else if (selection is FragmentSpreadNode) {
        _directives(selection.directives);
        final name = selection.name.value;
        final definition = fragments[name];
        if (definition == null || !_visitedFragments.add(name)) continue;
        _directives(definition.directives);
        final target = _fragmentType(
            definition.typeCondition.on.name.value, definition, '', name);
        if (target != null) {
          selectionSet(definition.selectionSet, target, '', name);
        }
      }
    }
  }

  void _field(FieldNode field, TypeDefinitionNode parent, String path,
      String? fragment) {
    final name = field.name.value;
    final key = field.alias?.value ?? name;
    final fieldPath = path.isEmpty ? key : '$path.$key';
    for (final argument in field.arguments) {
      _variablesIn(argument.value);
    }
    _directives(field.directives);

    // `__typename` is the response key of the type name the generated code
    // (and the cache) relies on; other `__` names belong to introspection.
    final alias = field.alias?.value;
    if (alias != null && alias.startsWith('__') && alias != name) {
      _report(
          CodegenErrorCodes.buildInvalidSelection,
          'Alias "$alias" is not allowed: aliases starting with "__" are '
          'reserved; rename it',
          field,
          fieldPath,
          fragment);
    }

    final parentName = parent.name.value;
    if (name == '__typename') {
      if (field.selectionSet != null) {
        _report(
            CodegenErrorCodes.buildInvalidSelection,
            'Field "__typename" cannot have a selection set',
            field,
            fieldPath,
            fragment);
      }
      return;
    }
    // Introspection fields: their types are not part of the SDL.
    if (name == '__schema' || name == '__type') return;

    if (parent is UnionTypeDefinitionNode) {
      _report(
          CodegenErrorCodes.buildUnknownField,
          'Field "$name" cannot be selected on union "$parentName"; use an '
          'inline fragment (... on Type)',
          field,
          fieldPath,
          fragment);
      return;
    }
    final fields = parent is ObjectTypeDefinitionNode
        ? parent.fields
        : (parent as InterfaceTypeDefinitionNode).fields;
    final definition = fields.where((f) => f.name.value == name).firstOrNull;
    if (definition == null) {
      _report(
          CodegenErrorCodes.buildUnknownField,
          'Field "$name" does not exist on type "$parentName"',
          field,
          fieldPath,
          fragment);
      return;
    }

    _arguments(field, definition, '$parentName.$name', fieldPath, fragment);

    final typeName = DocumentValidator._namedType(definition.type);
    final type = _types[typeName];
    if (DocumentValidator._isComposite(type)) {
      final set = field.selectionSet;
      if (set == null) {
        _report(
            CodegenErrorCodes.buildInvalidSelection,
            'Field "$name" of type "$typeName" needs a selection set',
            field,
            fieldPath,
            fragment);
      } else {
        selectionSet(set, type!, fieldPath, fragment);
      }
    } else if (field.selectionSet != null) {
      _report(
          CodegenErrorCodes.buildInvalidSelection,
          'Field "$name" of type "$typeName" cannot have a selection set',
          field,
          fieldPath,
          fragment);
    }
  }

  void _arguments(FieldNode field, FieldDefinitionNode definition,
      String fieldName, String path, String? fragment) {
    final declared = {for (final a in definition.args) a.name.value: a};
    final given = <String>{};
    for (final argument in field.arguments) {
      final name = argument.name.value;
      given.add(name);
      if (!declared.containsKey(name)) {
        _report(
            CodegenErrorCodes.buildInvalidArgument,
            'Unknown argument "$name" on field "$fieldName"',
            argument,
            path,
            fragment);
      }
    }
    for (final arg in definition.args) {
      final required = arg.type.isNonNull && arg.defaultValue == null;
      if (required && !given.contains(arg.name.value)) {
        _report(
            CodegenErrorCodes.buildInvalidArgument,
            'Missing required argument "${arg.name.value}" on field '
            '"$fieldName"',
            field,
            path,
            fragment);
      }
    }
  }

  TypeDefinitionNode? _fragmentType(
      String typeName, Node node, String path, String? fragment) {
    final type = _types[typeName];
    if (type == null) {
      _report(
          CodegenErrorCodes.buildInvalidSelection,
          'Fragment type "$typeName" does not exist in the schema',
          node,
          path,
          fragment);
      return null;
    }
    if (!DocumentValidator._isComposite(type)) {
      _report(
          CodegenErrorCodes.buildInvalidSelection,
          'Fragment on "$typeName" is not allowed: fragments need an object, '
          'interface or union type',
          node,
          path,
          fragment);
      return null;
    }
    return type;
  }

  void _directives(List<DirectiveNode> directives) {
    for (final directive in directives) {
      for (final argument in directive.arguments) {
        _variablesIn(argument.value);
      }
    }
  }

  void _variablesIn(ValueNode value) {
    if (value is VariableNode) {
      _usedVariables.putIfAbsent(value.name.value, () => value);
    } else if (value is ListValueNode) {
      value.values.forEach(_variablesIn);
    } else if (value is ObjectValueNode) {
      for (final field in value.fields) {
        _variablesIn(field.value);
      }
    }
  }

  /// Reports undeclared, unused and wrongly typed variables.
  void checkVariables() {
    final declared = {
      for (final d in operation.variableDefinitions) d.variable.name.value: d,
    };
    for (final entry in _usedVariables.entries) {
      if (!declared.containsKey(entry.key)) {
        _report(
            CodegenErrorCodes.buildInvalidVariable,
            'Variable "\$${entry.key}" is used but not declared by the '
                'operation',
            entry.value,
            '',
            null);
      }
    }
    for (final entry in declared.entries) {
      final name = entry.key;
      final definition = entry.value;
      if (!_usedVariables.containsKey(name)) {
        _report(
            CodegenErrorCodes.buildInvalidVariable,
            'Variable "\$$name" is declared but never used',
            definition,
            '',
            null);
      }
      final typeName = DocumentValidator._namedType(definition.type);
      if (GraphQLConstants.builtInScalars.contains(typeName)) continue;
      final type = _types[typeName];
      if (type == null) {
        _report(
            CodegenErrorCodes.buildInvalidVariable,
            'Variable "\$$name" has unknown type "$typeName"',
            definition,
            '',
            null);
      } else if (type is! ScalarTypeDefinitionNode &&
          type is! EnumTypeDefinitionNode &&
          type is! InputObjectTypeDefinitionNode) {
        _report(
            CodegenErrorCodes.buildInvalidVariable,
            'Variable "\$$name" has type "$typeName", which is not an input '
                'type',
            definition,
            '',
            null);
      }
    }
  }

  /// 1-based line of [node]; the gql parser only records spans of names.
  static int? _line(Node node) {
    final name = switch (node) {
      FieldNode(:final alias, :final name) => alias ?? name,
      ArgumentNode(:final name) => name,
      FragmentSpreadNode(:final name) => name,
      FragmentDefinitionNode(:final name) => name,
      InlineFragmentNode(:final typeCondition) => typeCondition?.on.name,
      VariableNode(:final name) => name,
      VariableDefinitionNode(:final variable) => variable.name,
      _ => null,
    };
    final span = name?.span ?? node.span;
    return span == null ? null : span.start.line + 1;
  }

  void _report(
      String code, String message, Node node, String path, String? fragment) {
    final where = [
      fragment == null ? null : 'fragment $fragment',
      if (path.isNotEmpty) 'path $path',
      if (_line(node) case final line?) 'line $line',
    ].whereType<String>();
    problems.add(ValidationProblem(
        code, where.isEmpty ? message : '$message (${where.join(', ')})'));
  }
}
