/// Client extension generation utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'code_utils.dart';
import 'config_context.dart';
import 'diagnostics.dart';
import 'document_utils.dart';
import 'document_validator.dart';
import 'naming.dart';
import 'schema_analyzer.dart';
import 'type_generator.dart';

/// Utility class for generating client extensions
class ClientExtensionGenerator {
  /// Generates a complete operation file (header, imports and the code from
  /// [generateClientExtension]).
  ///
  /// [sourcePath] is recorded in the header so the builder can tell which
  /// document a file was generated from.
  static String generateOperationFile(
    String operationName,
    String operationType,
    String operationDocumentContent,
    DocumentNode schemaDoc,
    Set<String> definedTypes, {
    Map<String, FragmentDefinitionNode> fragments = const {},
    String? sourcePath,
  }) {
    final operation = _findOperation(
        gql_lang.parseString(operationDocumentContent), operationName);
    final scalarImports = TypeGenerator.scalarImportDirectives();
    final body = generateClientExtension(
      operationName,
      operationType,
      operationDocumentContent,
      schemaDoc,
      definedTypes,
      fragments: fragments,
    );
    return '''${CodeGenerationConstants.generatedFileWarning}
// Operation: $operationName (${operation.type.name})
${sourcePath == null ? '' : '// Source: $sourcePath\n'}${CodeGenerationConstants.ignoreForFile}${scalarImports.isEmpty ? '' : ', unused_import'}

import 'package:graphql/client.dart' as graphql;
import 'types.dart';
$scalarImports
$body''';
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
  }) {
    final operationDoc = gql_lang.parseString(operationDocumentContent);
    final operation = _findOperation(operationDoc, operationName);
    final allFragments = {
      ...fragments,
      ...DocumentUtils.collectFragments([operationDoc]),
    };

    final schema = DocumentUtils.mergeSchemaExtensions(schemaDoc);
    SchemaAnalyzer.extractCustomTypesAndEnums(schema);
    if (CodegenConfigContext.validateDocuments) {
      DocumentValidator(schema).check(operation, allFragments);
    }

    final context = _OperationContext(
      name: operationName,
      operation: operation,
      schema: schema,
      definedTypes: definedTypes,
      strict: CodegenConfigContext.strictNullability,
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

    buffer.writeln(_generateParser(context));
    buffer.writeln(_generateOptions(context));
    buffer.write(_generateExtension(context));
    return buffer.toString();
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

  static String _generateVariablesClass(_OperationContext ctx) {
    final defs = ctx.operation.variableDefinitions;
    if (defs.isEmpty) return '';

    final className = '${ctx.pascal}Variables';
    final buffer = StringBuffer()
      ..writeln(
          '/// Variables for the `${ctx.name}` ${ctx.operation.type.name}.')
      ..writeln('///')
      ..writeln('/// Pass `toJson()` as the `variables` argument of the '
          'generated methods.')
      ..writeln('class $className {')
      ..writeln('  const $className({');

    final fields = [
      for (final d in defs)
        (
          graphqlName: d.variable.name.value,
          dartName: dartFieldName(d.variable.name.value, className: className),
          type: d.type,
          optional: !d.type.isNonNull || d.defaultValue?.value != null,
        ),
    ];

    for (final f in fields) {
      buffer.writeln(f.optional
          ? '    this.${f.dartName},'
          : '    required this.${f.dartName},');
    }
    buffer
      ..writeln('  });')
      ..writeln();

    for (final f in fields) {
      final type = _inputDartType(f.type, forceNullable: f.optional);
      buffer.writeln('  final $type ${f.dartName};');
    }

    buffer
      ..writeln()
      ..writeln('  Map<String, dynamic> toJson() => <String, dynamic>{');
    for (final f in fields) {
      if (f.optional) {
        var expr = _toJsonExpr(f.type, '${f.dartName}!');
        if (expr == '${f.dartName}!') expr = f.dartName;
        buffer.writeln("        if (${f.dartName} != null) "
            "'${f.graphqlName}': $expr,");
      } else {
        buffer.writeln("        '${f.graphqlName}': "
            "${_toJsonExpr(f.type, f.dartName)},");
      }
    }
    buffer
      ..writeln('      };')
      ..writeln('}');
    return buffer.toString();
  }

  /// Dart type of an input value, respecting the schema's nullability.
  static String _inputDartType(TypeNode type, {bool forceNullable = false}) {
    final nullable = forceNullable || !type.isNonNull;
    final base = type is ListTypeNode
        ? 'List<${_inputDartType(type.type)}>'
        : _namedDartType((type as NamedTypeNode).name.value);
    return _nullable(base, nullable);
  }

  /// Expression serialising the non-null value [v] of GraphQL [type].
  static String _toJsonExpr(TypeNode type, String v) {
    if (type is ListTypeNode) {
      final inner = type.type;
      final item = _toJsonExpr(inner, 'e');
      if (item == 'e') return v;
      final itemExpr = inner.isNonNull ? item : '(e == null ? null : $item)';
      return '$v.map((e) => $itemExpr).toList()';
    }

    final name = (type as NamedTypeNode).name.value;
    final mapped = CodegenConfigContext.scalarMapping[name];
    if (mapped != null) {
      final converter = CodegenConfigContext.scalarConverters[name];
      if (converter != null) return 'const $converter().toJson($v)';
      if (mapped == 'DateTime') return 'const DateTimeConverter().toJson($v)';
      return _isJsonNative(mapped) ? v : '$v.toJson()';
    }
    // A schema type named like a built-in scalar (e.g. `type Decimal`) is
    // handled as the type the generator declares for it.
    switch (TypeRegistry.declaresType(name) ? '' : name) {
      case 'Int':
      case 'Float':
      case 'String':
      case 'Boolean':
      case 'ID':
      case 'Short':
        return v;
      case 'DateTime':
        return 'const DateTimeConverter().toJson($v)';
      case 'LocalDate':
        return 'const LocalDateConverter().toJson($v)';
      case 'Decimal':
        return 'const SafeDecimalConverter().toJson($v)';
      case 'Long':
        return 'const LongConverter().toJson($v)';
      case 'Byte':
        return 'const ByteConverter().toJson($v)';
    }
    if (TypeRegistry.isEnum(name) || TypeRegistry.isCustomScalar(name)) {
      return 'const ${SchemaAnalyzer.dartTypeName(name)}Converter().toJson($v)';
    }
    if (TypeRegistry.inputTypes.contains(name)) return '$v.toJson()';
    return v;
  }

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
  Stream<$resultType> $camel($vars) {
    return subscribe(
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
  Stream<${ctx.returnType}> ${camel}Data($vars) {
    return $camel(variables)
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
  Future<$resultType> $camel($vars) async {
    final result = await $method(
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
  Future<${ctx.returnType}> ${camel}Data($vars) async {
    final result = await $camel(variables);
    return $parse(result.data);
  }
${isMutation ? '' : _generateCacheHelpers(ctx)}}
''';
  }

  // ---------------------------------------------------------------------------
  // Typed options and cache helpers
  // ---------------------------------------------------------------------------

  /// Top-level functions building `package:graphql` options whose
  /// `parserFn` is the generated parser, so `QueryResult.parsedData` (and
  /// `ObservableQuery` results) are typed.
  static String _generateOptions(_OperationContext ctx) {
    final common = [
      ('graphql.FetchPolicy? fetchPolicy', 'fetchPolicy: fetchPolicy'),
      ('graphql.ErrorPolicy? errorPolicy', 'errorPolicy: errorPolicy'),
      (
        'graphql.CacheRereadPolicy? cacheRereadPolicy',
        'cacheRereadPolicy: cacheRereadPolicy'
      ),
      ('graphql.Context? context', 'context: context'),
      ('Object? optimisticResult', 'optimisticResult: optimisticResult'),
    ];
    const poll = ('Duration? pollInterval', 'pollInterval: pollInterval');
    final t = ctx.returnType;
    final buffer = StringBuffer();
    switch (ctx.operation.type) {
      case OperationType.query:
        buffer
          ..writeln(_optionsFunction(ctx, 'QueryOptions', 'Query',
              'GraphQLClient.query', [...common, poll]))
          ..write(_optionsFunction(ctx, 'WatchQueryOptions', 'WatchQuery',
              'GraphQLClient.watchQuery', [
            ...common,
            poll,
            ('bool fetchResults = false', 'fetchResults: fetchResults'),
            (
              'bool carryForwardDataOnException = true',
              'carryForwardDataOnException: carryForwardDataOnException'
            ),
            (
              'bool? eagerlyFetchResults',
              'eagerlyFetchResults: eagerlyFetchResults'
            ),
          ]));
      case OperationType.mutation:
        buffer.write(_optionsFunction(
            ctx, 'MutationOptions', 'Mutation', 'GraphQLClient.mutate', [
          ...common,
          ('graphql.OnMutationUpdate<$t>? update', 'update: update'),
          (
            'graphql.OnMutationCompleted? onCompleted',
            'onCompleted: onCompleted'
          ),
          ('graphql.OnError? onError', 'onError: onError'),
        ]));
      case OperationType.subscription:
        buffer.write(_optionsFunction(ctx, 'SubscriptionOptions',
            'Subscription', 'GraphQLClient.subscribe', common));
    }
    return buffer.toString();
  }

  static String _optionsFunction(
    _OperationContext ctx,
    String optionsClass,
    String suffix,
    String clientMethod,
    List<(String, String)> params,
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
    for (final (param, _) in params) {
      buffer.writeln('  $param,');
    }
    buffer
      ..writeln('}) =>')
      ..writeln('    graphql.$optionsClass<$t>(')
      ..writeln('    document: ${ctx.camel}Document,')
      ..writeln('    operationName: ${ctx.camel}OperationName,')
      ..writeln('    variables: ${ctx.variablesJson},');
    for (final (_, arg) in params) {
      buffer.writeln('    $arg,');
    }
    buffer
      ..writeln('    parserFn: parse${ctx.pascal}Data,')
      ..writeln('  );');
    return buffer.toString();
  }

  /// `read*` / `write*` methods for the normalized cache of a query.
  static String _generateCacheHelpers(_OperationContext ctx) {
    final vars = '${ctx.pascal}Variables';
    final t =
        ctx.returnType.endsWith('?') ? ctx.returnType : '${ctx.returnType}?';
    final options = '${ctx.camel}QueryOptions';
    final (readParams, writeParams, args) = switch (ctx.variablesKind) {
      _VariablesKind.required => (
          '$vars variables, {bool optimistic = true}',
          '$vars variables, Map<String, dynamic> data, '
              '{bool broadcast = true}',
          'variables',
        ),
      _VariablesKind.optional => (
          '{$vars? variables, bool optimistic = true}',
          'Map<String, dynamic> data, '
              '{$vars? variables, bool broadcast = true}',
          'variables: variables',
        ),
      _VariablesKind.none => (
          '{bool optimistic = true}',
          'Map<String, dynamic> data, {bool broadcast = true}',
          '',
        ),
    };
    return '''

  /// Reads `${ctx.name}` from the cache; null when it isn't cached.
  $t read${ctx.pascal}($readParams) {
    final Map<String, dynamic>? data =
        readQuery($options($args).asRequest, optimistic: optimistic);
    return data == null ? null : parse${ctx.pascal}Data(data);
  }

  /// Writes raw `data` for `${ctx.name}` into the cache, shaped as the server
  /// returns it, including `__typename` on every object (also the root).
  void write${ctx.pascal}($writeParams) {
    writeQuery($options($args).asRequest, data: data, broadcast: broadcast);
  }
''';
  }

  // ---------------------------------------------------------------------------
  // Type helpers
  // ---------------------------------------------------------------------------

  /// Dart type for a GraphQL output type. In legacy (non-strict) mode every
  /// level is nullable, matching previous releases.
  static String _outputDartType(TypeNode type,
      {required bool legacy, bool forceNullable = false}) {
    final nullable = forceNullable || legacy || !type.isNonNull;
    final base = type is ListTypeNode
        ? 'List<${_outputDartType(type.type, legacy: legacy)}>'
        : _namedDartType((type as NamedTypeNode).name.value);
    return _nullable(base, nullable);
  }

  static String _namedDartType(String name) {
    final known = CodegenConfigContext.scalarMapping.containsKey(name) ||
        GraphQLConstants.scalarToDartType.containsKey(name) ||
        const {'Decimal', 'Long', 'Byte'}.contains(name) ||
        TypeRegistry.isEnum(name) ||
        TypeRegistry.isCustomScalar(name) ||
        TypeRegistry.objectTypes.contains(name) ||
        TypeRegistry.isAbstract(name) ||
        TypeRegistry.inputTypes.contains(name);
    if (!known) return 'dynamic';
    return SchemaAnalyzer.getDartType(
        NamedTypeNode(name: NameNode(value: name), isNonNull: true));
  }

  /// Dart types a JSON value can be used as directly.
  static bool _isJsonNative(String type) =>
      const {'String', 'int', 'double', 'num', 'bool', 'Object', 'dynamic'}
          .contains(type.replaceAll('?', '')) ||
      type.startsWith('Map<') ||
      type.startsWith('List<');

  static String _nullable(String type, bool nullable) =>
      nullable && type != 'dynamic' ? '$type?' : type;

  /// Expression converting the JSON value [v] into the Dart value of [type].
  static String _fromJsonExpr(TypeNode type, String v,
      {required bool legacy,
      required Set<String> definedTypes,
      bool forceNullable = false}) {
    final nullable = forceNullable || legacy || !type.isNonNull;
    final String inner;
    if (type is ListTypeNode) {
      final item = _fromJsonExpr(type.type, 'e',
          legacy: legacy, definedTypes: definedTypes);
      inner = '($v as List<dynamic>).map((e) => $item).toList()';
    } else {
      inner =
          _namedFromJson((type as NamedTypeNode).name.value, v, definedTypes);
    }
    return nullable ? '($v == null ? null : $inner)' : inner;
  }

  static String _namedFromJson(
      String name, String v, Set<String> definedTypes) {
    final mapped = CodegenConfigContext.scalarMapping[name];
    if (mapped != null) {
      final converter = CodegenConfigContext.scalarConverters[name];
      if (converter != null) return 'const $converter().fromJson($v)';
      switch (mapped) {
        case 'int':
          return 'const SafeIntConverter().fromJson($v)';
        case 'double':
          return 'const SafeDoubleConverter().fromJson($v)';
        case 'bool':
          return 'const SafeBoolConverter().fromJson($v)';
        case 'String':
          return 'const SafeStringConverter().fromJson($v)';
        case 'DateTime':
          return 'const DateTimeConverter().fromJson($v)';
        default:
          return _isJsonNative(mapped)
              ? '$v as $mapped'
              : '$mapped.fromJson($v)';
      }
    }
    // A schema type named like a built-in scalar (e.g. `type Decimal`) is
    // handled as the type the generator declares for it.
    switch (TypeRegistry.declaresType(name) ? '' : name) {
      case 'Int':
      case 'Short':
        return 'const SafeIntConverter().fromJson($v)';
      case 'Float':
        return 'const SafeDoubleConverter().fromJson($v)';
      case 'Boolean':
        return 'const SafeBoolConverter().fromJson($v)';
      case 'String':
      case 'ID':
        return 'const SafeStringConverter().fromJson($v)';
      case 'DateTime':
        return 'const DateTimeConverter().fromJson($v)';
      case 'LocalDate':
        return 'const LocalDateConverter().fromJson($v)';
      case 'Decimal':
        return 'const SafeDecimalConverter().fromJson($v)';
      case 'Long':
        return 'const LongConverter().fromJson($v)';
      case 'Byte':
        return 'const ByteConverter().fromJson($v)';
    }
    final dartName = SchemaAnalyzer.dartTypeName(name);
    if (TypeRegistry.isEnum(name)) {
      return 'const ${dartName}Converter().fromJson($v as String)';
    }
    if (TypeRegistry.isCustomScalar(name)) {
      return 'const ${dartName}Converter().fromJson($v)';
    }
    if (TypeRegistry.objectTypes.contains(name) ||
        TypeRegistry.isAbstract(name) ||
        definedTypes.contains(name)) {
      return '$dartName.fromJson($v as Map<String, dynamic>)';
    }
    return v;
  }

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
  late final List<_RootField> rootFields;

  _OperationContext({
    required this.name,
    required this.operation,
    required DocumentNode schema,
    required Set<String> definedTypes,
    required this.strict,
  })  : camel = name.toCamelCase(),
        pascal = name.capitalize() {
    final rootType = _rootType(schema);
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
      ClientExtensionGenerator._outputDartType(type,
          legacy: !strict, forceNullable: conditional),
      (v) => ClientExtensionGenerator._fromJsonExpr(type, v,
          legacy: !strict,
          definedTypes: definedTypes,
          forceNullable: conditional),
    );
  }
}
