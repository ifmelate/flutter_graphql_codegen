/// Client extension generation utilities for GraphQL code generation
library;

import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'code_utils.dart';
import 'config_context.dart';
import 'diagnostics.dart';
import 'document_utils.dart';
import 'document_validator.dart';
import 'json_exprs.dart';
import 'naming.dart';
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
    final (body, usesFragments) = _generate(
      operationName,
      operationDocumentContent,
      schemaDoc,
      definedTypes,
      fragments: fragments,
    );
    final ignores = CodegenConfigContext.operationResultTypes
        ? 'unused_import, deprecated_member_use_from_same_package'
        : 'unused_import';
    return '''${CodeGenerationConstants.generatedFileWarning}
// Operation: $operationName (${operation.type.name})
${sourcePath == null ? '' : '// Source: $sourcePath\n'}${CodeGenerationConstants.ignoreForFile}, $ignores

import 'package:graphql/client.dart' as graphql;
import 'package:normalize/utils.dart' as normalize;
${usesFragments ? "import 'fragments.dart';\n" : ''}import 'types.dart';
$scalarImports
$body''';
  }

  /// Generates `fragments.dart`: for every fragment its document, an
  /// interface with its fields (implemented by the operation classes that
  /// spread it) and a data class. Fragments on introspection types are left
  /// out. Returns null when no fragment is left.
  static String? generateFragmentsFile(
    DocumentNode schemaDoc,
    Map<String, FragmentDefinitionNode> fragments,
  ) {
    if (fragments.isEmpty) return null;
    final schema = DocumentUtils.mergeSchemaExtensions(schemaDoc);
    SchemaAnalyzer.extractCustomTypesAndEnums(schema);
    final types = OperationTypes(schema, fragments);
    if (types.fragmentNames.isEmpty) return null;
    types.checkFragments();

    final buffer = StringBuffer()
      ..writeln(CodeGenerationConstants.generatedFileWarning)
      ..writeln('// Fragments of all documents')
      ..writeln('${CodeGenerationConstants.ignoreForFile}, unused_import, '
          'deprecated_member_use_from_same_package')
      ..writeln()
      ..writeln("import 'package:graphql/client.dart' as graphql;")
      ..writeln("import 'types.dart';")
      ..write(TypeGenerator.scalarImportDirectives())
      ..writeln();
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
        ..write(types.fragmentData(name));
    }
    buffer.write(types.support);
    return buffer.toString();
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

  /// [generateClientExtension] plus whether the code uses `fragments.dart`.
  static (String, bool) _generate(
    String operationName,
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
      fragments: allFragments,
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
    return (buffer.toString(), classes?.usesFragments ?? false);
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
          // An explicit null would override the default on the server.
          hasDefault: d.defaultValue?.value != null,
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
      final type = JsonExprs.inputDartType(f.type, forceNullable: f.optional);
      buffer.writeln('  final $type ${f.dartName};');
    }

    buffer
      ..writeln()
      ..writeln('  Map<String, dynamic> toJson() => <String, dynamic>{');
    for (final f in fields) {
      if (f.optional) {
        var expr = JsonExprs.toJsonExpr(f.type, '${f.dartName}!');
        if (expr == '${f.dartName}!') expr = f.dartName;
        if (CodegenConfigContext.includeNullInputs && !f.hasDefault) {
          final value = expr == f.dartName
              ? expr
              : '${f.dartName} == null ? null : $expr';
          buffer.writeln("        '${f.graphqlName}': $value,");
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
      ..writeln('}');
    return buffer.toString();
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
    final classes = ctx.classes;
    final data = classes?.writeType ?? 'Map<String, dynamic>';
    final (readParams, writeParams, evictParams, args) =
        switch (ctx.variablesKind) {
      _VariablesKind.required => (
          '$vars variables, {bool optimistic = true}',
          '$vars variables, $data data, {bool broadcast = true}',
          '$vars variables',
          'variables',
        ),
      _VariablesKind.optional => (
          '{$vars? variables, bool optimistic = true}',
          '$data data, {$vars? variables, bool broadcast = true}',
          '{$vars? variables}',
          'variables: variables',
        ),
      _VariablesKind.none => (
          '{bool optimistic = true}',
          '$data data, {bool broadcast = true}',
          '',
          '',
        ),
    };
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
  })  : camel = name.toCamelCase(),
        pascal = name.capitalize() {
    final rootType = _rootType(schema);
    if (CodegenConfigContext.operationResultTypes) {
      rootFields = const [];
      classes = OperationTypes(schema, fragments)
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
