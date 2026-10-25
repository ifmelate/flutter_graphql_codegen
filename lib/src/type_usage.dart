/// Which schema types the generated code of some operations and fragments
/// refers to, for `prune_types`.
library;

import 'package:gql/ast.dart';

import 'document_utils.dart';
import 'schema_analyzer.dart';

/// Collects the enums, input types, custom scalars and abstract types that
/// operations and fragments use.
class TypeUsage {
  TypeUsage._(this._types);

  final Map<String, TypeDefinitionNode> _types;
  final Set<String> _used = {};

  /// Names of the schema types `types.dart` must declare for [operations]
  /// and [fragments]:
  ///
  /// - enums and custom scalars of selected fields (also inside fragments);
  /// - types of variables, with every input type, enum and scalar reachable
  ///   through their fields;
  /// - interfaces and unions that are selected or used as a type condition,
  ///   for `possibleTypes`.
  ///
  /// Fields the schema doesn't have are skipped; the document validator
  /// reports them.
  static Set<String> collect(
    DocumentNode schema,
    Iterable<OperationDefinitionNode> operations,
    Map<String, FragmentDefinitionNode> fragments,
  ) {
    final merged = DocumentUtils.mergeSchemaExtensions(schema);
    final usage = TypeUsage._({
      for (final d in merged.definitions.whereType<TypeDefinitionNode>())
        d.name.value: d,
    });
    for (final operation in operations) {
      for (final v in operation.variableDefinitions) {
        usage._input(_named(v.type));
      }
      final ObjectTypeDefinitionNode? root;
      try {
        root = SchemaAnalyzer.findRootType(merged, operation.type.name);
      } on StateError {
        continue;
      }
      if (root == null) continue;
      usage._selections(operation.selectionSet, root.name.value);
    }
    // fragments.dart has every fragment, used or not.
    for (final fragment in fragments.values) {
      final on = fragment.typeCondition.on.name.value;
      usage._abstract(on);
      usage._selections(fragment.selectionSet, on);
    }
    return usage._used;
  }

  static String _named(TypeNode type) => type is ListTypeNode
      ? _named(type.type)
      : (type as NamedTypeNode).name.value;

  void _selections(SelectionSetNode set, String parent) {
    for (final selection in set.selections) {
      switch (selection) {
        case FieldNode(:final name, :final selectionSet):
          if (name.value.startsWith('__')) continue;
          final field = _field(parent, name.value);
          if (field == null) continue;
          final type = _named(field.type);
          _output(type);
          if (selectionSet != null) _selections(selectionSet, type);
        case InlineFragmentNode(:final typeCondition, :final selectionSet):
          final on = typeCondition?.on.name.value ?? parent;
          _abstract(on);
          _selections(selectionSet, on);
        case FragmentSpreadNode():
          // Every fragment is collected on its own.
          break;
      }
    }
  }

  FieldDefinitionNode? _field(String type, String name) {
    final fields = switch (_types[type]) {
      ObjectTypeDefinitionNode(:final fields) => fields,
      InterfaceTypeDefinitionNode(:final fields) => fields,
      _ => const <FieldDefinitionNode>[],
    };
    return fields.where((f) => f.name.value == name).firstOrNull;
  }

  void _output(String type) {
    switch (_types[type]) {
      case EnumTypeDefinitionNode() || ScalarTypeDefinitionNode():
        _used.add(type);
      case InterfaceTypeDefinitionNode() || UnionTypeDefinitionNode():
        _used.add(type);
      default:
    }
  }

  void _abstract(String type) {
    if (_types[type]
        case InterfaceTypeDefinitionNode() || UnionTypeDefinitionNode()) {
      _used.add(type);
    }
  }

  void _input(String type) {
    final definition = _types[type];
    switch (definition) {
      case EnumTypeDefinitionNode() || ScalarTypeDefinitionNode():
        _used.add(type);
      case InputObjectTypeDefinitionNode(:final fields):
        if (!_used.add(type)) return;
        for (final f in fields) {
          _input(_named(f.type));
        }
      default:
    }
  }
}
