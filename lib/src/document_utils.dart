/// AST helpers for preparing GraphQL documents and schemas for generation.
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

import 'diagnostics.dart';

/// Utilities that operate on parsed GraphQL documents.
class DocumentUtils {
  /// Collects all fragment definitions from [documents], keyed by name.
  ///
  /// Throws a [CodegenException] when two different fragments share a name.
  static Map<String, FragmentDefinitionNode> collectFragments(
      Iterable<DocumentNode> documents) {
    final fragments = <String, FragmentDefinitionNode>{};
    for (final doc in documents) {
      for (final def in doc.definitions.whereType<FragmentDefinitionNode>()) {
        final name = def.name.value;
        final existing = fragments[name];
        if (existing != null &&
            gql_lang.printNode(existing) != gql_lang.printNode(def)) {
          throw CodegenException(
            CodegenErrorCodes.buildDuplicateFragment,
            'Fragment "$name" is defined more than once with different '
            'selections',
          );
        }
        fragments[name] = def;
      }
    }
    return fragments;
  }

  /// Builds a standalone document for [operation]: the operation itself plus
  /// every fragment it uses (transitively), with `__typename` added to every
  /// selection set so abstract types (interfaces/unions) can be resolved.
  static DocumentNode buildOperationDocument(
    OperationDefinitionNode operation,
    Map<String, FragmentDefinitionNode> fragments,
  ) {
    final used = <String>{};

    void visit(SelectionSetNode set) {
      for (final sel in set.selections) {
        if (sel is FieldNode && sel.selectionSet != null) {
          visit(sel.selectionSet!);
        } else if (sel is InlineFragmentNode) {
          visit(sel.selectionSet);
        } else if (sel is FragmentSpreadNode) {
          final name = sel.name.value;
          if (used.add(name)) {
            final fragment = fragments[name];
            if (fragment == null) {
              throw CodegenException(
                CodegenErrorCodes.buildMissingFragment,
                'Operation "${operation.name?.value ?? '<anonymous>'}" uses '
                'unknown fragment "$name"',
              );
            }
            visit(fragment.selectionSet);
          }
        }
      }
    }

    visit(operation.selectionSet);

    final usedFragments = used.toList()..sort();
    return DocumentNode(definitions: [
      OperationDefinitionNode(
        type: operation.type,
        name: operation.name,
        variableDefinitions: operation.variableDefinitions,
        directives: operation.directives,
        selectionSet: _addTypename(operation.selectionSet, isRoot: true),
      ),
      for (final name in usedFragments)
        FragmentDefinitionNode(
          name: fragments[name]!.name,
          typeCondition: fragments[name]!.typeCondition,
          directives: fragments[name]!.directives,
          selectionSet:
              _addTypename(fragments[name]!.selectionSet, isRoot: false),
        ),
    ]);
  }

  static SelectionSetNode _addTypename(SelectionSetNode set,
      {required bool isRoot}) {
    final selections = <SelectionNode>[
      for (final sel in set.selections)
        if (sel is FieldNode && sel.selectionSet != null)
          FieldNode(
            alias: sel.alias,
            name: sel.name,
            arguments: sel.arguments,
            directives: sel.directives,
            selectionSet: _addTypename(sel.selectionSet!, isRoot: false),
          )
        else if (sel is InlineFragmentNode)
          InlineFragmentNode(
            typeCondition: sel.typeCondition,
            directives: sel.directives,
            // The enclosing selection set already requests __typename.
            selectionSet: _addTypename(sel.selectionSet, isRoot: true),
          )
        else
          sel,
    ];

    final hasTypename = selections.any((s) =>
        s is FieldNode && s.alias == null && s.name.value == '__typename');
    if (!isRoot && !hasTypename) {
      selections.add(const FieldNode(name: NameNode(value: '__typename')));
    }
    return SelectionSetNode(selections: selections);
  }

  /// Folds `extend type`/`extend input`/`extend enum`/... definitions into the
  /// types they extend, so generators only have to look at base definitions.
  static DocumentNode mergeSchemaExtensions(DocumentNode schema) {
    final extensions =
        schema.definitions.whereType<TypeExtensionNode>().toList();
    if (extensions.isEmpty) return schema;

    final byName = <String, List<TypeExtensionNode>>{};
    for (final ext in extensions) {
      byName.putIfAbsent(ext.name.value, () => []).add(ext);
    }

    final merged = <DefinitionNode>[];
    final baseNames = <String>{};
    for (final def in schema.definitions) {
      if (def is TypeExtensionNode) continue;
      if (def is! TypeDefinitionNode) {
        merged.add(def);
        continue;
      }
      baseNames.add(def.name.value);
      merged.add(_applyExtensions(def, byName[def.name.value] ?? const []));
    }

    // An extension without a base definition (e.g. `extend type Query` in a
    // schema split across files) becomes the definition itself.
    for (final entry in byName.entries) {
      if (baseNames.contains(entry.key)) continue;
      final first = entry.value.first;
      final base = _extensionAsDefinition(first);
      if (base != null) {
        merged.add(_applyExtensions(base, entry.value.skip(1).toList()));
      }
    }

    return DocumentNode(definitions: merged);
  }

  static TypeDefinitionNode _applyExtensions(
      TypeDefinitionNode def, List<TypeExtensionNode> exts) {
    if (exts.isEmpty) return def;
    if (def is ObjectTypeDefinitionNode) {
      final e = exts.whereType<ObjectTypeExtensionNode>();
      return ObjectTypeDefinitionNode(
        name: def.name,
        description: def.description,
        directives: [...def.directives, for (final x in e) ...x.directives],
        interfaces: [...def.interfaces, for (final x in e) ...x.interfaces],
        fields: [...def.fields, for (final x in e) ...x.fields],
      );
    }
    if (def is InterfaceTypeDefinitionNode) {
      final e = exts.whereType<InterfaceTypeExtensionNode>();
      return InterfaceTypeDefinitionNode(
        name: def.name,
        description: def.description,
        directives: [...def.directives, for (final x in e) ...x.directives],
        interfaces: [...def.interfaces, for (final x in e) ...x.interfaces],
        fields: [...def.fields, for (final x in e) ...x.fields],
      );
    }
    if (def is InputObjectTypeDefinitionNode) {
      final e = exts.whereType<InputObjectTypeExtensionNode>();
      return InputObjectTypeDefinitionNode(
        name: def.name,
        description: def.description,
        directives: [...def.directives, for (final x in e) ...x.directives],
        fields: [...def.fields, for (final x in e) ...x.fields],
      );
    }
    if (def is EnumTypeDefinitionNode) {
      final e = exts.whereType<EnumTypeExtensionNode>();
      return EnumTypeDefinitionNode(
        name: def.name,
        description: def.description,
        directives: [...def.directives, for (final x in e) ...x.directives],
        values: [...def.values, for (final x in e) ...x.values],
      );
    }
    if (def is UnionTypeDefinitionNode) {
      final e = exts.whereType<UnionTypeExtensionNode>();
      return UnionTypeDefinitionNode(
        name: def.name,
        description: def.description,
        directives: [...def.directives, for (final x in e) ...x.directives],
        types: [...def.types, for (final x in e) ...x.types],
      );
    }
    return def;
  }

  static TypeDefinitionNode? _extensionAsDefinition(TypeExtensionNode ext) {
    if (ext is ObjectTypeExtensionNode) {
      return ObjectTypeDefinitionNode(
        name: ext.name,
        directives: ext.directives,
        interfaces: ext.interfaces,
        fields: ext.fields,
      );
    }
    if (ext is InterfaceTypeExtensionNode) {
      return InterfaceTypeDefinitionNode(
        name: ext.name,
        directives: ext.directives,
        interfaces: ext.interfaces,
        fields: ext.fields,
      );
    }
    if (ext is InputObjectTypeExtensionNode) {
      return InputObjectTypeDefinitionNode(
        name: ext.name,
        directives: ext.directives,
        fields: ext.fields,
      );
    }
    if (ext is EnumTypeExtensionNode) {
      return EnumTypeDefinitionNode(
        name: ext.name,
        directives: ext.directives,
        values: ext.values,
      );
    }
    if (ext is UnionTypeExtensionNode) {
      return UnionTypeDefinitionNode(
        name: ext.name,
        directives: ext.directives,
        types: ext.types,
      );
    }
    if (ext is ScalarTypeExtensionNode) {
      return ScalarTypeDefinitionNode(
          name: ext.name, directives: ext.directives);
    }
    return null;
  }
}
