/// Type generation utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'code_utils.dart';
import 'config_context.dart';
import 'diagnostics.dart';
import 'document_utils.dart';
import 'json_exprs.dart';
import 'naming.dart';
import 'schema_analyzer.dart';

/// A field of a generated JSON class.
typedef _Field = ({
  String name,
  TypeNode type,
  StringValueNode? description,
  List<DirectiveNode> directives,
});

_Field _fieldOf(FieldDefinitionNode f) => (
      name: f.name.value,
      type: f.type,
      description: f.description,
      directives: f.directives,
    );

_Field _inputFieldOf(InputValueDefinitionNode f) => (
      name: f.name.value,
      type: f.type,
      description: f.description,
      directives: f.directives,
    );

/// Utility class for generating types, enums, and converters
class TypeGenerator {
  /// Generates a complete types file with all necessary components
  static String generateTypesFile(String schema) {
    final schemaDoc =
        DocumentUtils.mergeSchemaExtensions(gql_lang.parseString(schema));
    _checkStructure(schemaDoc);
    SchemaAnalyzer.extractCustomTypesAndEnums(schemaDoc);
    _checkStrictScalars();
    _nullableConverters.clear();
    _usesEnumRaw = false;
    final needsConvert = _wrappedScalars(TypeRegistry.customScalars).isNotEmpty;
    final scalarConverters =
        _generateScalarConverters(TypeRegistry.customScalars);
    final enumDefinitions = _generateEnumDefinitions(schemaDoc);
    final enumConverters = _generateEnumConverters(schemaDoc);
    final typeDefinitions = _generateAllTypeDefinitions(schemaDoc, schema);
    // json_serializable writes types.g.dart only for annotated classes.
    final part = typeDefinitions.contains('@JsonSerializable')
        ? "part 'types.g.dart';"
        : '';

    return '''${CodeGenerationConstants.generatedFileWarning}
${CodeGenerationConstants.ignoreForFile}, unused_element, unused_import, deprecated_member_use_from_same_package

${needsConvert ? "import 'dart:convert';\n\n" : ''}import 'package:json_annotation/json_annotation.dart';
${scalarImportDirectives()}
$part

class Decimal {
  final String value;
  Decimal(this.value);

  @override
  String toString() => value;

  static Decimal parse(String value) => Decimal(value);

  @override
  bool operator ==(Object other) => other is Decimal && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class Long {
  final String value;
  Long(this.value);

  @override
  String toString() => value;

  static Long parse(String value) => Long(value);

  @override
  bool operator ==(Object other) => other is Long && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class DecimalConverter implements JsonConverter<Decimal, dynamic> {
  const DecimalConverter();

  @override
  Decimal fromJson(dynamic json) {
    if (json == null) return Decimal('0');
    if (json is String) return Decimal(json);
    if (json is int) return Decimal(json.toString());
    if (json is double) return Decimal(json.toString());
    return Decimal(json.toString());
  }

  @override
  dynamic toJson(Decimal object) => object.toString();
}

class DateTimeConverter implements JsonConverter<DateTime, dynamic> {
  const DateTimeConverter();

  @override
  DateTime fromJson(dynamic json) {
    if (json == null) return DateTime.now();
    if (json is String) return DateTime.parse(json);
    return DateTime.now();
  }

  @override
  dynamic toJson(DateTime object) {
    // Always convert to UTC to ensure GraphQL-compatible format with timezone
    // GraphQL DateTime scalar requires full ISO-8601 format with timezone
    return object.toUtc().toIso8601String();
  }
}

class LocalDateConverter implements JsonConverter<DateTime, dynamic> {
  const LocalDateConverter();

  @override
  DateTime fromJson(dynamic json) {
    if (json == null) return DateTime.now();
    if (json is String) return DateTime.parse(json);
    return DateTime.now();
  }

  @override
  dynamic toJson(DateTime object) => object.toIso8601String().split('T').first;
}

class LongConverter implements JsonConverter<Long, dynamic> {
  const LongConverter();

  @override
  Long fromJson(dynamic json) {
    if (json == null) return Long('0');
    if (json is String) return Long(json);
    if (json is int) return Long(json.toString());
    if (json is double) return Long(json.toInt().toString());
    return Long(json.toString());
  }

  @override
  dynamic toJson(Long object) => object.toString();
}

class Byte {
  final int value;
  Byte(this.value);

  @override
  String toString() => value.toString();

  static Byte parse(dynamic value) {
    if (value is int) return Byte(value);
    if (value is String) return Byte(int.tryParse(value) ?? 0);
    if (value is double) return Byte(value.toInt());
    return Byte(0);
  }

  @override
  bool operator ==(Object other) => other is Byte && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class ByteConverter implements JsonConverter<Byte, dynamic> {
  const ByteConverter();

  @override
  Byte fromJson(dynamic json) {
    if (json == null) return Byte(0);
    if (json is int) return Byte(json);
    if (json is String) return Byte(int.tryParse(json) ?? 0);
    if (json is double) return Byte(json.toInt());
    return Byte(0);
  }

  @override
  dynamic toJson(Byte object) => object.value;
}

class SafeStringConverter implements JsonConverter<String, dynamic> {
  const SafeStringConverter();

  @override
  String fromJson(dynamic json) {
    if (json == null) return '';
    return json.toString();
  }

  @override
  dynamic toJson(String object) => object;
}

// Safe converters that handle null values correctly
class SafeBoolConverter implements JsonConverter<bool, dynamic> {
  const SafeBoolConverter();

  @override
  bool fromJson(dynamic json) {
    if (json == null) return false;
    if (json is bool) return json;
    if (json is String) {
      final lower = json.toLowerCase();
      return lower == 'true' || lower == '1';
    }
    if (json is num) return json != 0;
    return false;
  }

  @override
  dynamic toJson(bool object) => object;
}

class SafeIntConverter implements JsonConverter<int, dynamic> {
  const SafeIntConverter();

  @override
  int fromJson(dynamic json) {
    if (json == null) return 0;
    if (json is int) return json;
    if (json is double) return json.toInt();
    if (json is String) {
      return int.tryParse(json) ?? 0;
    }
    return 0;
  }

  @override
  dynamic toJson(int object) => object;
}

class SafeDoubleConverter implements JsonConverter<double, dynamic> {
  const SafeDoubleConverter();

  @override
  double fromJson(dynamic json) {
    if (json == null) return 0.0;
    if (json is double) return json;
    if (json is int) return json.toDouble();
    if (json is String) {
      return double.tryParse(json) ?? 0.0;
    }
    return 0.0;
  }

  @override
  dynamic toJson(double object) => object;
}

class SafeDecimalConverter implements JsonConverter<Decimal, dynamic> {
  const SafeDecimalConverter();

  @override
  Decimal fromJson(dynamic json) {
    if (json == null) return Decimal('0');
    if (json is String) return Decimal(json);
    if (json is int) return Decimal(json.toString());
    if (json is double) return Decimal(json.toString());
    return Decimal(json.toString());
  }

  @override
  dynamic toJson(Decimal object) => object.toString();
}

class EnumConverter<T> implements JsonConverter<T, String> {
  const EnumConverter(this.valueMap);

  final Map<String, T> valueMap;

  @override
  T fromJson(String json) => valueMap[json]!;

  @override
  String toJson(T object) => object.toString().split('.').last;
}

/// Deep equality for generated classes: lists and maps are compared by their
/// elements.
bool graphqlDeepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!graphqlDeepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !graphqlDeepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

/// Hash code matching [graphqlDeepEquals].
int graphqlDeepHash(Object? value) {
  if (value is List) return Object.hashAll(value.map(graphqlDeepHash));
  if (value is Map) {
    return Object.hashAllUnordered(value.entries
        .map((e) => Object.hash(graphqlDeepHash(e.key), graphqlDeepHash(e.value))));
  }
  return value.hashCode;
}

$scalarConverters

$enumDefinitions

$enumConverters

$typeDefinitions

${_generatePossibleTypes()}

${_generateNullableConverters()}${_usesEnumRaw ? _enumRawHelper : ''}''';
  }

  /// `import` lines for the libraries of mapped scalar types.
  static String scalarImportDirectives() {
    final uris = CodegenConfigContext.scalarImports.values.toSet().toList()
      ..sort();
    return uris.map((uri) => "import '$uri';\n").join();
  }

  /// With `strict_scalars`, custom scalars must have a `scalar_mapping`.
  /// Rejects schemas the spec doesn't allow and the generator can't turn into
  /// valid Dart: empty types and an interface implemented twice. Runs after
  /// `extend` definitions are merged, so fields they add count.
  static void _checkStructure(DocumentNode schemaDoc) {
    final problems = <String>[];
    void interfaces(String name, List<NamedTypeNode> list) {
      final seen = <String>{};
      for (final i in list) {
        if (!seen.add(i.name.value)) {
          problems.add('$name: implements ${i.name.value} more than once');
        }
      }
    }

    for (final d in schemaDoc.definitions) {
      switch (d) {
        case ObjectTypeDefinitionNode(:final name, :final fields):
          if (fields.isEmpty) {
            problems
                .add('${name.value}: an object type needs at least one field');
          }
          interfaces(name.value, d.interfaces);
        case InterfaceTypeDefinitionNode(:final name, :final fields):
          if (fields.isEmpty) {
            problems
                .add('${name.value}: an interface needs at least one field');
          }
          interfaces(name.value, d.interfaces);
        case InputObjectTypeDefinitionNode(:final name, :final fields):
          if (fields.isEmpty) {
            problems
                .add('${name.value}: an input type needs at least one field');
          }
        case UnionTypeDefinitionNode(:final name, :final types):
          if (types.isEmpty) {
            problems.add('${name.value}: a union needs at least one member');
          }
        case EnumTypeDefinitionNode(:final name, :final values):
          if (values.isEmpty) {
            problems.add('${name.value}: an enum needs at least one value');
          }
        default:
      }
    }
    if (problems.isEmpty) return;
    throw CodegenException(
      CodegenErrorCodes.schemaInvalidStructure,
      'The schema has types the GraphQL spec does not allow:\n'
      '${problems.map((p) => '  - $p').join('\n')}',
    );
  }

  static void _checkStrictScalars() {
    if (!CodegenConfigContext.strictScalars) return;
    final unmapped = TypeRegistry.customScalars
        .where(TypeRegistry.isWrappedScalar)
        .toList()
      ..sort();
    if (unmapped.isEmpty) return;
    throw CodegenException(
      CodegenErrorCodes.schemaUnmappedScalar,
      'Custom scalars without a scalar_mapping entry (strict_scalars is on): '
      '${unmapped.join(', ')}',
    );
  }

  /// The concrete object types of every interface and union, in the shape
  /// `GraphQLCache(possibleTypes: ...)` expects for matching fragments.
  static String _generatePossibleTypes() {
    final abstractTypes = {
      ...TypeRegistry.interfaceTypes,
      ...TypeRegistry.unionTypes,
    }.toList()
      ..sort();
    final buffer = StringBuffer()
      ..writeln('/// Concrete types of every interface and union, for '
          '`GraphQLCache(possibleTypes: possibleTypes)`.');
    if (abstractTypes.isEmpty) {
      buffer.write('const Map<String, Set<String>> possibleTypes = {};');
      return buffer.toString();
    }
    buffer.writeln('const Map<String, Set<String>> possibleTypes = {');
    for (final name in abstractTypes) {
      final members = TypeRegistry.possibleTypes(name).map((t) => "'$t'");
      buffer.writeln(members.isEmpty
          ? "  '$name': <String>{},"
          : "  '$name': {${members.join(', ')}},");
    }
    buffer.write('};');
    return buffer.toString();
  }

  /// Custom scalars that get the generic generated wrapper class + converter.
  static Iterable<String> _wrappedScalars(Set<String> customScalars) =>
      customScalars.where(TypeRegistry.isWrappedScalar);

  /// Generates scalar converters for custom scalar types
  static String _generateScalarConverters(Set<String> customScalars) {
    final buffer = StringBuffer();

    for (final scalar in _wrappedScalars(customScalars)) {
      final name = SchemaAnalyzer.dartTypeName(scalar);
      buffer.writeln('''
/// Wrapper for the custom GraphQL scalar `$scalar`.
///
/// [raw] holds the JSON value exactly as received (string, number, map, ...).
class $name {
  final Object? raw;
  const $name(this.raw);

  /// String form of the value; non-string JSON values are JSON-encoded.
  String get value => raw is String ? raw as String : jsonEncode(raw);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is $name && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class ${name}Converter implements JsonConverter<$name, dynamic> {
  const ${name}Converter();

  @override
  $name fromJson(dynamic json) => $name(json);

  @override
  dynamic toJson($name object) => object.raw;
}
''');
    }
    return buffer.toString();
  }

  /// Generates enum definitions from schema
  static String _generateEnumDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in _sortedDefinitions(schemaDoc)) {
      if (definition is EnumTypeDefinitionNode) {
        final enumName = SchemaAnalyzer.dartTypeName(definition.name.value);
        buffer.write(_docComment(definition.description));
        buffer.writeln('enum $enumName {');
        // Sort enum values for determinism
        for (final value in _sortedEnumValues(definition)) {
          final graphqlName = value.name.value;
          final dartName = dartEnumValueName(graphqlName);
          buffer.write(_docComment(value.description,
              directives: value.directives, indent: '  '));
          buffer.write(_deprecation(value.directives, indent: '  '));
          // json_serializable decodes enum lists without our converter; the
          // JsonValue keeps escaped values mapped to their GraphQL names.
          if (dartName != graphqlName) {
            buffer.writeln("  @JsonValue('$graphqlName')");
          }
          buffer.writeln('  $dartName,');
        }
        if (CodegenConfigContext.unknownEnumFallback) {
          buffer.writeln('  /// A value added to the schema after this code '
              'was generated.');
          buffer.writeln('  \$unknown,');
        }
        buffer.writeln('}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Generates enum converters from schema
  static String _generateEnumConverters(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    for (final definition in _sortedDefinitions(schemaDoc)) {
      if (definition is EnumTypeDefinitionNode) {
        final enumName = SchemaAnalyzer.dartTypeName(definition.name.value);
        final values = _sortedEnumValues(definition);
        buffer.writeln(
            'class ${enumName}Converter extends JsonConverter<$enumName, String> {');
        buffer.writeln('  const ${enumName}Converter();');
        buffer.writeln();
        buffer.writeln('  @override');
        buffer.writeln('  $enumName fromJson(String json) {');
        buffer.writeln('    switch (json) {');
        for (final value in values) {
          buffer.writeln(
              "      case '${value.name.value}': return $enumName.${dartEnumValueName(value.name.value)};");
        }
        final fallback = CodegenConfigContext.unknownEnumFallback;
        buffer.writeln(fallback
            ? '      default: return $enumName.\$unknown;'
            : "      default: throw ArgumentError.value(json, 'json', 'Unknown $enumName value');");
        buffer.writeln('    }');
        buffer.writeln('  }');
        buffer.writeln();
        buffer.writeln('  @override');
        final needsMapping =
            values.any((v) => dartEnumValueName(v.name.value) != v.name.value);
        if (needsMapping || fallback) {
          buffer.writeln('  String toJson($enumName object) {');
          buffer.writeln('    switch (object) {');
          for (final value in values) {
            buffer.writeln(
                "      case $enumName.${dartEnumValueName(value.name.value)}: return '${value.name.value}';");
          }
          if (fallback) {
            buffer
                .writeln('      case $enumName.\$unknown: throw ArgumentError('
                    "'$enumName.\\\$unknown cannot be sent to the server');");
          }
          buffer.writeln('    }');
          buffer.writeln('  }');
        } else {
          buffer.writeln(
              '  String toJson($enumName object) => object.toString().split(".").last;');
        }
        buffer.writeln('}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  static List<DefinitionNode> _sortedDefinitions(DocumentNode schemaDoc) {
    final defs = List<DefinitionNode>.from(schemaDoc.definitions);
    defs.sort((a, b) {
      final an = (a is TypeDefinitionNode) ? a.name.value : '';
      final bn = (b is TypeDefinitionNode) ? b.name.value : '';
      return an.compareTo(bn);
    });
    return defs;
  }

  static List<EnumValueDefinitionNode> _sortedEnumValues(
      EnumTypeDefinitionNode definition) {
    return [...definition.values]
      ..sort((a, b) => a.name.value.compareTo(b.name.value));
  }

  /// Generates all type definitions from schema
  static String _generateAllTypeDefinitions(
      DocumentNode schemaDoc, String schema) {
    final buffer = StringBuffer();

    final interfaces = <String, InterfaceTypeDefinitionNode>{
      for (final def
          in schemaDoc.definitions.whereType<InterfaceTypeDefinitionNode>())
        def.name.value: def,
    };

    // With operation result types, results are parsed into per-operation
    // classes; only inputs are needed here, without json_serializable.
    if (CodegenConfigContext.operationResultTypes) {
      final inputs = _sortedDefinitions(schemaDoc)
          .whereType<InputObjectTypeDefinitionNode>()
          .toList();
      for (final definition in inputs) {
        buffer.writeln(_generateInputClass(definition));
      }
      if (buffer.toString().contains('_undefined')) {
        buffer.writeln('const _undefined = Object();');
      }
      return buffer.toString();
    }

    for (final definition in _sortedDefinitions(schemaDoc)) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(_generateTypeDefinition(definition, schema, interfaces));
      } else if (definition is InputObjectTypeDefinitionNode) {
        buffer.writeln(_generateInputTypeDefinition(definition, schema));
      } else if (definition is InterfaceTypeDefinitionNode) {
        buffer.writeln(_generateInterfaceDefinition(definition, interfaces));
      } else if (definition is UnionTypeDefinitionNode) {
        buffer.writeln(_generateUnionDefinition(definition));
      }
    }

    return buffer.toString();
  }

  /// Names of all fields declared by [typeName]'s interfaces (transitively).
  static Set<String> _inheritedFieldNames(
    String typeName,
    Map<String, InterfaceTypeDefinitionNode> interfaces, [
    Set<String>? visited,
  ]) {
    visited ??= <String>{};
    final names = <String>{};
    for (final superName in TypeRegistry.supertypes(typeName)) {
      final iface = interfaces[superName];
      if (iface == null || !visited.add(superName)) continue;
      names.addAll(iface.fields.map((f) => f.name.value));
      names.addAll(_inheritedFieldNames(superName, interfaces, visited));
    }
    return names;
  }

  /// Generates a type definition for a specific object type
  static String _generateTypeDefinition(ObjectTypeDefinitionNode typeNode,
      [String schema = '',
      Map<String, InterfaceTypeDefinitionNode> interfaces = const {}]) {
    final typeName = typeNode.name.value;
    return _generateJsonClass(
      className: SchemaAnalyzer.dartTypeName(typeName),
      description: typeNode.description,
      fields: typeNode.fields.map(_fieldOf).toList(),
      supertypes: _dartSupertypes(typeName),
      overriddenFields: _inheritedFieldNames(typeName, interfaces),
      rawEnumFields: true,
    );
  }

  /// Generates a type definition for a specific input type
  static String _generateInputTypeDefinition(
      InputObjectTypeDefinitionNode inputNode,
      [String schema = '']) {
    return _generateJsonClass(
      className: SchemaAnalyzer.dartTypeName(inputNode.name.value),
      description: inputNode.description,
      fields: inputNode.fields.map(_inputFieldOf).toList(),
      // With include_null_inputs a null field is sent as null, so the server
      // can tell "clear it" from "leave it".
      includeIfNull: CodegenConfigContext.includeNullInputs,
    );
  }

  /// Generates a hand-written input class (operation result types): `const`
  /// constructor, `final` fields, fromJson/toJson, value equality and a typed
  /// copyWith. Field names, Dart types and constructor defaults match the
  /// json_serializable classes of schema result types.
  static String _generateInputClass(InputObjectTypeDefinitionNode node) {
    final className = SchemaAnalyzer.dartTypeName(node.name.value);
    final fields = [
      for (final f in [
        ...node.fields
      ]..sort((a, b) => a.name.value.compareTo(b.name.value)))
        (
          node: f,
          key: f.name.value,
          name: dartFieldName(f.name.value, className: className),
          type: SchemaAnalyzer.getDartType(f.type),
        ),
    ];
    final names = fields.map((f) => f.name).toSet();
    String unused(String name) {
      while (names.contains(name)) {
        name = '${name}_';
      }
      return name;
    }

    final other = unused('other');
    final value = unused('value');
    // A field named `copyWith` would clash with the getter, one named
    // `identical` would hide the function the copy relies on.
    final hidesIdentical = names.contains('identical');
    final withCopy = !names.contains('copyWith') && !hidesIdentical;
    final copyWith = '${className}_CopyWith';

    final buffer = StringBuffer();
    buffer.write(_docComment(node.description));
    buffer.writeln('class $className {');
    for (final f in fields) {
      buffer.write(_docComment(f.node.description,
          directives: f.node.directives, indent: '  '));
      buffer.write(_deprecation(f.node.directives, indent: '  '));
      buffer.writeln('  final ${f.type} ${f.name};');
    }
    buffer.writeln();
    buffer.writeln('  const $className({');
    for (final f in fields) {
      if (f.type.startsWith('List<')) {
        buffer.writeln('    this.${f.name} = const [],');
      } else if (f.type.endsWith('?') || f.type == 'dynamic') {
        buffer.writeln('    this.${f.name},');
      } else {
        buffer.writeln('    required this.${f.name},');
      }
    }
    buffer.writeln('  });');
    buffer.writeln();

    buffer
        .writeln('  factory $className.fromJson(Map<String, dynamic> json) =>');
    buffer.writeln('      $className(');
    for (final f in fields) {
      final v = "json['${f.key}']";
      final type = f.node.type;
      // Like json_serializable's `defaultValue`, a missing list is empty.
      final expr = type is ListTypeNode
          ? '$v == null ? const <${_listElementType(f.type)}>[] : '
              '${_inputFromJson(type, v, nullable: false)}'
          : _inputFromJson(type, v, parenthesize: false);
      buffer.writeln('        ${f.name}: $expr,');
    }
    buffer.writeln('      );');
    buffer.writeln();

    // Null fields are left out unless include_null_inputs is on, so the
    // server can tell "clear it" from "leave it".
    final includeNull = CodegenConfigContext.includeNullInputs;
    buffer.writeln('  Map<String, dynamic> toJson() => {');
    for (final f in fields) {
      final type = f.node.type;
      if (!_inputNullable(type)) {
        buffer.writeln("        '${f.key}': ${_inputToJson(type, f.name)},");
        continue;
      }
      final conv = _inputToJson(type, value);
      if (includeNull) {
        buffer.writeln(conv == value
            ? "        '${f.key}': ${f.name},"
            : "        '${f.key}': switch (${f.name}) "
                '{ final $value? => $conv, null => null },');
      } else {
        buffer.writeln(
            "        if (${f.name} case final $value?) '${f.key}': $conv,");
      }
    }
    buffer.writeln('      };');
    buffer.writeln();

    if (withCopy) {
      buffer.writeln('  $copyWith get copyWith => _$copyWith(this);');
      buffer.writeln();
    }

    bool isList(String type) => type.startsWith('List<');
    buffer.writeln('  @override');
    buffer.writeln('  bool operator ==(Object $other) =>');
    if (!hidesIdentical) buffer.writeln('      identical(this, $other) ||');
    buffer.write('      $other is $className');
    for (final f in fields) {
      buffer.write(isList(f.type)
          ? ' &&\n          graphqlDeepEquals(${f.name}, $other.${f.name})'
          : ' &&\n          ${f.name} == $other.${f.name}');
    }
    buffer.writeln(';');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  int get hashCode => Object.hashAll([');
    for (final f in fields) {
      buffer.writeln(isList(f.type)
          ? '        graphqlDeepHash(${f.name}),'
          : '        ${f.name},');
    }
    buffer.writeln('      ]);');
    buffer.writeln('}');
    buffer.writeln();

    if (withCopy) {
      String param(String type) => JsonExprs.withNullability(
          type.endsWith('?') ? type.substring(0, type.length - 1) : type, true);
      buffer.writeln('/// Copies a [$className], changing the given fields '
          '(`null` included).');
      buffer.writeln('abstract class $copyWith {');
      buffer.writeln('  $className call({');
      for (final f in fields) {
        buffer.writeln('    ${param(f.type)} ${f.name},');
      }
      buffer.writeln('  });');
      buffer.writeln('}');
      buffer.writeln();
      buffer.writeln('class _$copyWith implements $copyWith {');
      buffer.writeln('  const _$copyWith(this._value);');
      buffer.writeln();
      buffer.writeln('  final $className _value;');
      buffer.writeln();
      buffer.writeln('  @override');
      buffer.writeln('  $className call({');
      for (final f in fields) {
        buffer.writeln('    Object? ${f.name} = _undefined,');
      }
      buffer.writeln('  }) =>');
      buffer.writeln('      $className(');
      for (final f in fields) {
        final cast = f.type == 'dynamic' ? '' : ' as ${f.type}';
        buffer.writeln('        ${f.name}: identical(${f.name}, _undefined) '
            '? _value.${f.name} : ${f.name}$cast,');
      }
      buffer.writeln('      );');
      buffer.writeln('}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Whether the Dart type of input [type] is nullable; in legacy mode lists
  /// always are (see [SchemaAnalyzer.getDartType]).
  static bool _inputNullable(TypeNode type) =>
      !type.isNonNull ||
      (type is ListTypeNode && !CodegenConfigContext.strictNullability);

  /// `T` of a Dart `List<T>` / `List<T>?` type.
  static String _listElementType(String listType) =>
      listType.substring(5, listType.length - (listType.endsWith('?') ? 2 : 1));

  /// Expression converting the JSON value [v] into the Dart value of input
  /// [type]; [nullable] defaults to the nullability of the Dart type.
  static String _inputFromJson(TypeNode type, String v,
      {bool? nullable, bool parenthesize = true}) {
    final String inner;
    if (type is ListTypeNode) {
      final item = _inputFromJson(type.type, 'e');
      inner = '($v as List<dynamic>).map((e) => $item).toList()';
    } else {
      inner = JsonExprs.namedFromJson(
          (type as NamedTypeNode).name.value, v, TypeRegistry.inputTypes);
    }
    if (!(nullable ?? _inputNullable(type))) return inner;
    final check = '$v == null ? null : $inner';
    return parenthesize ? '($check)' : check;
  }

  /// Expression serialising the non-null value [v] of input [type].
  static String _inputToJson(TypeNode type, String v) {
    if (type is! ListTypeNode) return JsonExprs.toJsonExpr(type, v);
    final item = _inputToJson(type.type, 'e');
    if (item == 'e') return v;
    final itemExpr =
        _inputNullable(type.type) ? '(e == null ? null : $item)' : item;
    return '$v.map((e) => $itemExpr).toList()';
  }

  /// Generates an abstract class for a GraphQL interface plus an `Unknown*`
  /// fallback implementation used for unrecognised `__typename` values.
  static String _generateInterfaceDefinition(
    InterfaceTypeDefinitionNode node,
    Map<String, InterfaceTypeDefinitionNode> interfaces,
  ) {
    final graphqlName = node.name.value;
    final name = SchemaAnalyzer.dartTypeName(graphqlName);
    final supertypes = _dartSupertypes(graphqlName);
    final inherited = _inheritedFieldNames(graphqlName, interfaces);
    final unknownName = 'Unknown$graphqlName';
    final sortedFields = [...node.fields]
      ..sort((a, b) => a.name.value.compareTo(b.name.value));

    final buffer = StringBuffer();
    buffer.write(_docComment(node.description,
        fallback: 'GraphQL interface `$graphqlName`.'));
    final impl =
        supertypes.isEmpty ? '' : ' implements ${supertypes.join(', ')}';
    buffer.writeln('abstract class $name$impl {');
    for (final field in sortedFields) {
      final fieldName = field.name.value;
      buffer.write(_docComment(field.description,
          directives: field.directives, indent: '  '));
      if (inherited.contains(fieldName)) buffer.writeln('  @override');
      buffer.write(_deprecation(field.directives, indent: '  '));
      buffer.writeln(
          '  ${SchemaAnalyzer.getDartType(field.type)} get ${dartFieldName(fieldName, className: name)};');
    }
    buffer.writeln();
    buffer.writeln(
        '  /// Creates the concrete implementation matching `__typename`.');
    buffer.writeln('  factory $name.fromJson(Map<String, dynamic> json) {');
    buffer.write(_typenameDispatch(graphqlName, '$unknownName.fromJson(json)'));
    buffer.writeln('  }');
    buffer.writeln();
    if (supertypes.isNotEmpty) buffer.writeln('  @override');
    buffer.writeln('  Map<String, dynamic> toJson();');
    buffer.writeln('}');
    buffer.writeln();

    buffer.writeln(
        '/// Fallback for `$graphqlName` implementations unknown at generation '
        'time.');
    buffer.write(_generateJsonClass(
      className: unknownName,
      fields: node.fields.map(_fieldOf).toList(),
      supertypes: [name],
      overriddenFields: node.fields.map((f) => f.name.value).toSet(),
      fieldNameClassName: name,
    ));
    return buffer.toString();
  }

  /// Generates an abstract class for a GraphQL union plus an `Unknown*`
  /// fallback that keeps the raw JSON.
  static String _generateUnionDefinition(UnionTypeDefinitionNode node) {
    final graphqlName = node.name.value;
    final name = SchemaAnalyzer.dartTypeName(graphqlName);
    final unknownName = 'Unknown$graphqlName';
    return '''
${_docComment(node.description, fallback: 'GraphQL union `$graphqlName`.')}abstract class $name {
  /// Creates the concrete member type matching `__typename`.
  factory $name.fromJson(Map<String, dynamic> json) {
${_typenameDispatch(graphqlName, '$unknownName(json)')}  }

  Map<String, dynamic> toJson();
}

/// Fallback for `$graphqlName` members unknown at generation time.
class $unknownName implements $name {
  const $unknownName(this.json);

  final Map<String, dynamic> json;

  String? get typename => json['__typename'] as String?;

  @override
  Map<String, dynamic> toJson() => json;
}

''';
  }

  /// Dart names of the interfaces and unions [typeName] implements.
  static List<String> _dartSupertypes(String typeName) =>
      TypeRegistry.supertypes(typeName)
          .map(SchemaAnalyzer.dartTypeName)
          .toList();

  static String _typenameDispatch(String abstractType, String fallback) {
    final buffer = StringBuffer();
    buffer.writeln("    switch (json['__typename']) {");
    for (final concrete in TypeRegistry.possibleTypes(abstractType)) {
      buffer.writeln("      case '$concrete':");
      buffer.writeln(
          '        return ${SchemaAnalyzer.dartTypeName(concrete)}.fromJson(json);');
    }
    buffer.writeln('      default:');
    buffer.writeln('        return $fallback;');
    buffer.writeln('    }');
    return buffer.toString();
  }

  /// Generates a json_serializable class with the given fields.
  ///
  /// [fieldNameClassName] is the class name used to detect member/class name
  /// clashes; it defaults to [className] (but `Unknown*` classes must use the
  /// interface name so field names match the interface getters).
  static String _generateJsonClass({
    required String className,
    required List<_Field> fields,
    StringValueNode? description,
    List<String> supertypes = const [],
    Set<String> overriddenFields = const {},
    String? fieldNameClassName,
    bool includeIfNull = false,
    bool rawEnumFields = false,
  }) {
    final buffer = StringBuffer();
    buffer.write(_docComment(description));
    buffer.writeln(
        '@JsonSerializable(includeIfNull: $includeIfNull, explicitToJson: true, fieldRename: FieldRename.none)');
    final impl =
        supertypes.isEmpty ? '' : ' implements ${supertypes.join(', ')}';
    buffer.writeln('class $className$impl {');

    // Sort fields deterministically by name
    final sortedFields = [...fields]..sort((a, b) => a.name.compareTo(b.name));

    for (final field in sortedFields) {
      final fieldName = field.name;
      final type = field.type;
      final dartName =
          dartFieldName(fieldName, className: fieldNameClassName ?? className);
      buffer.write(_docComment(field.description,
          directives: field.directives, indent: '  '));
      if (overriddenFields.contains(fieldName)) buffer.writeln('  @override');
      buffer.write(_deprecation(field.directives, indent: '  '));
      for (final line in _fieldAnnotations(fieldName, dartName, type)) {
        buffer.writeln(line);
      }
      buffer.writeln('  ${SchemaAnalyzer.getDartType(type)} $dartName;');
      if (rawEnumFields) {
        buffer.write(_rawEnumField(field, fields,
            className: fieldNameClassName ?? className));
      }
    }

    buffer.writeln();
    buffer.writeln('  $className({');
    for (final field in sortedFields) {
      final dartName =
          dartFieldName(field.name, className: fieldNameClassName ?? className);
      final fieldType = SchemaAnalyzer.getDartType(field.type);
      if (fieldType.startsWith('List<')) {
        // For list fields, provide empty list as default
        buffer.writeln('    this.$dartName = const [],');
      } else if (fieldType.endsWith('?')) {
        buffer.writeln('    this.$dartName,');
      } else {
        buffer.writeln('    required this.$dartName,');
      }
    }
    buffer.writeln('  });');

    buffer.writeln();
    buffer.writeln(
        '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);');
    if (supertypes.isNotEmpty) buffer.writeln('  @override');
    buffer.writeln(
        '  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');

    buffer.writeln('}');
    buffer.writeln();

    return buffer.toString();
  }

  /// Whether the current types file uses [_enumRawHelper].
  static bool _usesEnumRaw = false;

  /// With `unknown_enum_fallback`, an enum field (or a list of enums) gets a
  /// sibling `<name>Raw` with the string the server sent, so a value that
  /// parsed to `$unknown` can still be shown or logged. It is read from the
  /// field's JSON key and never written back.
  static String _rawEnumField(_Field field, List<_Field> fields,
      {required String className}) {
    if (!CodegenConfigContext.unknownEnumFallback) return '';
    final graphqlBase = getOriginalGraphQLType(field.type);
    if (!TypeRegistry.isEnum(graphqlBase)) return '';
    var type = field.type;
    if (type is ListTypeNode) {
      type = type.type;
      // Only plain lists; nested lists keep just the parsed values.
      if (type is ListTypeNode) return '';
    }
    final rawName = '${field.name}Raw';
    if (fields.any((f) => f.name == rawName)) return '';
    _usesEnumRaw = true;
    final dartType = field.type is ListTypeNode ? 'List<String?>?' : 'String?';
    return """
  /// [${dartFieldName(field.name, className: className)}] as the server sent it, also when it is `\$unknown`.
  @JsonKey(name: '${field.name}#raw', readValue: _enumRaw, includeToJson: false)
  $dartType ${dartFieldName(rawName, className: className)};
""";
  }

  static const _enumRawHelper = """
/// Reads the JSON value of an enum field for its `<name>Raw` sibling (the
/// sibling's key is the field's key plus `#raw`).
Object? _enumRaw(Map<dynamic, dynamic> json, String key) =>
    json[key.substring(0, key.length - 4)];
""";

  /// `///` lines for a schema [description] (or [fallback] when there is
  /// none), each ending with a newline; empty when there is nothing to write.
  ///
  /// Without `deprecated_annotations`, a `@deprecated` directive among
  /// [directives] is mentioned here instead of becoming `@Deprecated`.
  static String _docComment(StringValueNode? description,
      {List<DirectiveNode> directives = const [],
      String indent = '',
      String? fallback}) {
    var text = description?.value.trim() ?? '';
    if (text.isEmpty) text = fallback ?? '';
    final reason = _deprecationReason(directives);
    if (reason != null && !CodegenConfigContext.deprecatedAnnotations) {
      text =
          text.isEmpty ? 'Deprecated: $reason' : '$text\n\nDeprecated: $reason';
    }
    if (text.isEmpty) return '';
    return [
      for (final line in text.split('\n'))
        line.trimRight().isEmpty
            ? '$indent///\n'
            : '$indent/// ${line.trimRight()}\n'
    ].join();
  }

  /// A `@Deprecated(...)` line for a GraphQL `@deprecated` directive when
  /// `deprecated_annotations` is on, otherwise ''.
  static String _deprecation(List<DirectiveNode> directives,
      {String indent = ''}) {
    final reason = _deprecationReason(directives);
    if (reason == null || !CodegenConfigContext.deprecatedAnnotations) {
      return '';
    }
    final escaped = reason
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\n', r'\n');
    return "$indent@Deprecated('$escaped')\n";
  }

  /// The reason of a `@deprecated` directive, or null when there is none.
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

  /// Annotation lines (indented) for a generated field.
  static List<String> _fieldAnnotations(
      String fieldName, String dartName, TypeNode type) {
    final fieldType = SchemaAnalyzer.getDartType(type);
    final baseType = fieldType
        .replaceAll('?', '')
        .replaceAll('List<', '')
        .replaceAll('>', '');
    final isListField = fieldType.startsWith('List<');
    final isNullable = fieldType.endsWith('?');
    // Registry lookups use the GraphQL name; Dart names may be escaped.
    final graphqlBase = getOriginalGraphQLType(type);
    final mappedConverter =
        CodegenConfigContext.scalarMapping.containsKey(graphqlBase)
            ? CodegenConfigContext.scalarConverters[graphqlBase]
            : null;

    // Add @JsonKey annotation for field name preservation so json_serializable
    // never renames GraphQL fields (and escaped Dart names map back).
    final needsJsonKeyName =
        _needsJsonKeyForFieldName(fieldName) || dartName != fieldName;
    final nameArg = needsJsonKeyName ? "name: '$fieldName', " : '';
    final nameKey = "  @JsonKey(name: '$fieldName')";

    List<String> withName(String converter) =>
        [if (needsJsonKeyName) nameKey, converter];

    if (isListField) {
      // Check if the list contains custom types that need converters
      final innerType = fieldType.substring(
          5, fieldType.length - (fieldType.endsWith('>?') ? 2 : 1));
      final cleanInnerType = innerType.replaceAll('?', '');

      // json_serializable applies a field's converter to the elements of
      // (nested) lists. The built-in converters take `dynamic` and turn null
      // into a value, so nullable elements get a wrapper that keeps null.
      var elementConverter = mappedConverter;
      if (elementConverter == null) {
        final converter = _scalarConverter(graphqlBase, baseType);
        if (converter != null) {
          elementConverter = fieldType.contains('$baseType?')
              ? _nullableConverter(converter, baseType)
              : converter;
        }
      }
      if (elementConverter != null) {
        return [
          '  @JsonKey(${nameArg}defaultValue: const <$innerType>[])',
          '  @$elementConverter()',
        ];
      }
      // Regular lists (enums, objects, built-in scalars): default value only
      final unknownArg = CodegenConfigContext.unknownEnumFallback &&
              TypeRegistry.isEnum(graphqlBase)
          ? ', unknownEnumValue: $cleanInnerType.\$unknown'
          : '';
      return [
        '  @JsonKey(${nameArg}defaultValue: const <$cleanInnerType>[]$unknownArg)'
      ];
    }

    if (mappedConverter != null) return withName('  @$mappedConverter()');
    // As with list elements, a nullable field needs the wrapper to keep null
    // (the plain converter turns it into DateTime.now(), Custom(null), ...).
    final converter = _scalarConverter(graphqlBase, baseType);
    if (converter != null) {
      return withName(isNullable
          ? '  @${_nullableConverter(converter, baseType)}()'
          : '  @$converter()');
    }
    if (baseType == 'LocalDate') return withName('  @LocalDateConverter()');
    if (TypeRegistry.isEnum(graphqlBase)) {
      return withName('  @${baseType}Converter()');
    }
    // Safe converters for non-nullable primitives
    if (baseType == 'bool' && !isNullable) {
      return withName('  @SafeBoolConverter()');
    }
    if (baseType == 'int' && !isNullable) {
      return withName('  @SafeIntConverter()');
    }
    if (baseType == 'double' && !isNullable) {
      return withName('  @SafeDoubleConverter()');
    }
    return [if (needsJsonKeyName) nameKey];
  }

  /// Converter for a [baseType] value or list element, or null when
  /// json_serializable handles it itself.
  static String? _scalarConverter(String graphqlBase, String baseType) {
    if (TypeRegistry.isWrappedScalar(graphqlBase)) {
      return '${baseType}Converter';
    }
    return switch (baseType) {
      'DateTime' when graphqlBase == 'LocalDate' => 'LocalDateConverter',
      'DateTime' => 'DateTimeConverter',
      'Decimal' => 'SafeDecimalConverter',
      'Long' => 'LongConverter',
      'Byte' => 'ByteConverter',
      _ => null,
    };
  }

  /// Nullable wrappers used by the current types file: class name -> (inner
  /// converter, Dart type).
  static final Map<String, (String, String)> _nullableConverters = {};

  static String _nullableConverter(String converter, String dartType) {
    final name = '_Nullable$converter';
    _nullableConverters[name] = (converter, dartType);
    return name;
  }

  static String _generateNullableConverters() {
    final buffer = StringBuffer();
    final names = _nullableConverters.keys.toList()..sort();
    for (final name in names) {
      final (converter, type) = _nullableConverters[name]!;
      buffer.writeln('''
class $name implements JsonConverter<$type?, dynamic> {
  const $name();

  @override
  $type? fromJson(dynamic json) =>
      json == null ? null : const $converter().fromJson(json);

  @override
  dynamic toJson($type? object) =>
      object == null ? null : const $converter().toJson(object);
}
''');
    }
    return buffer.toString();
  }

  /// Determines if a field name needs explicit JsonKey annotation to preserve naming
  /// This prevents json_serializable from converting camelCase to snake_case
  static bool _needsJsonKeyForFieldName(String fieldName) {
    // Check if the field name contains uppercase letters (indicating camelCase)
    // We preserve all field names to maintain consistency with GraphQL responses
    return fieldName.contains(RegExp(r'[A-Z]')) || fieldName.length > 1;
  }

  /// Generates a class for an object type (legacy method, kept for compatibility)
  @Deprecated('Not used by the generator; will be removed in 3.0.')
  static String generateClassForType(ObjectTypeDefinitionNode type) {
    final className = type.name.value;
    final fields = type.fields;

    final classBuffer = StringBuffer();
    classBuffer.writeln('@JsonSerializable()');
    classBuffer.writeln('class $className {');

    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);
      final baseType = fieldType
          .replaceAll('?', '')
          .replaceAll('List<', '')
          .replaceAll('>', '');

      // Check if this is a list field
      final isListField = fieldType.startsWith('List<');

      if (isListField) {
        // Check if the list contains custom types that need converters
        final innerType = fieldType.substring(
            5, fieldType.length - (fieldType.endsWith('>?') ? 2 : 1));
        final cleanInnerType = innerType.replaceAll('?', '');

        // Add converter annotation for custom scalar types in lists
        if (TypeRegistry.isCustomScalar(cleanInnerType) &&
            cleanInnerType != 'Decimal' &&
            cleanInnerType != 'Short' &&
            cleanInnerType != 'Byte') {
          // For lists of custom scalars, use JsonKey with converter
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _${cleanInnerType.toLowerCase()}ListFromJson, toJson: _${cleanInnerType.toLowerCase()}ListToJson)');
        } else if (cleanInnerType == 'DateTime') {
          // Get original GraphQL type for list element to distinguish between DateTime and LocalDate
          final originalListType = getOriginalGraphQLType(field.type);
          if (originalListType == 'LocalDate') {
            classBuffer.writeln(
                '  @JsonKey(defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
          } else {
            classBuffer.writeln(
                '  @JsonKey(defaultValue: [], fromJson: _dateTimeListFromJson, toJson: _dateTimeListToJson)');
          }
        } else if (cleanInnerType == 'LocalDate') {
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _localDateListFromJson, toJson: _localDateListToJson)');
        } else if (cleanInnerType == 'Decimal') {
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _decimalListFromJson, toJson: _decimalListToJson)');
        } else if (cleanInnerType == 'Byte') {
          classBuffer.writeln(
              '  @JsonKey(defaultValue: [], fromJson: _byteListFromJson, toJson: _byteListToJson)');
        } else if (TypeRegistry.isEnum(cleanInnerType)) {
          classBuffer.writeln('  @JsonKey(defaultValue: [])');
        } else {
          // For regular lists (including object lists), just use default value
          classBuffer.writeln('  @JsonKey(defaultValue: [])');
        }
      } else if (baseType == 'DateTime') {
        // Get original GraphQL type to distinguish between DateTime and LocalDate
        final originalType = getOriginalGraphQLType(field.type);
        if (originalType == 'LocalDate') {
          classBuffer.writeln('  @LocalDateConverter()');
        } else {
          classBuffer.writeln('  @DateTimeConverter()');
        }
      } else if (baseType == 'Decimal') {
        classBuffer.writeln('  @SafeDecimalConverter()');
      } else if (baseType == 'Long') {
        classBuffer.writeln('  @LongConverter()');
      } else if (baseType == 'Byte') {
        classBuffer.writeln('  @ByteConverter()');
      } else if (TypeRegistry.isEnum(baseType)) {
        classBuffer.writeln('  @${baseType}Converter()');
      } else if (!GraphQLConstants.builtInScalars.contains(baseType) &&
          !GraphQLConstants.scalarToDartType.containsKey(baseType) &&
          TypeRegistry.isCustomScalar(baseType) &&
          baseType != 'Decimal' &&
          baseType != 'Long' &&
          baseType != 'Short' &&
          baseType != 'Byte') {
        classBuffer.writeln('  @${baseType}Converter()');
      }

      classBuffer.writeln('  final $fieldType ${fieldName.toCamelCase()};');
    }

    classBuffer.writeln();
    classBuffer.writeln('  $className({');
    for (final field in fields) {
      final fieldName = field.name.value;
      var fieldType = SchemaAnalyzer.getDartType(field.type);

      final isNullable = fieldType.endsWith('?');
      final isListField = fieldType.startsWith('List<');

      // Special handling for boolean fields that we made nullable for safety
      final isBooleanMadeNullable = fieldType == 'bool' && !isNullable;
      // Special handling for numeric fields that we made nullable for safety
      final isNumericMadeNullable =
          (fieldType == 'int' || fieldType == 'double') && !isNullable;

      // Lists are now always nullable, so they don't need 'required'
      // Other nullable fields also don't need 'required'
      if (isListField) {
        // For list fields, provide empty list as default
        classBuffer.writeln('    this.$fieldName = const [],');
      } else if (isBooleanMadeNullable) {
        // Boolean fields made nullable for safety don't need 'required'
        classBuffer.writeln('    this.$fieldName,');
      } else if (isNumericMadeNullable) {
        // Numeric fields made nullable for safety don't need 'required'
        classBuffer.writeln('    this.$fieldName,');
      } else if (isNullable) {
        classBuffer.writeln('    this.$fieldName,');
      } else {
        classBuffer.writeln('    required this.$fieldName,');
      }
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

  /// Generates type definitions for older API compatibility
  @Deprecated('Not used by the generator; will be removed in 3.0.')
  static String generateTypeDefinitions(DocumentNode schemaDoc) {
    final buffer = StringBuffer();

    // Sort deterministically
    final defs = List<DefinitionNode>.from(schemaDoc.definitions);
    defs.sort((a, b) {
      final an = (a is TypeDefinitionNode) ? a.name.value : '';
      final bn = (b is TypeDefinitionNode) ? b.name.value : '';
      return an.compareTo(bn);
    });

    for (final definition in defs) {
      if (definition is ObjectTypeDefinitionNode) {
        buffer.writeln(generateClassForType(definition));
      }
    }

    return buffer.toString();
  }

  // Method removed - was unused

  /// Gets the original GraphQL type name from a TypeNode without mapping
  static String getOriginalGraphQLType(TypeNode type) {
    if (type is NamedTypeNode) {
      return type.name.value;
    } else if (type is ListTypeNode) {
      return getOriginalGraphQLType(type.type);
    }
    return 'dynamic';
  }

  /// Gets the Dart type from a TypeNode but preserves original type name for converter logic
  @Deprecated('Not used by the generator; will be removed in 3.0.')
  static String getDartTypeFromOriginal(
      String originalType, bool isNullable, bool isList) {
    String dartType;

    switch (originalType) {
      case 'Int':
        dartType = 'int';
        break;
      case 'Float':
        dartType = 'double';
        break;
      case 'String':
        dartType = 'String';
        break;
      case 'Boolean':
        dartType = 'bool';
        break;
      case 'ID':
        dartType = 'String';
        break;
      case 'Short':
        dartType = 'int';
        break;
      case 'DateTime':
      case 'LocalDate':
        dartType = 'DateTime';
        break;
      case 'Decimal':
        dartType = 'Decimal';
        break;
      case 'Long':
        dartType = 'Long';
        break;
      case 'Byte':
        dartType = 'Byte';
        break;
      default:
        dartType = originalType;
        break;
    }

    if (isList) {
      return isNullable ? 'List<$dartType>?' : 'List<$dartType>';
    }

    return isNullable ? '$dartType?' : dartType;
  }
}
