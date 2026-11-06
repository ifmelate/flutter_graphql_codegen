/// `add_id_fields`: selects `id` on every object the cache can normalize.
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

import 'config_context.dart';
import 'diagnostics.dart';
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
/// around it already has it.
///
/// Two rules keep the documents valid:
///
/// - A type gets `id` only if every type it shares a union or interface
///   with declares `id` with the same type (or has none), since sibling
///   `... on` selections must agree on the type of a response key.
/// - A selection where another field is aliased `id` (`id: name`), also
///   inside its inline fragments and spread fragments, doesn't get `id`.
///   When a fragment spread there would get `id` itself, the build fails
///   with `BLD109`.
///
/// Both depend only on the schema and the fragment definitions, so a
/// fragment gets the same fields in `fragments.dart` and in every operation.
/// The field is added to the documents the client sends and to the result
/// classes, as if the operation had selected it.
class IdFields {
  /// [fragments] are the definitions the documents may spread, as written.
  IdFields(DocumentNode schema,
      [Map<String, FragmentDefinitionNode> fragments = const {}])
      : _schema = DocumentUtils.mergeSchemaExtensions(schema),
        _fragmentDefs = fragments {
    for (final def in _schema.definitions.whereType<TypeDefinitionNode>()) {
      _types[def.name.value] = def;
    }
    for (final def in _types.values) {
      switch (def) {
        case UnionTypeDefinitionNode(:final name, :final types):
          for (final member in types) {
            _possible.putIfAbsent(name.value, () => {}).add(member.name.value);
            _containers
                .putIfAbsent(member.name.value, () => {})
                .add(name.value);
          }
        case ObjectTypeDefinitionNode(:final name, :final interfaces) ||
              InterfaceTypeDefinitionNode(:final name, :final interfaces):
          for (final i in interfaces) {
            _possible.putIfAbsent(i.name.value, () => {}).add(name.value);
            _containers.putIfAbsent(name.value, () => {}).add(i.name.value);
          }
        default:
      }
    }
  }

  final DocumentNode _schema;
  final Map<String, FragmentDefinitionNode> _fragmentDefs;
  final Map<String, TypeDefinitionNode> _types = {};

  /// Abstract type -> the types it contains (union members, implementations).
  final Map<String, Set<String>> _possible = {};

  /// Type -> the unions and interfaces that contain it.
  final Map<String, Set<String>> _containers = {};
  final Map<String, String?> _idTypes = {};
  final Map<String, bool> _eligible = {};
  final Map<String, bool> _fragmentAdds = {};

  static const _idField = FieldNode(name: NameNode(value: 'id'));

  /// [operation] with `id` added, or [operation] itself when
  /// `add_id_fields` is off or its root type isn't in the schema.
  /// [fragments] are the fragments it may spread, as written.
  static OperationDefinitionNode operationOf(
    DocumentNode schema,
    OperationDefinitionNode operation,
    Map<String, FragmentDefinitionNode> fragments,
  ) {
    if (!CodegenConfigContext.addIdFields) return operation;
    return IdFields(schema, fragments).operation(operation);
  }

  /// [fragments] with `id` added. Returns [fragments] when `add_id_fields`
  /// is off.
  static Map<String, FragmentDefinitionNode> fragmentsOf(
    DocumentNode schema,
    Map<String, FragmentDefinitionNode> fragments,
  ) {
    if (!CodegenConfigContext.addIdFields) return fragments;
    final ids = IdFields(schema, fragments);
    return {
      for (final MapEntry(:key, :value) in fragments.entries)
        key: ids.fragment(value),
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
          _set(operation.selectionSet, root.name.value, inherited: false),
      span: operation.span,
    );
  }

  /// [fragment] with `id` added to its selection sets.
  FragmentDefinitionNode fragment(FragmentDefinitionNode fragment) =>
      FragmentDefinitionNode(
        name: fragment.name,
        typeCondition: fragment.typeCondition,
        directives: fragment.directives,
        selectionSet:
            _set(fragment.selectionSet, fragment.typeCondition.on.name.value),
        span: fragment.span,
      );

  /// [set] of type [type] with `id` added, and in its subselections.
  ///
  /// [inherited] is set for selections that share the objects of the
  /// selection around them (the root, inline fragments on the same type or
  /// inside a selection that has `id`): they add nothing, and pass on
  /// whether the objects have `id`.
  SelectionSetNode _set(SelectionSetNode set, String type, {bool? inherited}) {
    final directKeys = {
      for (final s in set.selections.whereType<FieldNode>())
        (s.alias ?? s.name).value,
    };
    final blocked = _aliasesId(set, {});
    if (blocked) _checkSpreads(set, {});
    final add = inherited == null &&
        !blocked &&
        !directKeys.contains('id') &&
        _isEligible(type);
    // Whether inline fragments in this set must not add `id`: the objects
    // have it already, or another field takes the `id` key.
    final hasId =
        (inherited ?? false) || add || blocked || directKeys.contains('id');

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
        final next = _set(selectionSet, fieldType);
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
        final next = _set(selectionSet, on,
            inherited: parentHasId || on == parent ? parentHasId : null);
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

  /// Whether a field other than `id` is aliased `id` in [set], its inline
  /// fragments or the fragments it spreads (the fields of one object).
  bool _aliasesId(SelectionSetNode set, Set<String> visiting) {
    for (final sel in set.selections) {
      switch (sel) {
        case FieldNode(:final alias?, :final name)
            when alias.value == 'id' && name.value != 'id':
          return true;
        case InlineFragmentNode(:final selectionSet):
          if (_aliasesId(selectionSet, visiting)) return true;
        case FragmentSpreadNode(:final name):
          final def = _fragmentDefs[name.value];
          if (def != null &&
              visiting.add(name.value) &&
              _aliasesId(def.selectionSet, visiting)) {
            return true;
          }
        default:
      }
    }
    return false;
  }

  /// Throws when a fragment spread in [set] (which aliases `id`) gets `id`
  /// in its own definition: the document couldn't be valid.
  void _checkSpreads(SelectionSetNode set, Set<String> visiting) {
    for (final sel in set.selections) {
      switch (sel) {
        case InlineFragmentNode(:final selectionSet):
          _checkSpreads(selectionSet, visiting);
        case FragmentSpreadNode(:final name):
          final def = _fragmentDefs[name.value];
          if (def == null || !visiting.add(name.value)) continue;
          if (_fragmentAddsId(name.value)) {
            throw CodegenException(
              CodegenErrorCodes.buildIdAliasConflict,
              'add_id_fields adds `id` to fragment "${name.value}", but it is '
              'spread where another field is aliased `id`. Rename that '
              'alias (e.g. `id: name` to `nameId: name`).',
            );
          }
          _checkSpreads(def.selectionSet, visiting);
        default:
      }
    }
  }

  /// Whether fragment [name] gets `id` in its definition.
  bool _fragmentAddsId(String name) => _fragmentAdds.putIfAbsent(name, () {
        final def = _fragmentDefs[name]!;
        final set = def.selectionSet;
        final selects = set.selections
            .any((s) => s is FieldNode && (s.alias ?? s.name).value == 'id');
        return !selects &&
            _isEligible(def.typeCondition.on.name.value) &&
            !_aliasesId(set, {name});
      });

  /// Whether [type] gets `id`: it has one, and every type it shares a union
  /// or interface with has the same `id` type, or none.
  bool _isEligible(String type) => _eligible.putIfAbsent(type, () {
        final own = _idType(type);
        if (own == null) return false;
        for (final container in _containers[type] ?? const <String>{}) {
          for (final other in {container, ...?_possible[container]}) {
            final theirs = _idType(other);
            if (theirs != null && theirs != own) return false;
          }
        }
        // An interface: its implementations must agree with it, too.
        for (final other in _possible[type] ?? const <String>{}) {
          final theirs = _idType(other);
          if (theirs != null && theirs != own) return false;
        }
        return true;
      });

  /// The type of [type]'s `id` field (`ID!`), or null when it has none that
  /// a selection can take: a scalar `id` without required arguments.
  String? _idType(String type) => _idTypes.putIfAbsent(type, () {
        final id = _fields(type).where((f) => f.name.value == 'id').firstOrNull;
        if (id == null) return null;
        if (id.args.any((a) => a.type.isNonNull && a.defaultValue == null)) {
          return null;
        }
        final named = _named(id.type);
        final scalar = _types[named] is ScalarTypeDefinitionNode ||
            const {'ID', 'String', 'Int', 'Float', 'Boolean'}.contains(named);
        return scalar ? gql_lang.printNode(id.type) : null;
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
