/// Result classes that follow the selections of an operation or fragment
/// (`result_types: operation`).
///
/// A selection becomes a class with exactly the selected fields. Selections
/// on interfaces and unions become a sealed class with one subclass per type
/// that has type-specific fields, plus `_Other` for every other type. Each
/// fragment becomes an interface that the classes spreading it implement.
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

import 'code_utils.dart';
import 'config_context.dart';
import 'diagnostics.dart';
import 'json_exprs.dart';
import 'naming.dart';
import 'schema_analyzer.dart';

/// Classes generated for one operation.
class OperationClasses {
  OperationClasses._({
    required this.code,
    required this.returnType,
    required this.writeType,
    required String Function(String data) parse,
    required String Function(String data) write,
    required this.usesFragments,
  })  : _parse = parse,
        _write = write;

  /// Declarations of the result classes.
  final String code;

  /// Return type of `parse<Op>Data`.
  final String returnType;

  /// Type of the `data` parameter of `write<Op>`.
  final String writeType;

  /// Whether [code] refers to declarations of `fragments.dart`.
  final bool usesFragments;

  final String Function(String data) _parse;
  final String Function(String data) _write;

  /// Expression turning the non-null response map [data] into [returnType].
  String parseExpr(String data) => _parse(data);

  /// Expression turning the typed local variable [data] into the response
  /// map written to the cache (root `__typename` included).
  String writeExpr(String data) => _write(data);
}

/// Builds result classes for operations and fragments of one schema.
///
/// [schema] must already be merged with its extensions, and
/// `SchemaAnalyzer.extractCustomTypesAndEnums` must have run for it.
class OperationTypes {
  OperationTypes(
      DocumentNode schema, Map<String, FragmentDefinitionNode> fragments)
      : _ctx = _Context(
          _SchemaInfo(schema),
          fragments,
          legacy: !CodegenConfigContext.strictNullability,
        );

  final _Context _ctx;

  /// Generates the classes for [operation] named [name] whose root type is
  /// [rootType].
  OperationClasses operation(
      OperationDefinitionNode operation, String name, String rootType) {
    final pascal = name.capitalize();
    final names = _Names({
      ..._ctx.reserved,
      ..._ctx.fragmentFileNamesNear(pascal),
      '${pascal}Variables',
    });
    final resultName = names.claim('${pascal}Result');
    final root = _Builder(_ctx, names, fragmentFile: false).root(
      resultName,
      pascal,
      rootType,
      operation.selectionSet,
      label: name,
      doc: 'Typed `data` of the `$name` ${operation.type.name}.',
    );

    final emitter = _Emitter(_ctx);
    final fields = root.fields;
    if (fields.length > 1) {
      emitter.tree(root);
    } else {
      for (final child in root.children) {
        emitter.tree(child);
      }
    }
    emitter.finish();

    final String returnType;
    final String writeType;
    final String Function(String) parse;
    final String Function(String) write;
    if (fields.isEmpty) {
      returnType = 'Map<String, dynamic>?';
      writeType = 'Map<String, dynamic>';
      parse = (data) => data;
      write = (data) => data;
    } else if (fields.length == 1) {
      final f = fields.single;
      returnType = emitter.dartType(f);
      writeType = returnType;
      parse = (data) => emitter.fromJson(f, "$data['${f.key}']");
      write = (data) => "<String, dynamic>{'__typename': '$rootType', "
          "'${f.key}': ${emitter.toJson(f, data, promotable: true)}}";
    } else {
      returnType = _ctx.legacy ? '$resultName?' : resultName;
      writeType = resultName;
      parse = (data) => '$resultName.fromJson($data)';
      write = (data) =>
          "<String, dynamic>{'__typename': '$rootType', ...$data.toJson()}";
    }

    return OperationClasses._(
      code: emitter.code,
      returnType: returnType,
      writeType: writeType,
      parse: parse,
      write: write,
      usesFragments: emitter.usesFragments,
    );
  }

  /// Names of the fragments with generated declarations, sorted.
  ///
  /// Fragments on introspection types (`__Type`, ...) have none: the
  /// fields selecting them (`__schema`, `__type`) are raw JSON maps.
  List<String> get fragmentNames => _ctx.declaredFragments;

  /// GraphQL type the fragment [name] is on.
  String fragmentType(String name) =>
      _ctx.fragment(name).typeCondition.on.name.value;

  /// Interface declarations of fragment [name] (the interface, its nested
  /// interfaces and its type-specific interfaces).
  String fragmentInterfaces(String name) {
    final emitter = _Emitter(_ctx)..tree(_ctx.fragmentInterface(name));
    return emitter.code;
  }

  /// Class declarations of the data classes of fragment [name] (named
  /// `<Fragment>Data`).
  String fragmentData(String name) {
    final emitter = _Emitter(_ctx)..tree(_ctx.fragmentFile.data[name]!);
    return emitter.code;
  }

  /// Dart name of the data class of fragment [name].
  String fragmentDataClass(String name) => _ctx.fragmentFile.data[name]!.name;

  /// Dart name of the interface of fragment [name].
  String fragmentInterfaceName(String name) =>
      _ctx.fragmentInterface(name).name;

  /// Shared declarations every file with data classes needs, or ''.
  String get support =>
      _ctx.fragmentFile.data.isEmpty ? '' : _Emitter.undefined;

  /// Validates all fragments and returns the names declared for them;
  /// throws when two fragments would declare the same name.
  Set<String> checkFragments() => _ctx.fragmentFile.names;
}

// -----------------------------------------------------------------------------
// Schema lookups
// -----------------------------------------------------------------------------

class _SchemaInfo {
  _SchemaInfo(DocumentNode schema)
      : types = {
          for (final d in schema.definitions.whereType<TypeDefinitionNode>())
            d.name.value: d,
        },
        rootTypes = _rootTypes(schema);

  final Map<String, TypeDefinitionNode> types;

  /// Names of the query, mutation and subscription types.
  final Set<String> rootTypes;

  static Set<String> _rootTypes(DocumentNode schema) {
    final names = <String>{};
    for (final kind in const ['query', 'mutation', 'subscription']) {
      try {
        final root = SchemaAnalyzer.findRootType(schema, kind);
        if (root != null) names.add(root.name.value);
      } on StateError {
        // No such root type.
      }
    }
    return names;
  }

  bool isAbstract(String type) {
    final def = types[type];
    return def is InterfaceTypeDefinitionNode || def is UnionTypeDefinitionNode;
  }

  bool isComposite(String type) =>
      isAbstract(type) || types[type] is ObjectTypeDefinitionNode;

  /// Concrete types a value of [type] can have.
  List<String> possible(String type) =>
      isAbstract(type) ? TypeRegistry.possibleTypes(type) : [type];

  /// Whether a fragment on [condition] (null: no condition) applies to a
  /// value of concrete type [concrete].
  bool applies(String? condition, String concrete) =>
      condition == null ||
      condition == concrete ||
      possible(condition).contains(concrete);

  /// Whether a fragment on [condition] applies to every value of [type].
  bool coversAll(String? condition, String type) {
    if (condition == null || condition == type) return true;
    final own = possible(type);
    final covered = possible(condition);
    return own.isNotEmpty && own.every(covered.contains);
  }

  FieldDefinitionNode? field(String type, String name) {
    final def = types[type];
    final fields = def is ObjectTypeDefinitionNode
        ? def.fields
        : def is InterfaceTypeDefinitionNode
            ? def.fields
            : const <FieldDefinitionNode>[];
    return fields.where((f) => f.name.value == name).firstOrNull;
  }
}

// -----------------------------------------------------------------------------
// Selection model
// -----------------------------------------------------------------------------

/// A selection set, the type its selections are on and the `@skip` /
/// `@include` directives it depends on (relative to the enclosing object).
class _Sel {
  const _Sel(this.set, this.scope, [this.conditions = const {}]);

  final SelectionSetNode set;
  final String scope;
  final Set<String> conditions;
}

/// One occurrence of a field in a selection.
class _Occurrence {
  const _Occurrence(this.node, this.scope, this.conditions);

  final FieldNode node;
  final String scope;
  final Set<String> conditions;

  String get key => node.alias?.value ?? node.name.value;
}

enum _Kind {
  /// A concrete class parsed from JSON.
  klass,

  /// A sealed base class of a selection on an interface or union.
  sealed,

  /// An interface (fragments, and the nested types of sealed classes).
  iface,
}

enum _FieldKind {
  typename,

  /// `__schema` / `__type`: raw JSON maps.
  introspection,

  /// Not in the schema (only with `validate_documents: false`): raw JSON.
  untyped,
  regular,
}

/// A generated class or interface.
class _Shape {
  _Shape(this.kind, this.name, this.type, this.label, this.doc,
      {required this.fragment, String? path})
      : path = path ?? name;

  final _Kind kind;
  final String name;

  /// GraphQL type: the concrete type of a class, the abstract type of a
  /// sealed class, `_Other` class or abstract interface.
  final String type;

  /// `Operation.field.field` path for doc comments.
  final String label;
  final String doc;

  /// Declared in `fragments.dart`.
  final bool fragment;

  /// Prefix of the names of nested classes.
  final String path;

  final List<_Field> fields = [];
  List<_Shape> supers = const [];

  /// Type-specific subclasses (or interfaces) by concrete type.
  final Map<String, _Shape> variants = {};

  /// Fallback subclass of a sealed class.
  _Shape? other;

  /// Name of the copyWith interface (classes only).
  String? copyWith;

  /// `__typename` used when the JSON has none (classes of a concrete type).
  String? typenameFallback;

  _Field? field(String key) => fields.where((f) => f.key == key).firstOrNull;

  bool isSubtypeOf(_Shape other) =>
      identical(this, other) || supers.any((s) => s.isSubtypeOf(other));

  /// Shapes declared after this one, in declaration order.
  Iterable<_Shape> get children sync* {
    for (final f in fields) {
      if (f.nested != null) yield f.nested!;
    }
    yield* variants.values;
    if (other != null) yield other!;
  }
}

class _Field {
  _Field({
    required this.kind,
    required this.key,
    required this.dartName,
    this.type,
    this.forced = false,
    this.nested,
    this.def,
    this.overrides = false,
  });

  final _FieldKind kind;

  /// Response key (alias or field name).
  final String key;
  final String dartName;

  /// Schema type (regular fields only).
  final TypeNode? type;

  /// Nullable because of `@skip` / `@include`.
  final bool forced;
  final _Shape? nested;
  final FieldDefinitionNode? def;
  final bool overrides;

  /// Name of the `<field>Raw` sibling of an enum field, if any.
  String? rawName;
  bool rawOverrides = false;

  bool get rawList => type is ListTypeNode;
}

/// Unique class names within one generated file.
class _Names {
  _Names([Iterable<String> taken = const []]) : _taken = {...taken};

  final Set<String> _taken;

  String claim(String desired) {
    var name = desired;
    for (var i = 2; !_taken.add(name); i++) {
      name = '${desired}_$i';
    }
    return name;
  }
}

/// Fields every generated class has, so selected fields can't use them.
const _memberNames = {
  'typename', 'copyWith', 'identical', 'graphqlDeepEquals', //
  'graphqlDeepHash',
};

String _namedType(TypeNode type) => type is ListTypeNode
    ? _namedType(type.type)
    : (type as NamedTypeNode).name.value;

/// PascalCase segment of a nested class name for response key [key].
String _segment(String key) {
  final stripped = key.replaceFirst(RegExp('^_+'), '');
  if (stripped.isEmpty) return 'Value';
  return stripped[0].toUpperCase() + stripped.substring(1);
}

Set<String> _withConditions(Set<String> base, List<DirectiveNode> directives) {
  final added = [
    for (final d in directives)
      if (d.name.value == 'skip' || d.name.value == 'include')
        gql_lang.printNode(d),
  ];
  return added.isEmpty ? base : {...base, ...added};
}

// -----------------------------------------------------------------------------
// Building
// -----------------------------------------------------------------------------

/// State shared by the builders of one generation run.
class _Context {
  _Context(this.schema, this.fragments, {required this.legacy})
      : reserved = _reservedNames();

  final _SchemaInfo schema;
  final Map<String, FragmentDefinitionNode> fragments;
  final bool legacy;

  /// Type names generated code must not declare: built-in names and the
  /// declarations of types.dart (enums, inputs, scalars).
  final Set<String> reserved;

  final Map<String, _Shape> _interfaces = {};
  final Set<String> _building = {};
  _FragmentFile? _fragmentFile;

  static Set<String> _reservedNames() {
    final names = {...reservedTypeNames, 'Decimal', 'Long', 'Byte'};
    for (final t in [
      ...TypeRegistry.enumTypes,
      ...TypeRegistry.customScalars.where(TypeRegistry.isWrappedScalar),
    ]) {
      final dart = SchemaAnalyzer.dartTypeName(t);
      names
        ..add(dart)
        ..add('${dart}Converter');
    }
    names.addAll(TypeRegistry.inputTypes.map(SchemaAnalyzer.dartTypeName));
    return names;
  }

  FragmentDefinitionNode fragment(String name) {
    final def = fragments[name];
    if (def == null) {
      throw CodegenException(
        CodegenErrorCodes.buildMissingFragment,
        'Unknown fragment "$name"',
      );
    }
    return def;
  }

  /// Dart name of the interface of fragment [name].
  String fragmentClassName(String name) {
    var dart = name;
    while (reserved.contains(dart) || dartReservedWords.contains(dart)) {
      dart = '${dart}_';
    }
    return dart;
  }

  /// The interface of fragment [name] (built on first use).
  _Shape fragmentInterface(String name) {
    final cached = _interfaces[name];
    if (cached != null) return cached;
    if (!_building.add(name)) {
      throw CodegenException(
        CodegenErrorCodes.buildInvalidSelection,
        'Fragment "$name" spreads itself',
      );
    }
    final def = fragment(name);
    final type = def.typeCondition.on.name.value;
    if (!schema.isComposite(type)) {
      throw CodegenException(
        CodegenErrorCodes.buildInvalidSelection,
        'Fragment "$name" is on "$type", which is not an object, interface '
        'or union type',
      );
    }
    final shape = _Builder(this, _Names(reserved), fragmentFile: true).group(
      fragmentClassName(name),
      type,
      [_Sel(def.selectionSet, type)],
      const [],
      klass: false,
      label: name,
      typename: !schema.rootTypes.contains(type),
      doc: 'Fields of the `$name` fragment on `$type`.',
    );
    _building.remove(name);
    return _interfaces[name] = shape;
  }

  _FragmentFile get fragmentFile => _fragmentFile ??= _FragmentFile(this);

  /// Fragments that get declarations in `fragments.dart`, sorted: all but
  /// those on introspection types, which only appear inside `__schema` /
  /// `__type` selections (raw JSON maps).
  late final List<String> declaredFragments = [
    for (final MapEntry(:key, :value) in fragments.entries)
      if (!value.typeCondition.on.name.value.startsWith('__')) key,
  ]..sort();

  /// Names declared in `fragments.dart` that an operation named [pascal]
  /// could also declare (all of its names start with [pascal]).
  Set<String> fragmentFileNamesNear(String pascal) {
    final near = declaredFragments.where((f) {
      final name = fragmentClassName(f);
      return pascal.startsWith(name) || name.startsWith(pascal);
    });
    if (near.isEmpty) return const {};
    return fragmentFile.names;
  }
}

/// Everything declared in `fragments.dart`.
class _FragmentFile {
  _FragmentFile(_Context ctx) {
    final sorted = ctx.declaredFragments;
    final owners = <String, String>{};
    void collect(_Shape shape, String fragment) {
      for (final name in [
        shape.name,
        if (shape.copyWith != null) shape.copyWith!
      ]) {
        final owner = owners[name];
        if (owner != null && owner != fragment) {
          throw CodegenException(
            CodegenErrorCodes.buildDuplicateFragment,
            'Fragments "$owner" and "$fragment" both generate a type named '
            '"$name"; rename one of them',
          );
        }
        owners[name] = fragment;
      }
      for (final child in shape.children) {
        collect(child, fragment);
      }
    }

    for (final f in sorted) {
      collect(ctx.fragmentInterface(f), f);
    }
    final names = _Names({...ctx.reserved, ...owners.keys});
    for (final f in sorted) {
      final def = ctx.fragment(f);
      final type = def.typeCondition.on.name.value;
      final spread = SelectionSetNode(
          selections: [FragmentSpreadNode(name: NameNode(value: f))]);
      final shape = _Builder(ctx, names, fragmentFile: true).group(
        '${ctx.fragmentClassName(f)}Data',
        type,
        [_Sel(spread, type)],
        const [],
        klass: true,
        label: f,
        typename: !ctx.schema.rootTypes.contains(type),
        doc: 'Data of the `$f` fragment, for example read from the cache.',
      );
      data[f] = shape;
      collect(shape, f);
    }
    this.names.addAll(owners.keys);
  }

  /// Data class of each fragment.
  final Map<String, _Shape> data = {};
  final Set<String> names = {};
}

class _Builder {
  _Builder(this.ctx, this.names, {required this.fragmentFile});

  final _Context ctx;
  final _Names names;
  final bool fragmentFile;

  _SchemaInfo get schema => ctx.schema;

  /// The class of an operation's `data` (no `__typename`).
  _Shape root(String name, String path, String type, SelectionSetNode set,
      {required String label, required String doc}) {
    final shape = _Shape(_Kind.klass, name, type, label, doc,
        fragment: fragmentFile, path: path);
    _fill(shape, [_Sel(set, type)], (c) => schema.applies(c, type), const [],
        typename: false);
    return shape;
  }

  /// The class (or sealed class family, or interface family when not
  /// [klass]) for selections [sels] on [type]. [required] are interfaces the
  /// result must implement (the nested types of the enclosing class's
  /// supertypes for this field).
  _Shape group(
    String desired,
    String type,
    List<_Sel> sels,
    List<_Shape> required, {
    required bool klass,
    required String label,
    bool typename = true,
    String? doc,
  }) {
    final concreteKind = klass ? _Kind.klass : _Kind.iface;
    if (!schema.isAbstract(type)) {
      final shape = _Shape(concreteKind, names.claim(desired), type, label,
          doc ?? '`$label` (a `$type`).',
          fragment: fragmentFile);
      _fill(shape, sels, (c) => schema.applies(c, type), required,
          typename: typename, typenameFallback: type);
      return shape;
    }

    final base = _Shape(
      klass ? _Kind.sealed : _Kind.iface,
      names.claim(desired),
      type,
      label,
      doc ??
          (klass
              ? '`$label` (a `$type`); switch over its subclasses.'
              : '`$label` (a `$type`).'),
      fragment: fragmentFile,
    );
    final variantTypes = <String>{
      for (final c in schema.possible(type))
        if (_hasSpecific(sels, type, c, const {})) c,
      for (final r in required) ...r.variants.keys,
    }.toList()
      ..sort();
    for (final c in variantTypes) {
      base.variants[c] = _Shape(concreteKind, names.claim('${base.name}_On$c'),
          c, label, '`$label` when it is a `$c`.',
          fragment: fragmentFile);
    }
    if (klass) {
      base.other = _Shape(
          _Kind.klass,
          names.claim('${base.name}_Other'),
          type,
          label,
          '`$label` of any other type, including types added to the '
          'schema after this code was generated.',
          fragment: fragmentFile);
    }

    bool covers(String? c) => schema.coversAll(c, type);
    _fill(base, sels, covers, required, typename: typename);
    for (final c in variantTypes) {
      _fill(
        base.variants[c]!,
        sels,
        (x) => schema.applies(x, c),
        [
          base,
          for (final r in required)
            if (r.variants[c] != null) r.variants[c]!,
        ],
        typename: typename,
        typenameFallback: c,
      );
    }
    if (base.other != null) {
      _fill(base.other!, sels, covers, [base], typename: typename);
    }
    return base;
  }

  /// Whether [sels] on abstract [type] have a fragment applying to concrete
  /// type [concrete] but not to every type of [type].
  bool _hasSpecific(
      List<_Sel> sels, String type, String concrete, Set<String> active) {
    for (final sel in sels) {
      for (final node in sel.set.selections) {
        String? condition;
        SelectionSetNode set;
        var nextActive = active;
        if (node is InlineFragmentNode) {
          condition = node.typeCondition?.on.name.value;
          set = node.selectionSet;
        } else if (node is FragmentSpreadNode) {
          final name = node.name.value;
          if (active.contains(name)) continue;
          final def = ctx.fragment(name);
          condition = def.typeCondition.on.name.value;
          set = def.selectionSet;
          nextActive = {...active, name};
        } else {
          continue;
        }
        if (schema.coversAll(condition, type)) {
          if (_hasSpecific([_Sel(set, condition ?? sel.scope)], type, concrete,
              nextActive)) {
            return true;
          }
        } else if (schema.applies(condition, concrete)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Visits the fields of [sels] (through fragments [include] accepts) and
  /// the fragment spreads on the way.
  void _walk(
    List<_Sel> sels,
    bool Function(String? condition) include,
    void Function(_Occurrence) onField,
    void Function(String fragment, Set<String> conditions) onSpread, [
    Set<String> active = const {},
  ]) {
    for (final sel in sels) {
      for (final node in sel.set.selections) {
        if (node is FieldNode) {
          onField(_Occurrence(node, sel.scope,
              _withConditions(sel.conditions, node.directives)));
        } else if (node is InlineFragmentNode) {
          final condition = node.typeCondition?.on.name.value;
          if (!include(condition)) continue;
          _walk([
            _Sel(node.selectionSet, condition ?? sel.scope,
                _withConditions(sel.conditions, node.directives)),
          ], include, onField, onSpread, active);
        } else if (node is FragmentSpreadNode) {
          final name = node.name.value;
          final def = ctx.fragment(name);
          final condition = def.typeCondition.on.name.value;
          if (!include(condition)) continue;
          if (active.contains(name)) {
            throw CodegenException(
              CodegenErrorCodes.buildInvalidSelection,
              'Fragment "$name" spreads itself',
            );
          }
          final conditions = _withConditions(sel.conditions, node.directives);
          onSpread(name, conditions);
          _walk([_Sel(def.selectionSet, condition, conditions)], include,
              onField, onSpread, {...active, name});
        }
      }
    }
  }

  /// Fills [shape] with the fields [sels] select for its type.
  void _fill(
    _Shape shape,
    List<_Sel> sels,
    bool Function(String? condition) include,
    List<_Shape> required, {
    required bool typename,
    String? typenameFallback,
  }) {
    final occurrences = <String, List<_Occurrence>>{};
    final spreads = <String>[];
    _walk(
      sels,
      include,
      (o) => occurrences.putIfAbsent(o.key, () => []).add(o),
      (name, conditions) {
        if (conditions.isEmpty) spreads.add(name);
      },
    );

    // Interfaces: the required ones plus the fragments spread
    // unconditionally (their type-specific interface when there is one).
    final concrete = !schema.isAbstract(shape.type);
    final targets = [
      for (final f in spreads)
        if (ctx.fragmentInterface(f) case final i)
          concrete ? i.variants[shape.type] ?? i : i,
    ];
    shape.supers = _minimal([...required, ...targets]);
    if (shape.kind == _Kind.klass) {
      shape.copyWith = names.claim('${shape.name}_CopyWith');
      shape.typenameFallback = typenameFallback;
    }

    final used = <String>{};
    String unique(String name) {
      while (!used.add(name)) {
        name = '${name}_';
      }
      return name;
    }

    _Field? inherited(String key) =>
        shape.supers.map((s) => s.field(key)).nonNulls.firstOrNull;

    if (typename) {
      shape.fields.add(_Field(
        kind: _FieldKind.typename,
        key: '__typename',
        dartName: unique('typename'),
        overrides: inherited('__typename') != null,
      ));
    }

    for (final MapEntry(:key, value: occs) in occurrences.entries) {
      final first = occs.first;
      final fieldName = first.node.name.value;
      // The document validator reports this too; this guards
      // `validate_documents: false`, where it would clash with `typename`.
      final aliased = key == '__typename'
          ? occs.map((o) => o.node.name.value).where((n) => n != key)
          : const <String>[];
      if (aliased.firstOrNull case final other?) {
        throw CodegenException(
          CodegenErrorCodes.buildInvalidSelection,
          'Alias "__typename" on field "$other" is not allowed (in '
          '${shape.label}): "__typename" is reserved for the type name; '
          'rename the alias',
        );
      }
      if (fieldName == '__typename' && (!typename || key == '__typename')) {
        continue;
      }
      final parent = inherited(key);
      String dartName() {
        if (parent != null) return unique(parent.dartName);
        var name = dartFieldName(key, className: shape.name);
        if (_memberNames.contains(name)) name = '${name}_';
        return unique(name);
      }

      if (fieldName == '__schema' || fieldName == '__type') {
        shape.fields.add(_Field(
          kind: _FieldKind.introspection,
          key: key,
          dartName: dartName(),
          overrides: parent != null,
        ));
        continue;
      }

      final def = fieldName == '__typename'
          ? _typenameDef
          : schema.field(first.scope, fieldName) ??
              schema.field(shape.type, fieldName);
      if (def == null && !CodegenConfigContext.validateDocuments) {
        shape.fields.add(_Field(
          kind: _FieldKind.untyped,
          key: key,
          dartName: dartName(),
          overrides: parent != null,
        ));
        continue;
      }
      if (def == null) {
        throw CodegenException(
          CodegenErrorCodes.buildUnknownField,
          'Field "$fieldName" does not exist on type "${first.scope}" '
          '(in ${shape.label})',
        );
      }

      // @skip/@include may leave the field out, unless it is also selected
      // without them.
      final forced = occs.every((o) => o.conditions.isNotEmpty);
      final named = _namedType(def.type);
      _Shape? nested;
      if (schema.isComposite(named)) {
        final subs = [
          for (final o in occs)
            if (o.node.selectionSet != null)
              _Sel(
                o.node.selectionSet!,
                named,
                // Conditions that hold whenever the field is present don't
                // make its subfields optional.
                occs.every((j) => j.conditions.containsAll(o.conditions))
                    ? const {}
                    : o.conditions,
              ),
        ];
        if (subs.isEmpty) {
          throw CodegenException(
            CodegenErrorCodes.buildInvalidSelection,
            'Field "$fieldName" of type "$named" needs a selection of '
            'subfields (in ${shape.label})',
          );
        }
        nested = group(
          '${shape.path}_${_segment(key)}',
          named,
          subs,
          [
            for (final s in shape.supers)
              if (s.field(key)?.nested case final n?) n,
          ],
          klass: shape.kind == _Kind.klass,
          label: '${shape.label}.$key',
        );
      }

      final field = _Field(
        kind: _FieldKind.regular,
        key: key,
        dartName: dartName(),
        type: def.type,
        forced: forced,
        nested: nested,
        def: def,
        overrides: parent != null,
      );
      shape.fields.add(field);

      // `<field>Raw` keeps the server's string next to `$unknown`.
      final rawType =
          def.type is ListTypeNode ? (def.type as ListTypeNode).type : def.type;
      if (CodegenConfigContext.unknownEnumFallback &&
          rawType is NamedTypeNode &&
          TypeRegistry.isEnum(rawType.name.value)) {
        field.rawName = parent?.rawName != null
            ? unique(parent!.rawName!)
            : unique(dartFieldName('${key}Raw', className: shape.name));
        field.rawOverrides = parent?.rawName != null;
      }
    }
  }

  static const _typenameDef = FieldDefinitionNode(
    name: NameNode(value: '__typename'),
    type: NamedTypeNode(name: NameNode(value: 'String'), isNonNull: true),
  );

  /// [list] without duplicates and without types another one implements.
  static List<_Shape> _minimal(List<_Shape> list) {
    final unique = <_Shape>[];
    for (final s in list) {
      if (!unique.any((u) => identical(u, s))) unique.add(s);
    }
    return [
      for (final s in unique)
        if (!unique.any((o) => !identical(o, s) && o.isSubtypeOf(s))) s,
    ];
  }
}

// -----------------------------------------------------------------------------
// Emitting
// -----------------------------------------------------------------------------

class _Emitter {
  _Emitter(this.ctx);

  final _Context ctx;
  final StringBuffer _out = StringBuffer();
  bool _usesUndefined = false;
  bool usesFragments = false;

  /// Marker for copyWith parameters that were not passed.
  static const undefined =
      '/// Marks `copyWith` parameters that were not passed.\n'
      'const _undefined = Object();\n';

  String get code => _out.toString();

  /// Appends declarations shared by the classes written so far.
  void finish() {
    if (_usesUndefined) _out.writeln(undefined);
  }

  /// Writes [shape] and everything declared under it.
  void tree(_Shape shape) {
    switch (shape.kind) {
      case _Kind.klass:
        _klass(shape);
      case _Kind.sealed:
        _sealed(shape);
      case _Kind.iface:
        _iface(shape);
    }
    for (final child in shape.children) {
      tree(child);
    }
  }

  String dartType(_Field f) => switch (f.kind) {
        _FieldKind.typename => 'String',
        _FieldKind.introspection => 'Map<String, dynamic>?',
        _FieldKind.untyped => 'dynamic',
        _FieldKind.regular => JsonExprs.outputDartType(f.type!,
            legacy: ctx.legacy, forceNullable: f.forced, named: f.nested?.name),
      };

  String _rawType(_Field f) => f.rawList ? 'List<String?>?' : 'String?';

  /// Expression parsing JSON value [v] of field [f].
  String fromJson(_Field f, String v, {String? typenameFallback}) {
    switch (f.kind) {
      case _FieldKind.typename:
        return typenameFallback == null
            ? '$v as String'
            : "$v as String? ?? '$typenameFallback'";
      case _FieldKind.introspection:
        return '$v as Map<String, dynamic>?';
      case _FieldKind.untyped:
        return v;
      case _FieldKind.regular:
        final nested = f.nested;
        return JsonExprs.fromJsonExpr(f.type!, v,
            legacy: ctx.legacy,
            definedTypes: const {},
            forceNullable: f.forced,
            composite: nested == null
                ? null
                : (v) => '${nested.name}.fromJson($v as Map<String, dynamic>)');
    }
  }

  /// Expression serialising field [f] whose value is [v].
  String toJson(_Field f, String v, {bool promotable = false}) {
    if (f.kind != _FieldKind.regular) return v;
    final raw = f.rawName;
    if (raw != null && !promotable) return _enumToJson(f, v, raw);
    return JsonExprs.outputToJsonExpr(f.type!, v,
        legacy: ctx.legacy,
        forceNullable: f.forced,
        promotable: promotable,
        composite: f.nested == null ? null : (v) => '$v.toJson()');
  }

  /// An enum field with a `Raw` sibling: `$unknown` is written back as the
  /// string the server sent.
  String _enumToJson(_Field f, String v, String raw) {
    final type = f.type!;
    final name = SchemaAnalyzer.dartTypeName(_namedType(type));
    final converter = 'const ${name}Converter()';
    final unknown = '$name.\$unknown';
    final nullable = f.forced || ctx.legacy || !type.isNonNull;
    if (type is! ListTypeNode) {
      final known = nullable
          ? '$v == null ? null : $converter.toJson($v!)'
          : '$converter.toJson($v)';
      return '$v == $unknown ? $raw : $known';
    }
    final elementNullable = ctx.legacy || !type.type.isNonNull;
    final element = elementNullable
        ? 'e == null ? null : $converter.toJson(e)'
        : '$converter.toJson(e)';
    final list = '[for (final (i, e) in ${nullable ? '$v!' : v}.indexed) '
        'e == $unknown ? $raw?.elementAtOrNull(i) : $element]';
    return nullable ? '$v == null ? null : $list' : list;
  }

  String _implements(_Shape s) {
    if (s.supers.isEmpty) return '';
    if (!s.fragment && s.supers.any((x) => x.fragment)) usesFragments = true;
    return ' implements ${s.supers.map((x) => x.name).join(', ')}';
  }

  void _doc(String text, {String indent = ''}) {
    for (final line in text.trim().split('\n')) {
      final trimmed = line.trimRight();
      _out.writeln(trimmed.isEmpty ? '$indent///' : '$indent/// $trimmed');
    }
  }

  /// Doc comment and `@Deprecated` of a field from the schema.
  void _fieldDoc(_Field f) {
    final def = f.def;
    if (def == null) return;
    var text = def.description?.value.trim() ?? '';
    final reason = _deprecationReason(def.directives);
    if (reason != null && !CodegenConfigContext.deprecatedAnnotations) {
      text =
          text.isEmpty ? 'Deprecated: $reason' : '$text\n\nDeprecated: $reason';
    }
    if (text.isNotEmpty) _doc(text, indent: '  ');
    if (reason != null && CodegenConfigContext.deprecatedAnnotations) {
      final escaped = reason
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'")
          .replaceAll(r'$', r'\$')
          .replaceAll('\n', r'\n');
      _out.writeln("  @Deprecated('$escaped')");
    }
  }

  static String? _deprecationReason(List<DirectiveNode> directives) {
    final directive =
        directives.where((d) => d.name.value == 'deprecated').firstOrNull;
    if (directive == null) return null;
    final reason = directive.arguments
        .where((a) => a.name.value == 'reason')
        .firstOrNull
        ?.value;
    return reason is StringValueNode ? reason.value : 'No longer supported';
  }

  void _rawDoc(_Field f) => _out.writeln('  /// [${f.dartName}] as the server '
      'sent it, also when it is `\$unknown`.');

  /// Getters of an interface or sealed class.
  void _getters(_Shape s) {
    for (final f in s.fields) {
      _fieldDoc(f);
      if (f.overrides) _out.writeln('  @override');
      _out.writeln('  ${dartType(f)} get ${f.dartName};');
      if (f.rawName != null) {
        _out.writeln();
        _rawDoc(f);
        if (f.rawOverrides) _out.writeln('  @override');
        _out.writeln('  ${_rawType(f)} get ${f.rawName};');
      }
      _out.writeln();
    }
    if (s.supers.isNotEmpty) _out.writeln('  @override');
    _out.writeln('  Map<String, dynamic> toJson();');
  }

  void _iface(_Shape s) {
    _doc(s.doc);
    _out
      ..writeln('abstract interface class ${s.name}${_implements(s)} {')
      ..writeln();
    _getters(s);
    _out
      ..writeln('}')
      ..writeln();
  }

  void _sealed(_Shape s) {
    _doc(s.doc);
    _out
      ..writeln('sealed class ${s.name}${_implements(s)} {')
      ..writeln('  /// Parses the subclass matching `__typename`.')
      ..writeln('  factory ${s.name}.fromJson(Map<String, dynamic> json) =>')
      ..writeln("      switch (json['__typename']) {");
    for (final MapEntry(key: type, value: v) in s.variants.entries) {
      _out.writeln("        '$type' => ${v.name}.fromJson(json),");
    }
    _out
      ..writeln('        _ => ${s.other!.name}.fromJson(json),')
      ..writeln('      };')
      ..writeln();
    _getters(s);
    _out
      ..writeln('}')
      ..writeln();
  }

  /// Fields and raw siblings of a class: (Dart name, Dart type, field, raw).
  List<(String, String, _Field, bool)> _members(_Shape s) => [
        for (final f in s.fields) ...[
          (f.dartName, dartType(f), f, false),
          if (f.rawName != null) (f.rawName!, _rawType(f), f, true),
        ],
      ];

  static bool _deep(String type) {
    final t = type.replaceAll('?', '');
    return t.startsWith('List<') ||
        t.startsWith('Map<') ||
        t == 'dynamic' ||
        t == 'Object';
  }

  void _klass(_Shape s) {
    final members = _members(s);
    final name = s.name;
    _doc(s.doc);
    _out.writeln('class $name${_implements(s)} {');

    // Constructor.
    _out.writeln('  const $name({');
    for (final (dart, type, _, _) in members) {
      final optional = type.endsWith('?') || type == 'dynamic';
      _out.writeln(optional ? '    this.$dart,' : '    required this.$dart,');
    }
    _out
      ..writeln('  });')
      ..writeln();

    // fromJson.
    _out.writeln(
        '  factory $name.fromJson(Map<String, dynamic> json) => $name(');
    for (final (dart, _, f, raw) in members) {
      final v = "json['${f.key}']";
      final String expr;
      if (raw) {
        expr = f.rawList
            ? '($v as List<dynamic>?)?.map((e) => e as String?).toList()'
            : '$v as String?';
      } else {
        expr = fromJson(f, v, typenameFallback: s.typenameFallback);
      }
      _out.writeln('        $dart: $expr,');
    }
    _out
      ..writeln('      );')
      ..writeln();

    // Fields.
    for (final (dart, type, f, raw) in members) {
      if (raw) {
        _rawDoc(f);
        if (f.rawOverrides) _out.writeln('  @override');
      } else {
        _fieldDoc(f);
        if (f.overrides) _out.writeln('  @override');
      }
      _out
        ..writeln('  final $type $dart;')
        ..writeln();
    }

    // toJson.
    if (s.supers.isNotEmpty) _out.writeln('  @override');
    _out.writeln('  Map<String, dynamic> toJson() => <String, dynamic>{');
    for (final f in s.fields) {
      _out.writeln("        '${f.key}': ${toJson(f, f.dartName)},");
    }
    _out
      ..writeln('      };')
      ..writeln();

    // copyWith.
    final copyWith = s.copyWith!;
    _usesUndefined = true;
    _out
      ..writeln('  /// Copies this object with the given fields replaced.')
      ..writeln('  $copyWith get copyWith => _$copyWith(this);')
      ..writeln();

    // == and hashCode.
    String self(String dart) => dart == 'other' ? 'this.other' : dart;
    _out
      ..writeln('  @override')
      ..writeln('  bool operator ==(Object other) =>')
      ..writeln('      identical(this, other) ||')
      ..write('      other is $name');
    for (final (dart, type, _, _) in members) {
      _out.write(_deep(type)
          ? ' &&\n          graphqlDeepEquals(other.$dart, ${self(dart)})'
          : ' &&\n          other.$dart == ${self(dart)}');
    }
    _out
      ..writeln(';')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  int get hashCode => Object.hashAll([');
    for (final (dart, type, _, _) in members) {
      _out.writeln(
          _deep(type) ? '        graphqlDeepHash($dart),' : '        $dart,');
    }
    _out
      ..writeln('      ]);')
      ..writeln('}')
      ..writeln();

    _copyWith(s, members);
  }

  void _copyWith(_Shape s, List<(String, String, _Field, bool)> members) {
    final name = s.name;
    final copyWith = s.copyWith!;
    String nullable(String type) =>
        type == 'dynamic' || type.endsWith('?') ? type : '$type?';

    _out
      ..writeln('/// `copyWith` of [$name]; pass `null` to clear a nullable '
          'field.')
      ..writeln('abstract class $copyWith {')
      ..writeln('  $name call({');
    for (final (dart, type, _, _) in members) {
      _out.writeln('    ${nullable(type)} $dart,');
    }
    _out
      ..writeln('  });')
      ..writeln('}')
      ..writeln()
      ..writeln('class _$copyWith implements $copyWith {')
      ..writeln('  const _$copyWith(this._value);')
      ..writeln()
      ..writeln('  final $name _value;')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  $name call({');
    for (final (dart, _, _, _) in members) {
      _out.writeln('    Object? $dart = _undefined,');
    }
    _out.writeln('  }) =>');
    _out.writeln('      $name(');
    for (final (dart, type, _, _) in members) {
      final cast = type == 'dynamic' ? dart : '$dart as $type';
      _out.writeln('        $dart: identical($dart, _undefined) '
          '? _value.$dart : $cast,');
    }
    _out
      ..writeln('      );')
      ..writeln('}')
      ..writeln();
  }
}
