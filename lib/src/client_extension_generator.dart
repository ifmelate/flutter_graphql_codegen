/// Client extension generation utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'code_utils.dart';
import 'config_context.dart';
import 'declarations.dart';
import 'diagnostics.dart';
import 'document_utils.dart';
import 'document_validator.dart';
import 'enum_settings.dart';
import 'flutter_generator.dart';
import 'json_exprs.dart';
import 'naming.dart';
import 'operation_groups.dart';
import 'operation_types.dart';
import 'schema_analyzer.dart';
import 'type_generator.dart';

/// Utility class for generating client extensions
class ClientExtensionGenerator {
  /// Generates a complete operation file (header, imports and the code from
  /// [generateClientExtension]).
  ///
  /// [sourcePath] is recorded in the header so the builder can tell which
  /// document a file was generated from.
  ///
  /// With a [group] (`group_operations: directory`) the file also adds the
  /// operation's methods to the group's class.
  ///
  /// [fragmentLibraries] maps fragments of [fragments] declared by another
  /// package (`fragment_imports`) to the URI of their library.
  static String generateOperationFile(
    String operationName,
    String operationType,
    String operationDocumentContent,
    DocumentNode schemaDoc,
    Set<String> definedTypes, {
    Map<String, FragmentDefinitionNode> fragments = const {},
    Map<String, String> fragmentLibraries = const {},
    String? sourcePath,
    OperationGroup? group,
  }) {
    final operation = _findOperation(
        gql_lang.parseString(operationDocumentContent), operationName);
    final scalarImports = TypeGenerator.scalarImportDirectives();
    final (body, libraries) = _generate(
      operationName,
      operationDocumentContent,
      schemaDoc,
      definedTypes,
      fragments: fragments,
      group: group,
      fragmentLibraries: fragmentLibraries,
    );
    final ignores = CodegenConfigContext.operationResultTypes
        ? 'unused_import, deprecated_member_use_from_same_package'
        : 'unused_import';
    return '''${CodeGenerationConstants.generatedFileWarning}
// Operation: $operationName (${operation.type.name})
${sourcePath == null ? '' : '// Source: $sourcePath\n'}${group == null ? '' : '${group.operationHeader}\n'}${CodeGenerationConstants.ignoreForFile}, $ignores

${FlutterGenerator.imports()}import 'package:graphql/client.dart' as graphql;
import 'package:normalize/utils.dart' as normalize;
${group == null ? '' : "import '${group.fileName}';\n"}${_libraryImports(libraries)}$scalarImports
$body''';
  }

  /// Import directives of generated files for [libraries] (fragment
  /// libraries, see [OperationClasses.libraries]) and types.dart, which is
  /// that of another package with `types_import`.
  static String _libraryImports(Iterable<String> libraries) => [
        for (final library in {
          ...libraries,
          CodegenConfigContext.typesImport ?? 'types.dart',
        })
          "import '$library';\n",
      ].join();

  /// Generates `fragments.dart`: for every fragment its document, an
  /// interface with its fields (implemented by the operation classes that
  /// spread it), a data class and `read<Fragment>Fragment` /
  /// `write<Fragment>Fragment` cache methods. Fragments on introspection
  /// types are left out. Returns null when no fragment is left.
  ///
  /// Fragments listed in [fragmentLibraries] are declared by another package
  /// (`fragment_imports`, name -> library URI): they are not declared again,
  /// but local fragments may spread them.
  static String? generateFragmentsFile(
    DocumentNode schemaDoc,
    Map<String, FragmentDefinitionNode> fragments, {
    Map<String, String> fragmentLibraries = const {},
  }) {
    if (fragments.isEmpty) return null;
    final schema = DocumentUtils.mergeSchemaExtensions(schemaDoc);
    SchemaAnalyzer.extractCustomTypesAndEnums(schema);
    EnumSettings.validate(schema);
    final types =
        OperationTypes(schema, fragments, fragmentLibraries: fragmentLibraries);
    if (types.fragmentNames.isEmpty) return null;
    types.checkFragments();

    final buffer = StringBuffer();
    for (final name in types.fragmentNames) {
      final camel = name.toCamelCase();
      final document = gql_lang
          .printNode(DocumentUtils.buildFragmentDocument(name, fragments));
      buffer
        ..writeln('/// GraphQL document of the `$name` fragment (with the '
            'fragments it uses).')
        ..writeln('final ${camel}Fragment = graphql.gql('
            '${_dartStringLiteral(document)});')
        ..writeln()
        ..writeln("const String ${camel}FragmentName = '$name';")
        ..writeln()
        ..write(types.fragmentInterfaces(name))
        ..write(types.fragmentData(name))
        ..write(_fragmentCacheExtension(types, name));
    }
    buffer.write(types.support);
    final code = '''${CodeGenerationConstants.generatedFileWarning}
// Fragments of all documents
${CodeGenerationConstants.ignoreForFile}, unused_import, deprecated_member_use_from_same_package

import 'package:graphql/client.dart' as graphql;
${_libraryImports(types.fragmentFileLibraries)}${TypeGenerator.scalarImportDirectives()}
$buffer''';

    // Classes are checked by checkFragments; this catches constants and
    // extensions, e.g. of names differing only in the case of the first
    // letter (`userBits` and `UserBits` both declare `userBitsFragment`).
    final seen = <String>{};
    for (final name in topLevelDeclarations(code)) {
      if (!seen.add(name)) {
        throw CodegenException(
          CodegenErrorCodes.buildDuplicateFragment,
          'fragments.dart would declare "$name" twice, for two fragments '
          'with similar names; rename one of them',
        );
      }
    }
    return code;
  }

  /// `read<Fragment>Fragment` / `write<Fragment>Fragment` on
  /// `GraphQLClient` for fragment [name].
  ///
  /// `normalize` identifies the object from `idFields` plus a `__typename`
  /// that defaults to the fragment's type condition. That default is right
  /// for a fragment on an object type, but names no cached object for one
  /// on an interface or union, so there `__typename` must be given (read)
  /// or is taken from the data (write).
  static String _fragmentCacheExtension(OperationTypes types, String name) {
    final camel = name.toCamelCase();
    final pascal = name.capitalize();
    final type = types.fragmentType(name);
    final abstract = TypeRegistry.isAbstract(type);
    final data = types.fragmentDataClass(name);
    final iface = types.fragmentInterfaceName(name);
    final read = _extensionMember('read${pascal}Fragment');
    final write = _extensionMember('write${pascal}Fragment');

    String request(String idFields) => '''
      graphql.FragmentRequest(
        fragment: graphql.Fragment(
          document: ${camel}Fragment,
          fragmentName: ${camel}FragmentName,
        ),
        idFields: $idFields,
        variables: variables ?? const {},
      )''';

    final String readIdFields;
    final String readCheck;
    final String writeIdFields;
    final String idDoc;
    final String writeIdDoc;
    if (abstract) {
      readIdFields = 'idFields';
      readCheck = '''
    if (!idFields.containsKey('__typename')) {
      throw ArgumentError.value(idFields, 'idFields',
          'needs "__typename": $name is on the abstract type $type');
    }
''';
      writeIdFields = "{'__typename': data.typename, ...idFields}";
      idDoc = '''
  /// [idFields] identify the object (usually `id`) and must include its
  /// `__typename`, since `$type` is abstract.''';
      writeIdDoc = '''
  /// [idFields] identify the object (usually `id`); `__typename` defaults to
  /// `data.typename`.''';
    } else {
      readIdFields = writeIdFields = "{'__typename': '$type', ...idFields}";
      readCheck = '';
      idDoc = writeIdDoc = '''
  /// [idFields] identify the object (usually `{'id': ...}`); `__typename`
  /// defaults to `$type`.''';
    }

    return '''
/// Cache access for the `$name` fragment.
extension ${pascal}FragmentExtension on graphql.GraphQLClient {
  /// Reads the `$name` fragment of an object from the cache; null when it
  /// isn't cached (or only partly).
  ///
$idDoc
  $data? $read(
    Map<String, dynamic> idFields, {
    Map<String, dynamic>? variables,
    bool optimistic = true,
  }) {
$readCheck    final Map<String, dynamic>? json = this.readFragment(
${request(readIdFields)},
      optimistic: optimistic,
    );
    return json == null ? null : $data.fromJson(json);
  }

  /// Writes [data] as the `$name` fragment of an object into the cache.
  /// Any object implementing [$iface] can be written, such as one returned
  /// by an operation that spreads the fragment.
  ///
$writeIdDoc
  void $write(
    Map<String, dynamic> idFields,
    $iface data, {
    Map<String, dynamic>? variables,
    bool broadcast = true,
  }) {
    this.writeFragment(
${request(writeIdFields)},
      data: data.toJson(),
      broadcast: broadcast,
    );
  }
}

''';
  }

  /// Generates the client code for a GraphQL operation: the document constant,
  /// an optional variables class, a typed `parse*Data` function and an
  /// extension on `GraphQLClient`.
  ///
  /// [operationDocumentContent] may contain several operations and fragments;
  /// the operation named [operationName] is used. Fragments referenced but not
  /// defined there are looked up in [fragments].
  static String generateClientExtension(
    String operationName,
    String operationType,
    String operationDocumentContent,
    DocumentNode schemaDoc,
    Set<String> definedTypes, {
    Map<String, FragmentDefinitionNode> fragments = const {},
  }) =>
      _generate(
        operationName,
        operationDocumentContent,
        schemaDoc,
        definedTypes,
        fragments: fragments,
      ).$1;

  /// [generateClientExtension] plus the fragment libraries the code uses
  /// (see [OperationClasses.libraries]).
  static (String, List<String>) _generate(
    String operationName,
    String operationDocumentContent,
    DocumentNode schemaDoc,
    Set<String> definedTypes, {
    Map<String, FragmentDefinitionNode> fragments = const {},
    OperationGroup? group,
    Map<String, String> fragmentLibraries = const {},
  }) {
    final operationDoc = gql_lang.parseString(operationDocumentContent);
    final operation = _findOperation(operationDoc, operationName);
    final allFragments = {
      ...fragments,
      ...DocumentUtils.collectFragments([operationDoc]),
    };

    final schema = DocumentUtils.mergeSchemaExtensions(schemaDoc);
    SchemaAnalyzer.extractCustomTypesAndEnums(schema);
    EnumSettings.validate(schema);
    if (CodegenConfigContext.validateDocuments) {
      DocumentValidator(schema).check(operation, allFragments);
    }

    final context = _OperationContext(
      name: operationName,
      operation: operation,
      schema: schema,
      definedTypes: definedTypes,
      strict: CodegenConfigContext.strictNullability,
      fragments: allFragments,
      fragmentLibraries: fragmentLibraries,
    );

    final document = gql_lang.printNode(
        DocumentUtils.buildOperationDocument(operation, allFragments));

    final buffer = StringBuffer()
      ..writeln('/// GraphQL document for the `$operationName` '
          '${operation.type.name}.')
      ..writeln('final ${context.camel}Document = graphql.gql('
          '${_dartStringLiteral(document)});')
      ..writeln()
      ..writeln("const String ${context.camel}OperationName = "
          "'$operationName';")
      ..writeln();

    final variables = _generateVariablesClass(context);
    if (variables.isNotEmpty) buffer.writeln(variables);

    final classes = context.classes;
    buffer.writeln(classes == null
        ? _generateParser(context)
        : _generateTypedParser(context, classes));
    buffer.writeln(_generateOptions(context));
    buffer.write(_generateExtension(context));
    if (group != null) buffer.write(_generateGroupExtension(context, group));
    final flutter = _generateFlutter(context, definedTypes);
    if (flutter.isNotEmpty) {
      buffer
        ..writeln()
        ..write(flutter);
    }
    // The result classes declare the marker too when they have copyWith.
    if (variables.contains('_undefined') &&
        !buffer.toString().contains(_undefinedDeclaration)) {
      buffer
        ..writeln()
        ..writeln('/// Marks `copyWith` parameters that were not passed.')
        ..writeln(_undefinedDeclaration);
    }
    return (buffer.toString(), classes?.libraries ?? const <String>[]);
  }

  static OperationDefinitionNode _findOperation(
      DocumentNode doc, String operationName) {
    final operations = doc.definitions.whereType<OperationDefinitionNode>();
    if (operations.isEmpty) {
      throw CodegenException(
        CodegenErrorCodes.buildOperationParse,
        'No operation found in document for "$operationName"',
      );
    }
    return operations.firstWhere(
      (op) => op.name?.value == operationName,
      orElse: () => operations.first,
    );
  }

  // ---------------------------------------------------------------------------
  // Variables
  // ---------------------------------------------------------------------------

  static const _undefinedDeclaration = 'const _undefined = Object();';

  static String _generateVariablesClass(_OperationContext ctx) {
    final defs = ctx.operation.variableDefinitions;
    if (defs.isEmpty) return '';

    final className = '${ctx.pascal}Variables';
    final includeNull = CodegenConfigContext.includeNullInputs;
    final fields = [
      for (final d in defs)
        (
          graphqlName: d.variable.name.value,
          dartName: dartFieldName(d.variable.name.value, className: className),
          type: d.type,
          dartType: JsonExprs.inputDartType(d.type,
              forceNullable:
                  !d.type.isNonNull || d.defaultValue?.value != null),
          optional: !d.type.isNonNull || d.defaultValue?.value != null,
          // An explicit null would override the default on the server.
          hasDefault: d.defaultValue?.value != null,
          defaultValue: d.defaultValue?.value,
        ),
    ];
    final names = fields.map((f) => f.dartName).toSet();
    String unused(String name) {
      while (names.contains(name)) {
        name = '${name}_';
      }
      return name;
    }

    final other = unused('other');
    // As in input classes: a variable named `copyWith` would clash with the
    // getter, one named `identical` would hide the function the copy and
    // the explicit nulls rely on.
    final hidesIdentical = names.contains('identical');
    final withCopy = !names.contains('copyWith') && !hidesIdentical;
    final copyWith = '${className}_CopyWith';

    // A variable of a nullable GraphQL type passed as null to `withNulls` or
    // `copyWith` is sent as null; a private flag per variable remembers that.
    // With include_null_inputs only variables with a default value need it.
    final withNulls = !hidesIdentical && fields.any((f) => !f.type.isNonNull);
    final flagged = [
      if (withNulls)
        for (final f in fields)
          if (!f.type.isNonNull && (!includeNull || f.hasDefault)) f,
    ];
    final flaggedNames = flagged.map((f) => f.dartName).toSet();
    final flags = flagged.isNotEmpty;
    String flag(String name) => '_${name}IsNull';
    String cast(String v, String type) => type == 'dynamic' ? v : '$v as $type';
    String param(String name, bool optional) =>
        optional ? 'this.$name' : 'required this.$name';

    final buffer = StringBuffer()
      ..writeln(
          '/// Variables for the `${ctx.name}` ${ctx.operation.type.name}.')
      ..writeln('///')
      ..writeln('/// Pass `toJson()` as the `variables` argument of the '
          'generated methods.')
      ..writeln('class $className {')
      ..writeln('  const $className({');
    for (final f in fields) {
      buffer.writeln('    ${param(f.dartName, f.optional)},');
    }
    buffer
      ..writeln(flags
          ? '  }) : ${[
              for (final f in flagged) '${flag(f.dartName)} = false'
            ].join(',\n        ')};'
          : '  });')
      ..writeln();

    if (withNulls) {
      buffer
        ..writeln(flags
            ? '  /// Like [$className.new], but a variable passed as `null` is '
                'sent as `null`\n  /// (replacing its default value, if it '
                'has one). Variables left out are not\n  /// sent.'
            : '  /// The same as [$className.new]: with include_null_inputs '
                'every null variable\n  /// is sent as `null`.')
        ..writeln('  const factory $className.withNulls({');
      for (final f in fields) {
        buffer.writeln('    ${f.optional ? '' : 'required '}'
            '${f.dartType} ${f.dartName},');
      }
      buffer
        ..writeln('  }) = ${flags ? '$className._withNulls' : className};')
        ..writeln();
    }
    if (flags) {
      buffer.writeln('  const $className._withNulls({');
      for (final f in fields) {
        buffer.writeln(flaggedNames.contains(f.dartName)
            ? '    Object? ${f.dartName} = _undefined,'
            : '    ${param(f.dartName, f.optional)},');
      }
      final inits = [
        for (final f in flagged) ...[
          '${f.dartName} = identical(${f.dartName}, _undefined) ? null : '
              '${cast(f.dartName, f.dartType)}',
          '${flag(f.dartName)} = identical(${f.dartName}, null)',
        ],
      ];
      buffer
        ..writeln('  }) : ${inits.join(',\n        ')};')
        ..writeln();
    }

    for (final f in fields) {
      buffer.writeln('  final ${f.dartType} ${f.dartName};');
    }
    if (flags) {
      buffer
        ..writeln()
        ..writeln('  // Whether a null variable is sent as null (set by '
            'withNulls and copyWith).');
      for (final f in flagged) {
        buffer.writeln('  final bool ${flag(f.dartName)};');
      }
    }

    buffer
      ..writeln()
      ..writeln('  Map<String, dynamic> toJson() => <String, dynamic>{');
    for (final f in fields) {
      if (f.optional) {
        var expr = JsonExprs.toJsonExpr(f.type, '${f.dartName}!');
        if (expr == '${f.dartName}!') expr = f.dartName;
        final defaultValue = f.defaultValue;
        if (defaultValue != null) {
          // The default is sent explicitly: the server would apply it anyway,
          // but the normalized cache doesn't, and @include/@skip on a missing
          // variable would make it expect fields the server left out. An
          // explicit null (withNulls, copyWith) replaces the default.
          var literal = _valueLiteral(defaultValue);
          if (flaggedNames.contains(f.dartName)) {
            literal = '(${flag(f.dartName)} ? null : $literal)';
          }
          buffer.writeln(expr == f.dartName
              ? "        '${f.graphqlName}': ${f.dartName} ?? $literal,"
              : "        '${f.graphqlName}': ${f.dartName} == null "
                  '? $literal : $expr,');
        } else if (includeNull) {
          final value = expr == f.dartName
              ? expr
              : '${f.dartName} == null ? null : $expr';
          buffer.writeln("        '${f.graphqlName}': $value,");
        } else if (flaggedNames.contains(f.dartName)) {
          buffer.writeln("        if (${f.dartName} != null) "
              "'${f.graphqlName}': $expr "
              "else if (${flag(f.dartName)}) '${f.graphqlName}': null,");
        } else {
          buffer.writeln("        if (${f.dartName} != null) "
              "'${f.graphqlName}': $expr,");
        }
      } else {
        buffer.writeln("        '${f.graphqlName}': "
            "${JsonExprs.toJsonExpr(f.type, f.dartName)},");
      }
    }
    buffer
      ..writeln('      };')
      ..writeln();

    if (withCopy) {
      buffer
        ..writeln('  /// Copies these variables with the given ones replaced.')
        ..writeln('  $copyWith get copyWith => _$copyWith(this);')
        ..writeln();
    }

    bool deep(String type) => type.startsWith('List<');
    buffer
      ..writeln('  @override')
      ..writeln('  bool operator ==(Object $other) =>');
    if (!hidesIdentical) buffer.writeln('      identical(this, $other) ||');
    buffer.write('      $other is $className');
    for (final f in fields) {
      buffer.write(deep(f.dartType)
          ? ' &&\n          graphqlDeepEquals(${f.dartName}, '
              '$other.${f.dartName})'
          : ' &&\n          ${f.dartName} == $other.${f.dartName}');
    }
    // An explicit null is sent, an absent variable is not: they differ.
    for (final f in flagged) {
      buffer.write(' &&\n          ${flag(f.dartName)} == '
          '$other.${flag(f.dartName)}');
    }
    buffer
      ..writeln(';')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  int get hashCode => Object.hashAll([');
    for (final f in fields) {
      buffer.writeln(deep(f.dartType)
          ? '        graphqlDeepHash(${f.dartName}),'
          : '        ${f.dartName},');
    }
    for (final f in flagged) {
      buffer.writeln('        ${flag(f.dartName)},');
    }
    buffer
      ..writeln('      ]);')
      ..writeln('}');

    if (withCopy) {
      buffer
        ..writeln()
        ..writeln(flags
            ? '/// `copyWith` of [$className]. A variable set to `null` is '
                'sent as `null`\n/// (see [$className.withNulls]).'
            : '/// `copyWith` of [$className]; `null` sets a variable to '
                'null.')
        ..writeln('abstract class $copyWith {')
        ..writeln('  $className call({');
      for (final f in fields) {
        final type = f.dartType.endsWith('?') || f.dartType == 'dynamic'
            ? f.dartType
            : '${f.dartType}?';
        buffer.writeln('    $type ${f.dartName},');
      }
      buffer
        ..writeln('  });')
        ..writeln('}')
        ..writeln()
        ..writeln('class _$copyWith implements $copyWith {')
        ..writeln('  const _$copyWith(this._value);')
        ..writeln()
        ..writeln('  final $className _value;')
        ..writeln()
        ..writeln('  @override')
        ..writeln('  $className call({');
      for (final f in fields) {
        buffer.writeln('    Object? ${f.dartName} = _undefined,');
      }
      buffer
        ..writeln('  }) =>')
        ..writeln('      ${flags ? '$className._withNulls' : className}(');
      for (final f in fields) {
        final name = f.dartName;
        final isFlagged = flaggedNames.contains(name);
        final keep = isFlagged
            ? '(_value.${flag(name)} ? null : _value.$name ?? _undefined)'
            : '_value.$name';
        final passed = isFlagged ? name : cast(name, f.dartType);
        buffer.writeln(
            '        $name: identical($name, _undefined) ? $keep : $passed,');
      }
      buffer
        ..writeln('      );')
        ..writeln('}');
    }
    return buffer.toString();
  }

  /// Dart expression for the JSON form of a GraphQL constant [value] (a
  /// variable's default value).
  static String _valueLiteral(ValueNode value) => switch (value) {
        IntValueNode(:final value) => value,
        FloatValueNode(:final value) => value,
        BooleanValueNode(:final value) => '$value',
        NullValueNode() => 'null',
        StringValueNode(:final value) => _stringLiteral(value),
        EnumValueNode(:final name) => _stringLiteral(name.value),
        ListValueNode(:final values) =>
          '<dynamic>[${values.map(_valueLiteral).join(', ')}]',
        ObjectValueNode(:final fields) => '<String, dynamic>{${fields.map(
              (f) => '${_stringLiteral(f.name.value)}: '
                  '${_valueLiteral(f.value)}',
            ).join(', ')}}',
        _ => throw CodegenException(
            CodegenErrorCodes.buildOperationParse,
            'Unsupported default value: ${gql_lang.printNode(value)}',
          ),
      };

  static String _stringLiteral(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  static String _generateParser(_OperationContext ctx) {
    final fn = 'parse${ctx.pascal}Data';
    final returnType = ctx.returnType;
    final noData = returnType.endsWith('?')
        ? 'return null;'
        : "throw StateError('${ctx.name}: response contains no data');";

    final buffer = StringBuffer()
      ..writeln('/// Converts the `data` of a `${ctx.name}` response into a '
          'typed value.')
      ..writeln('$returnType $fn(Map<String, dynamic>? data) {')
      ..writeln('  if (data == null) {')
      ..writeln('    $noData')
      ..writeln('  }');

    final fields = ctx.rootFields;
    if (fields.isEmpty) {
      buffer.writeln('  return data;');
    } else if (fields.length == 1) {
      final f = fields.single;
      buffer
        ..writeln("  final value = data['${f.responseKey}'];")
        ..writeln('  return ${f.fromJson('value')};');
    } else {
      buffer.writeln('  return ${ctx.resultClassName}(');
      for (final f in fields) {
        buffer.writeln("    ${f.dartName}: "
            "${f.fromJson("data['${f.responseKey}']")},");
      }
      buffer.writeln('  );');
    }
    buffer.writeln('}');

    if (fields.length > 1) {
      buffer
        ..writeln()
        ..write(_generateResultClass(ctx));
    }
    return buffer.toString();
  }

  /// `parse*Data` and the result classes (`result_types: operation`).
  static String _generateTypedParser(
      _OperationContext ctx, OperationClasses classes) {
    final returnType = classes.returnType;
    final noData = returnType.endsWith('?')
        ? 'return null;'
        : "throw StateError('${ctx.name}: response contains no data');";
    final buffer = StringBuffer()
      ..writeln('/// Converts the `data` of a `${ctx.name}` response into a '
          'typed value.')
      ..writeln(
          '$returnType parse${ctx.pascal}Data(Map<String, dynamic>? data) {')
      ..writeln('  if (data == null) {')
      ..writeln('    $noData')
      ..writeln('  }')
      ..writeln('  return ${classes.parseExpr('data')};')
      ..writeln('}')
      ..writeln();
    buffer.write(classes.code);
    return buffer.toString();
  }

  static String _generateResultClass(_OperationContext ctx) {
    final name = ctx.resultClassName;
    final buffer = StringBuffer()
      ..writeln(
          '/// Typed `data` of the `${ctx.name}` ${ctx.operation.type.name}.')
      ..writeln('class $name {')
      ..writeln('  const $name({');
    for (final f in ctx.rootFields) {
      buffer.writeln(f.dartType.endsWith('?')
          ? '    this.${f.dartName},'
          : '    required this.${f.dartName},');
    }
    buffer
      ..writeln('  });')
      ..writeln();
    for (final f in ctx.rootFields) {
      buffer.writeln('  final ${f.dartType} ${f.dartName};');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Client extension
  // ---------------------------------------------------------------------------

  static String _generateExtension(_OperationContext ctx) {
    final camel = ctx.camel;
    final run = _extensionMember(camel);
    final runData = _extensionMember('${camel}Data');
    final parse = 'parse${ctx.pascal}Data';
    final kind = ctx.operation.type;
    const vars = '[Map<String, dynamic>? variables]';
    const resultType = 'graphql.QueryResult<Map<String, dynamic>>';
    final options = '''
        document: ${camel}Document,
        operationName: ${camel}OperationName,
        variables: variables ?? const {},''';

    if (kind == OperationType.subscription) {
      return '''
extension ${ctx.name}Extension on graphql.GraphQLClient {
  /// Subscribes to `${ctx.name}` and emits raw results.
  ///
  /// Results with errors are emitted as [graphql.OperationException] errors.
  Stream<$resultType> $run($vars) {
    return this.subscribe(
      graphql.SubscriptionOptions<Map<String, dynamic>>(
$options
      ),
    ).map((result) {
      if (result.hasException) {
        throw result.exception!;
      }
      return result;
    });
  }

  /// Subscribes to `${ctx.name}` and emits typed data.
  Stream<${ctx.returnType}> $runData($vars) {
    return $run(variables)
        .where((result) => !(result.isLoading && result.data == null))
        .map((result) => $parse(result.data));
  }
}
''';
    }

    final isMutation = kind == OperationType.mutation;
    final method = isMutation ? 'mutate' : 'query';
    final optionsType = isMutation ? 'MutationOptions' : 'QueryOptions';
    return '''
extension ${ctx.name}Extension on graphql.GraphQLClient {
  /// Executes `${ctx.name}` and returns the raw result.
  ///
  /// Throws [graphql.OperationException] when the result has errors.
  Future<$resultType> $run($vars) async {
    final result = await this.$method(
      graphql.$optionsType<Map<String, dynamic>>(
$options
      ),
    );
    if (result.hasException) {
      throw result.exception!;
    }
    return result;
  }

  /// Executes `${ctx.name}` and returns typed data.
  Future<${ctx.returnType}> $runData($vars) async {
    final result = await $run(variables);
    return $parse(result.data);
  }
${isMutation ? '' : _generateCacheHelpers(ctx)}}
''';
  }

  /// Members of `GraphQLClient` (and `Object`). An extension method with one of
  /// these names would never be called: the client's own member wins. So such
  /// names get a trailing underscore (operation `Query` -> `client.query_()`).
  static const _clientMemberNames = {
    'cache', 'copyWith', 'defaultPolicies', 'fetchMore', 'link', 'mutate', //
    'query', 'queryManager', 'readFragment', 'readQuery', 'resetStore',
    'subscribe', 'watchMutation', 'watchQuery', 'writeFragment', 'writeQuery',
    'hashCode', 'noSuchMethod', 'runtimeType', 'toString',
  };

  static String _extensionMember(String name) =>
      _clientMemberNames.contains(name) ? '${name}_' : name;

  /// Names of the members of `GraphQLClient` itself.
  static Set<String> get clientMemberNames => _clientMemberNames;

  /// Names of the `GraphQLClient` extension methods of operation
  /// [operationName] of type [operationType] (`query`, `mutation` or
  /// `subscription`).
  static Set<String> operationMemberNames(
      String operationName, String operationType) {
    final camel = operationName.toCamelCase();
    final pascal = operationName.capitalize();
    return {
      _extensionMember(camel),
      _extensionMember('${camel}Data'),
      if (operationType == 'query') ...[
        _extensionMember('read$pascal'),
        _extensionMember('write$pascal'),
        _extensionMember('evict$pascal'),
      ],
    };
  }

  /// Members of the group class itself; an operation method with one of
  /// these names gets a trailing underscore in the group.
  static const _groupMemberNames = {'client'};

  /// The extension adding the methods of the operation to the class of its
  /// [group]; each delegates to the `GraphQLClient` extension method of the
  /// same name.
  static String _generateGroupExtension(
      _OperationContext ctx, OperationGroup group) {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('/// `${ctx.name}` in the operations of `${group.path}` '
          '([${group.className}]).')
      ..writeln('extension ${OperationGroup.operationExtension(ctx.name)} '
          'on ${group.className} {');
    void member(String returnType, String flat, String params, String args) {
      final name = _groupMemberNames.contains(flat) ? '${flat}_' : flat;
      buffer
        ..writeln('  /// Same as [${ctx.name}Extension.$flat].')
        ..writeln('  $returnType $name($params) => client.$flat($args);')
        ..writeln();
    }

    final camel = ctx.camel;
    const vars = '[Map<String, dynamic>? variables]';
    const raw = 'graphql.QueryResult<Map<String, dynamic>>';
    final stream = ctx.operation.type == OperationType.subscription;
    String wrap(String t) => stream ? 'Stream<$t>' : 'Future<$t>';
    member(wrap(raw), _extensionMember(camel), vars, 'variables');
    member(wrap(ctx.returnType), _extensionMember('${camel}Data'), vars,
        'variables');
    if (ctx.operation.type == OperationType.query) {
      final s = _cacheSignatures(ctx);
      final pascal = ctx.pascal;
      member(s.readType, _extensionMember('read$pascal'), s.readParams,
          s.readArgs);
      member(
          'void', _extensionMember('write$pascal'), s.writeParams, s.writeArgs);
      member(
          'bool', _extensionMember('evict$pascal'), s.evictParams, s.evictArgs);
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Typed options and cache helpers
  // ---------------------------------------------------------------------------

  /// Top-level functions building `package:graphql` options whose
  /// `parserFn` is the generated parser, so `QueryResult.parsedData` (and
  /// `ObservableQuery` results) are typed.
  static String _generateOptions(_OperationContext ctx) {
    final params = _optionsParams(ctx);
    final buffer = StringBuffer();
    switch (ctx.operation.type) {
      case OperationType.query:
        buffer
          ..writeln(_optionsFunction(ctx, 'QueryOptions', 'Query',
              'GraphQLClient.query', params['Query']!))
          ..write(_optionsFunction(ctx, 'WatchQueryOptions', 'WatchQuery',
              'GraphQLClient.watchQuery', params['WatchQuery']!));
      case OperationType.mutation:
        buffer.write(_optionsFunction(ctx, 'MutationOptions', 'Mutation',
            'GraphQLClient.mutate', params['Mutation']!));
      case OperationType.subscription:
        buffer.write(_optionsFunction(
            ctx,
            'SubscriptionOptions',
            'Subscription',
            'GraphQLClient.subscribe',
            params['Subscription']!));
    }
    return buffer.toString();
  }

  /// Named parameters of the options functions of the operation, by suffix
  /// (`Query`, `WatchQuery`, `Mutation`, `Subscription`).
  static Map<String, List<OptionsParam>> _optionsParams(_OperationContext ctx) {
    const common = [
      OptionsParam('graphql.FetchPolicy?', 'fetchPolicy'),
      OptionsParam('graphql.ErrorPolicy?', 'errorPolicy'),
      OptionsParam('graphql.CacheRereadPolicy?', 'cacheRereadPolicy'),
      OptionsParam('graphql.Context?', 'context'),
      OptionsParam('Object?', 'optimisticResult'),
    ];
    const poll = OptionsParam('Duration?', 'pollInterval');
    return switch (ctx.operation.type) {
      OperationType.query => {
          'Query': const [
            ...common,
            poll,
            // Called by graphql_flutter's Query widget and useQuery hook.
            OptionsParam('graphql.OnQueryComplete?', 'onComplete'),
            OptionsParam('graphql.OnQueryError?', 'onError'),
          ],
          'WatchQuery': const [
            ...common,
            poll,
            OptionsParam('bool', 'fetchResults', 'false'),
            OptionsParam('bool', 'carryForwardDataOnException', 'true'),
            OptionsParam('bool?', 'eagerlyFetchResults'),
          ],
        },
      OperationType.mutation => {
          'Mutation': [
            ...common,
            OptionsParam(
                'graphql.OnMutationUpdate<${ctx.returnType}>?', 'update'),
            const OptionsParam('graphql.OnMutationCompleted?', 'onCompleted'),
            const OptionsParam('graphql.OnError?', 'onError'),
          ],
        },
      OperationType.subscription => {'Subscription': common},
    };
  }

  /// The widgets and hooks of the operation (`flutter_widgets`,
  /// `flutter_hooks`).
  static String _generateFlutter(
          _OperationContext ctx, Set<String> definedTypes) =>
      FlutterGenerator.generate(FlutterOperation(
        name: ctx.name,
        type: ctx.operation.type,
        pascal: ctx.pascal,
        camel: ctx.camel,
        resultType: ctx.returnType,
        variables: switch (ctx.variablesKind) {
          _VariablesKind.none => OperationVariables.none,
          _VariablesKind.required => OperationVariables.required,
          _VariablesKind.optional => OperationVariables.optional,
        },
        optionsParams: _optionsParams(ctx),
        definedTypes: definedTypes,
      ));

  static String _optionsFunction(
    _OperationContext ctx,
    String optionsClass,
    String suffix,
    String clientMethod,
    List<OptionsParam> params,
  ) {
    final t = ctx.returnType;
    final vars = '${ctx.pascal}Variables';
    final buffer = StringBuffer()
      ..writeln('/// Options for running `${ctx.name}` with '
          '[graphql.$clientMethod]; the result\'s `parsedData` is typed.')
      ..write('graphql.$optionsClass<$t> ${ctx.camel}${suffix}Options(');
    switch (ctx.variablesKind) {
      case _VariablesKind.required:
        buffer.write('\n  $vars variables, {\n');
      case _VariablesKind.optional:
        buffer.write('{\n  $vars? variables,\n');
      case _VariablesKind.none:
        buffer.write('{\n');
    }
    for (final param in params) {
      buffer.writeln('  ${param.declaration},');
    }
    buffer
      ..writeln('}) =>')
      ..writeln('    graphql.$optionsClass<$t>(')
      ..writeln('    document: ${ctx.camel}Document,')
      ..writeln('    operationName: ${ctx.camel}OperationName,')
      ..writeln('    variables: ${ctx.variablesJson},');
    for (final param in params) {
      buffer.writeln('    ${param.name}: ${param.name},');
    }
    buffer
      ..writeln('    parserFn: parse${ctx.pascal}Data,')
      ..writeln('  );');
    return buffer.toString();
  }

  /// Parameters of the `read*` / `write*` / `evict*` methods of a query, the
  /// arguments forwarding them to methods with the same parameters, and the
  /// arguments of its options function.
  static ({
    String readType,
    String readParams,
    String readArgs,
    String writeParams,
    String writeArgs,
    String evictParams,
    String evictArgs,
    String optionsArgs,
  }) _cacheSignatures(_OperationContext ctx) {
    final vars = '${ctx.pascal}Variables';
    final t =
        ctx.returnType.endsWith('?') ? ctx.returnType : '${ctx.returnType}?';
    final data = ctx.classes?.writeType ?? 'Map<String, dynamic>';
    return switch (ctx.variablesKind) {
      _VariablesKind.required => (
          readType: t,
          readParams: '$vars variables, {bool optimistic = true}',
          readArgs: 'variables, optimistic: optimistic',
          writeParams: '$vars variables, $data data, {bool broadcast = true}',
          writeArgs: 'variables, data, broadcast: broadcast',
          evictParams: '$vars variables',
          evictArgs: 'variables',
          optionsArgs: 'variables',
        ),
      _VariablesKind.optional => (
          readType: t,
          readParams: '{$vars? variables, bool optimistic = true}',
          readArgs: 'variables: variables, optimistic: optimistic',
          writeParams: '$data data, {$vars? variables, bool broadcast = true}',
          writeArgs: 'data, variables: variables, broadcast: broadcast',
          evictParams: '{$vars? variables}',
          evictArgs: 'variables: variables',
          optionsArgs: 'variables: variables',
        ),
      _VariablesKind.none => (
          readType: t,
          readParams: '{bool optimistic = true}',
          readArgs: 'optimistic: optimistic',
          writeParams: '$data data, {bool broadcast = true}',
          writeArgs: 'data, broadcast: broadcast',
          evictParams: '',
          evictArgs: '',
          optionsArgs: '',
        ),
    };
  }

  /// `read*` / `write*` methods for the normalized cache of a query.
  static String _generateCacheHelpers(_OperationContext ctx) {
    final options = '${ctx.camel}QueryOptions';
    final classes = ctx.classes;
    final s = _cacheSignatures(ctx);
    final t = s.readType;
    final readParams = s.readParams;
    final writeParams = s.writeParams;
    final evictParams = s.evictParams;
    final args = s.optionsArgs;
    final write = classes == null
        ? '''
  /// Writes raw `data` for `${ctx.name}` into the cache, shaped as the server
  /// returns it, including `__typename` on every object (also the root).
  void ${_extensionMember('write${ctx.pascal}')}($writeParams) {
    this.writeQuery($options($args).asRequest, data: data, broadcast: broadcast);
  }
'''
        : '''
  /// Writes `data` for `${ctx.name}` into the cache, as if the server had
  /// returned it.
  void ${_extensionMember('write${ctx.pascal}')}($writeParams) {
    this.writeQuery($options($args).asRequest,
        data: ${classes.writeExpr('data')}, broadcast: broadcast);
  }
''';
    return '''

  /// Reads `${ctx.name}` from the cache; null when it isn't cached.
  $t ${_extensionMember('read${ctx.pascal}')}($readParams) {
    final Map<String, dynamic>? data =
        this.readQuery($options($args).asRequest, optimistic: optimistic);
    return data == null ? null : parse${ctx.pascal}Data(data);
  }

$write
  /// Removes the cached root fields of `${ctx.name}` for these variables, so
  /// the next `cacheFirst` read fetches it again. Returns whether anything was
  /// removed. Objects it pointed to stay cached, and active `watchQuery`
  /// results are not notified; call `refetch()` on them if needed.
  bool ${_extensionMember('evict${ctx.pascal}')}($evictParams) {
    final request = $options($args).asRequest;
    final document = request.operation.document;
    final rootId = normalize.resolveRootTypename(
        normalize.getOperationDefinition(
            document, request.operation.operationName),
        this.cache.typePolicies);
    final root = this.cache.readNormalized(rootId, optimistic: false);
    if (root == null) return false;
    final keys = normalize.operationFieldNames(
        document,
        request.operation.operationName ?? '',
        request.variables,
        this.cache.typePolicies,
        this.cache.possibleTypes);
    final rest = Map<String, dynamic>.of(root);
    var removed = false;
    for (final key in keys) {
      // Shared by every query on this root; reads need it.
      if (key == '__typename') continue;
      if (rest.containsKey(key)) {
        rest.remove(key);
        removed = true;
      }
    }
    if (removed) this.cache.writeNormalized(rootId, rest);
    return removed;
  }
''';
  }

  // ---------------------------------------------------------------------------
  // Type helpers
  // ---------------------------------------------------------------------------

  /// Returns [s] as a Dart string literal (raw triple-quoted when possible).
  static String _dartStringLiteral(String s) {
    if (!s.contains('"""')) return 'r"""\n$s\n"""';
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\n', r'\n');
    return "'$escaped'";
  }
}

enum _VariablesKind { none, required, optional }

/// A named parameter of a generated options function (`<op>QueryOptions`),
/// passed on unchanged as the argument of the same name.
class OptionsParam {
  final String type;
  final String name;

  /// Default value, for a non-nullable parameter.
  final String? defaultValue;

  const OptionsParam(this.type, this.name, [this.defaultValue]);

  /// `Type name` or `Type name = default`.
  String get declaration =>
      defaultValue == null ? '$type $name' : '$type $name = $defaultValue';
}

/// A root field selected by an operation.
class _RootField {
  final String responseKey;
  final String dartName;
  final String dartType;
  final String Function(String jsonExpr) fromJson;

  _RootField(this.responseKey, this.dartName, this.dartType, this.fromJson);
}

/// Pre-computed information about the operation being generated.
class _OperationContext {
  final String name;
  final OperationDefinitionNode operation;
  final bool strict;
  final String camel;
  final String pascal;

  /// Root fields of the schema-typed result (`result_types: schema`).
  late final List<_RootField> rootFields;

  /// Result classes (`result_types: operation`).
  OperationClasses? classes;

  _OperationContext({
    required this.name,
    required this.operation,
    required DocumentNode schema,
    required Set<String> definedTypes,
    required this.strict,
    required Map<String, FragmentDefinitionNode> fragments,
    Map<String, String> fragmentLibraries = const {},
  })  : camel = name.toCamelCase(),
        pascal = name.capitalize() {
    final rootType = _rootType(schema);
    if (CodegenConfigContext.operationResultTypes) {
      rootFields = const [];
      classes = OperationTypes(schema, fragments,
              fragmentLibraries: fragmentLibraries)
          .operation(operation, name, rootType.name.value);
      return;
    }
    rootFields = [
      for (final sel in operation.selectionSet.selections)
        if (sel is FieldNode && sel.name.value != '__typename')
          _rootField(sel, rootType, definedTypes),
    ];
  }

  String get resultClassName => '${pascal}Result';

  /// Whether the operation has variables, and whether any is required.
  _VariablesKind get variablesKind {
    final defs = operation.variableDefinitions;
    if (defs.isEmpty) return _VariablesKind.none;
    return defs.any((d) => d.type.isNonNull && d.defaultValue?.value == null)
        ? _VariablesKind.required
        : _VariablesKind.optional;
  }

  /// Expression for the variables map in generated options functions.
  String get variablesJson => switch (variablesKind) {
        _VariablesKind.required => 'variables.toJson()',
        _VariablesKind.optional => 'variables?.toJson() ?? const {}',
        _VariablesKind.none => 'const {}',
      };

  /// Return type of the generated `*Data` method / `parse*Data` function.
  String get returnType {
    final classes = this.classes;
    if (classes != null) return classes.returnType;
    if (rootFields.isEmpty) return 'Map<String, dynamic>?';
    if (rootFields.length == 1) return rootFields.single.dartType;
    return strict ? resultClassName : '$resultClassName?';
  }

  ObjectTypeDefinitionNode _rootType(DocumentNode schema) {
    try {
      final root = SchemaAnalyzer.findRootType(schema, operation.type.name);
      if (root != null) return root;
    } on StateError {
      // Reported below.
    }
    throw CodegenException(
      CodegenErrorCodes.buildOperationParse,
      'Schema has no root type for ${operation.type.name} operations '
      '(needed by "$name")',
    );
  }

  _RootField _rootField(FieldNode sel, ObjectTypeDefinitionNode rootType,
      Set<String> definedTypes) {
    final fieldName = sel.name.value;
    // Introspection fields: their types aren't in the SDL, so the result is
    // the raw JSON.
    if (fieldName == '__schema' || fieldName == '__type') {
      final responseKey = sel.alias?.value ?? fieldName;
      return _RootField(
        responseKey,
        dartFieldName(responseKey, className: resultClassName),
        'Map<String, dynamic>?',
        (v) => '$v as Map<String, dynamic>?',
      );
    }
    final schemaField =
        rootType.fields.where((f) => f.name.value == fieldName).firstOrNull;
    if (schemaField == null) {
      throw CodegenException(
        CodegenErrorCodes.buildUnknownField,
        'Field "$fieldName" does not exist on type '
        '"${rootType.name.value}" (operation "$name")',
      );
    }

    // @skip/@include may remove the field from the response entirely.
    final conditional = sel.directives
        .any((d) => d.name.value == 'skip' || d.name.value == 'include');
    final responseKey = sel.alias?.value ?? fieldName;
    final type = schemaField.type;
    return _RootField(
      responseKey,
      dartFieldName(responseKey, className: resultClassName),
      JsonExprs.outputDartType(type,
          legacy: !strict, forceNullable: conditional),
      (v) => JsonExprs.fromJsonExpr(type, v,
          legacy: !strict,
          definedTypes: definedTypes,
          forceNullable: conditional),
    );
  }
}
