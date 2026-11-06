/// `add_id_fields`: selects `id` on every object the cache can normalize.
library;

import 'package:gql/ast.dart';

import 'config_context.dart';
import 'document_utils.dart';
import 'schema_analyzer.dart';

/// Adds an `id` field to selection sets, the way `__typename` is added, so
/// the normalized cache of `package:graphql` (which keys objects by
/// `__typename` and `id`) can store and read every object a query returns.
///
/// A selection set gets `id` when its type (an object type or an interface)
/// has a field `id` of a scalar type without required arguments, and the set
/// doesn't select `id` already. Union selections have no fields of their
/// own, so there `id` goes into the `... on Type` selections and fragments
/// whose type has it. An inline fragment doesn't get `id` when the selection
/// around it already has it. A set where another field is aliased `id` is
/// left alone, since the two would clash.
///
/// The field is added to the documents the client sends and to the result
/// classes, as if the operation had selected it.
class IdFields {
  IdFields(DocumentNode schema)
      : _schema = DocumentUtils.mergeSchemaExtensions(schema) {
    for (final def in _schema.definitions.whereType<TypeDefinitionNode>()) {
      _types[def.name.value] = def;
    }
  }

  final DocumentNode _schema;
  final Map<String, TypeDefinitionNode> _types = {};
  final Map<String, bool> _hasId = {};

  static const _idField = FieldNode(name: NameNode(value: 'id'));

  /// [operation] with `id` added, or [operation] itself when
  /// `add_id_fields` is off or its root type isn't in the schema.
  static OperationDefinitionNode operationOf(
      DocumentNode schema, OperationDefinitionNode operation) {
    if (!CodegenConfigContext.addIdFields) return operation;
    return IdFields(schema).operation(operation);
  }

  /// [fragments] with `id` added, except those named in [skip] (fragments
  /// another package declares, see `fragment_imports`, whose classes that
  /// package generates). Returns [fragments] when `add_id_fields` is off.
  static Map<String, FragmentDefinitionNode> fragmentsOf(
    DocumentNode schema,
    Map<String, FragmentDefinitionNode> fragments, {
    Set<String> skip = const {},
  }) {
    if (!CodegenConfigContext.addIdFields) return fragments;
    final ids = IdFields(schema);
    return {
      for (final MapEntry(:key, :value) in fragments.entries)
        key: skip.contains(key) ? value : ids.fragment(value),
    };
  }

  /// [operation] with `id` added to its selection sets.
  OperationDefinitionNode operation(OperationDefinitionNode operation) {
    final ObjectTypeDefinitionNode? root;
    try {
      root = SchemaAnalyzer.findRootType(_schema, operation.type.name);
    } on StateError {
      return operation; // reported by the generator
    }
    if (root == null) return operation;
    return OperationDefinitionNode(
      type: operation.type,
      name: operation.name,
      variableDefinitions: operation.variableDefinitions,
      directives: operation.directives,
      // The root object is never normalized by id.
      selectionSet:
          _set(operation.selectionSet, root.name.value, covered: true),
      span: operation.span,
    );
  }

  /// [fragment] with `id` added to its selection sets.
  FragmentDefinitionNode fragment(FragmentDefinitionNode fragment) =>
      FragmentDefinitionNode(
        name: fragment.name,
        typeCondition: fragment.typeCondition,
        directives: fragment.directives,
        selectionSet: _set(
            fragment.selectionSet, fragment.typeCondition.on.name.value,
            covered: false),
        span: fragment.span,
      );

  /// [set] of type [type] with `id` added (unless [covered]: the
  /// selection around it already has `id`), and in its subselections.
  SelectionSetNode _set(SelectionSetNode set, String type,
      {required bool covered}) {
    final keys = {
      for (final s in set.selections.whereType<FieldNode>())
        (s.alias ?? s.name).value,
    };
    final add = !covered && !keys.contains('id') && _typeHasId(type);
    // Whether inline fragments in this set must not add `id`: the objects
    // have it already, or another field takes the `id` key.
    final hasId = add || keys.contains('id') || (covered && _typeHasId(type));

    final changed = <SelectionNode>[];
    var modified = add;
    for (final sel in set.selections) {
      final next = _selection(sel, type, hasId);
      if (!identical(next, sel)) modified = true;
      changed.add(next);
    }
    if (!modified) return set;
    return SelectionSetNode(
      selections: [if (add) _idField, ...changed],
      span: set.span,
    );
  }

  SelectionNode _selection(SelectionNode sel, String parent, bool parentHasId) {
    switch (sel) {
      case FieldNode(:final selectionSet?):
        if (sel.name.value.startsWith('__')) return sel;
        final fieldType = _fieldType(parent, sel.name.value);
        if (fieldType == null) return sel; // reported by the validator
        final next = _set(selectionSet, fieldType, covered: false);
        if (identical(next, selectionSet)) return sel;
        return FieldNode(
          alias: sel.alias,
          name: sel.name,
          arguments: sel.arguments,
          directives: sel.directives,
          selectionSet: next,
          span: sel.span,
        );
      case InlineFragmentNode(:final typeCondition, :final selectionSet):
        final on = typeCondition?.on.name.value ?? parent;
        final next =
            _set(selectionSet, on, covered: parentHasId || on == parent);
        if (identical(next, selectionSet)) return sel;
        return InlineFragmentNode(
          typeCondition: typeCondition,
          directives: sel.directives,
          selectionSet: next,
          span: sel.span,
        );
      default:
        // Leaf fields; fragment spreads get `id` in their own definition.
        return sel;
    }
  }

  /// Whether [type] is an object type or interface with an `id` field of a
  /// scalar type that needs no arguments.
  bool _typeHasId(String type) => _hasId.putIfAbsent(type, () {
        final id = _fields(type).where((f) => f.name.value == 'id').firstOrNull;
        if (id == null) return false;
        if (id.args.any((a) => a.type.isNonNull && a.defaultValue == null)) {
          return false;
        }
        final named = _named(id.type);
        return _types[named] is ScalarTypeDefinitionNode ||
            const {'ID', 'String', 'Int', 'Float', 'Boolean'}.contains(named);
      });

  String? _fieldType(String type, String field) {
    final definition =
        _fields(type).where((f) => f.name.value == field).firstOrNull;
    return definition == null ? null : _named(definition.type);
  }

  List<FieldDefinitionNode> _fields(String type) => switch (_types[type]) {
        ObjectTypeDefinitionNode(:final fields) => fields,
        InterfaceTypeDefinitionNode(:final fields) => fields,
        _ => const [],
      };

  static String _named(TypeNode type) => type is ListTypeNode
      ? _named(type.type)
      : (type as NamedTypeNode).name.value;
}
