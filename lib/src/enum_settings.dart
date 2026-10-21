/// Per-enum settings of the `enums:` option, as the generators use them.
library;

import 'package:gql/ast.dart';

import 'code_utils.dart';
import 'config.dart';
import 'config_context.dart';
import 'diagnostics.dart';
import 'naming.dart';

/// Answers what the `enums:` option (and `unknown_enum_fallback`) mean for
/// one GraphQL enum.
class EnumSettings {
  static EnumConfig? _of(String name) =>
      TypeRegistry.isEnum(name) ? CodegenConfigContext.enumConfigs[name] : null;

  /// Dart type the user maps enum [name] to (no Dart enum is generated for
  /// it), or null.
  static String? customType(String name) => _of(name)?.type;

  /// Whether enum [name] is mapped to a user type.
  static bool isCustom(String name) => customType(name) != null;

  /// GraphQL name of the value unknown values of enum [name] decode to, or
  /// null.
  static String? fallback(String name) =>
      isCustom(name) ? null : _of(name)?.fallback;

  /// `Enum.value` expression of the fallback of enum [dartName], or null.
  static String? fallbackExpr(String name, String dartName) {
    final value = fallback(name);
    return value == null ? null : '$dartName.${dartEnumValueName(value)}';
  }

  /// Whether the generated Dart enum [name] has a `$unknown` value: with
  /// `unknown_enum_fallback`, unless the enum has its own `fallback`.
  static bool hasUnknown(String name) =>
      TypeRegistry.isEnum(name) &&
      CodegenConfigContext.unknownEnumFallback &&
      !isCustom(name) &&
      fallback(name) == null;

  /// Whether fields of enum [name] get a `<field>Raw` sibling with the string
  /// the server sent: when unknown values decode to `$unknown` or to a
  /// fallback value.
  static bool hasRaw(String name) =>
      TypeRegistry.isEnum(name) &&
      !isCustom(name) &&
      (CodegenConfigContext.unknownEnumFallback || fallback(name) != null);

  /// Libraries of the user types of mapped enums.
  static Iterable<String> get imports => CodegenConfigContext.enumConfigs.values
      .map((c) => c.type == null ? null : c.import)
      .nonNulls;

  /// Checks the `enums:` option against [schema] (merged with its
  /// extensions): every entry must name an enum, and a fallback one of its
  /// values.
  static void validate(DocumentNode schema) {
    final configs = CodegenConfigContext.enumConfigs;
    if (configs.isEmpty) return;
    final enums = {
      for (final d in schema.definitions.whereType<EnumTypeDefinitionNode>())
        d.name.value: d,
    };
    final kinds = {
      for (final d in schema.definitions.whereType<TypeDefinitionNode>())
        d.name.value: switch (d) {
          ObjectTypeDefinitionNode() => 'an object type',
          InterfaceTypeDefinitionNode() => 'an interface',
          UnionTypeDefinitionNode() => 'a union',
          InputObjectTypeDefinitionNode() => 'an input type',
          ScalarTypeDefinitionNode() => 'a scalar',
          _ => 'a type',
        },
    };
    final problems = <String>[];
    for (final MapEntry(key: name, value: config) in configs.entries) {
      problems.addAll(config.problems(name));
      final def = enums[name];
      if (def == null) {
        final kind = kinds[name];
        final known = enums.keys.toList()..sort();
        problems.add(kind != null
            ? 'enums.$name: "$name" is $kind, not an enum'
            : 'enums.$name: the schema has no enum "$name"'
                '${known.isEmpty ? '' : ' (enums: ${known.join(', ')})'}');
        continue;
      }
      final fallback = config.fallback;
      final values = def.values.map((v) => v.name.value).toList()..sort();
      if (fallback != null && !values.contains(fallback)) {
        problems.add('enums.$name: fallback "$fallback" is not a value of '
            '$name (values: ${values.join(', ')})');
      }
    }
    if (problems.isEmpty) return;
    throw CodegenException(
      CodegenErrorCodes.cfgInvalid,
      'Invalid enums option:\n${problems.map((p) => '  - $p').join('\n')}',
    );
  }
}
