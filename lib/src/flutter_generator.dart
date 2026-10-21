/// graphql_flutter widgets and flutter_hooks hooks per operation
/// (`flutter_widgets` / `flutter_hooks`).
library;

import 'package:gql/ast.dart';

import 'client_extension_generator.dart' show OptionsParam;
import 'config_context.dart';
import 'diagnostics.dart';

/// Prefix of `package:graphql_flutter/graphql_flutter.dart` in op files.
const String graphqlFlutterPrefix = 'graphql_flutter';

/// Prefix of `package:flutter/widgets.dart` in op files.
const String widgetsPrefix = 'widgets';

/// Whether an operation has variables, and whether any is required.
enum OperationVariables { none, required, optional }

/// What [FlutterGenerator] needs to know about an operation.
class FlutterOperation {
  /// GraphQL name of the operation.
  final String name;
  final OperationType type;

  /// The operation name in PascalCase / camelCase.
  final String pascal;
  final String camel;

  /// `TParsed` of its options: the return type of `parse<Op>Data`.
  final String resultType;
  final OperationVariables variables;

  /// Parameters of the generated options functions by their suffix
  /// (`Query`, `WatchQuery`, `Mutation`, `Subscription`).
  final Map<String, List<OptionsParam>> optionsParams;

  /// Names declared by types.dart, which index.dart exports with the
  /// operation files.
  final Set<String> definedTypes;

  const FlutterOperation({
    required this.name,
    required this.type,
    required this.pascal,
    required this.camel,
    required this.resultType,
    required this.variables,
    required this.optionsParams,
    this.definedTypes = const {},
  });

  String get variablesClass => '${pascal}Variables';

  /// `Query`, `Mutation` or `Subscription`.
  String get kind => switch (type) {
        OperationType.query => 'Query',
        OperationType.mutation => 'Mutation',
        OperationType.subscription => 'Subscription',
      };

  /// [pascal] without a trailing [kind], so operation `GetUserQuery` gets
  /// widget `GetUserQuery` (not `GetUserQueryQuery`) like `GetUser` does.
  String get base => pascal.length > kind.length && pascal.endsWith(kind)
      ? pascal.substring(0, pascal.length - kind.length)
      : pascal;
}

/// Generates graphql_flutter widgets and hooks on top of the typed options
/// functions of an operation file.
class FlutterGenerator {
  /// Whether operation files get any Flutter code.
  static bool get enabled =>
      CodegenConfigContext.flutterWidgets || CodegenConfigContext.flutterHooks;

  /// Import directives operation files need for the Flutter code.
  static String imports() {
    if (!enabled) return '';
    final buffer = StringBuffer();
    if (CodegenConfigContext.flutterWidgets) {
      buffer
          .writeln("import 'package:flutter/widgets.dart' as $widgetsPrefix;");
    }
    buffer.writeln("import 'package:graphql_flutter/graphql_flutter.dart' "
        'as $graphqlFlutterPrefix;');
    return buffer.toString();
  }

  /// The widgets and hooks of [op] (empty when both options are off).
  static String generate(FlutterOperation op) {
    if (!enabled) return '';
    _checkNames(op);
    final widgets = CodegenConfigContext.flutterWidgets;
    final hooks = CodegenConfigContext.flutterHooks;
    final buffer = StringBuffer();
    switch (op.type) {
      case OperationType.query:
        if (widgets) buffer.writeln(_queryWidget(op));
        if (hooks) {
          buffer
            ..writeln(_queryHook(op))
            ..writeln(_watchQueryHook(op));
        }
      case OperationType.mutation:
        buffer.writeln(_runMutationTypedef(op));
        if (widgets) buffer.writeln(_mutationWidget(op));
        if (hooks) buffer.writeln(_mutationHook(op));
      case OperationType.subscription:
        if (widgets) buffer.writeln(_subscriptionWidget(op));
        if (hooks) buffer.writeln(_subscriptionHook(op));
    }
    return buffer.toString();
  }

  /// Name of the widget of [op]: `<Op>Query`, `<Op>Mutation` or
  /// `<Op>Subscription`.
  static String widgetName(FlutterOperation op) => '${op.base}${op.kind}';

  /// Name of the typed run function type of mutation [op].
  static String runMutationName(FlutterOperation op) => 'Run${op.base}Mutation';

  /// Classes and typedefs are exported by index.dart together with
  /// types.dart; a schema type of the same name would make that export
  /// ambiguous.
  static void _checkNames(FlutterOperation op) {
    final names = [
      if (CodegenConfigContext.flutterWidgets) widgetName(op),
      if (op.type == OperationType.mutation) runMutationName(op),
    ];
    for (final name in names) {
      if (op.definedTypes.contains(name)) {
        throw CodegenException(
          CodegenErrorCodes.buildDuplicateDeclaration,
          'Operation "${op.name}" generates the Flutter type "$name", which '
          'types.dart declares for the schema as well; rename the operation',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Shared pieces
  // ---------------------------------------------------------------------------

  static const _gf = graphqlFlutterPrefix;
  static const _w = widgetsPrefix;

  /// Parameters of the options function with [suffix] that the widgets and
  /// hooks take as well.
  static List<OptionsParam> _params(FlutterOperation op, String suffix,
          {Set<String> except = const {}}) =>
      [
        for (final p in op.optionsParams[suffix] ?? const <OptionsParam>[])
          if (!except.contains(p.name)) p,
      ];

  /// Parameter list of a hook: variables like the options function
  /// (positional when required), then [params].
  static String _hookParams(FlutterOperation op, List<OptionsParam> params,
      {List<String> extra = const []}) {
    final named = [
      if (op.variables == OperationVariables.optional)
        '${op.variablesClass}? variables',
      for (final p in params) p.declaration,
      ...extra,
    ];
    final buffer = StringBuffer();
    if (op.variables == OperationVariables.required) {
      buffer.write('\n  ${op.variablesClass} variables,');
      if (named.isNotEmpty) buffer.write(' {');
    } else if (named.isNotEmpty) {
      buffer.write('{');
    }
    if (named.isNotEmpty) {
      buffer.write('\n');
      for (final n in named) {
        buffer.writeln('  $n,');
      }
      buffer.write('}');
    } else if (op.variables == OperationVariables.required) {
      buffer.write('\n');
    }
    return buffer.toString();
  }

  /// Call of the options function with [suffix], passing the variables and
  /// [params] of the same names; [arg] maps a name to its argument
  /// expression (`this.context` in a widget's `build`).
  static String _optionsCall(
      FlutterOperation op, String suffix, List<OptionsParam> params,
      {String Function(String name)? arg, String indent = '    '}) {
    final value = arg ?? (String name) => name;
    final args = [
      if (op.variables == OperationVariables.required) value('variables'),
      if (op.variables == OperationVariables.optional)
        'variables: ${value('variables')}',
      for (final p in params) '${p.name}: ${value(p.name)}',
    ];
    final buffer = StringBuffer('${op.camel}${suffix}Options(');
    if (args.isNotEmpty) {
      buffer.write('\n');
      for (final a in args) {
        buffer.writeln('$indent  $a,');
      }
      buffer.write(indent);
    }
    buffer.write(')');
    return buffer.toString();
  }

  /// Constructor parameters and fields of a widget: variables (named,
  /// required when the operation requires them), then [params].
  static (String, String) _widgetMembers(FlutterOperation op,
      List<OptionsParam> params, List<(String, String, String)> extra,
      {bool variables = true}) {
    final ctor = StringBuffer();
    final fields = StringBuffer();
    if (variables) {
      switch (op.variables) {
        case OperationVariables.required:
          ctor.writeln('    required this.variables,');
          fields
            ..writeln('  /// Variables of the ${op.type.name}.')
            ..writeln('  final ${op.variablesClass} variables;')
            ..writeln();
        case OperationVariables.optional:
          ctor.writeln('    this.variables,');
          fields
            ..writeln('  /// Variables of the ${op.type.name}.')
            ..writeln('  final ${op.variablesClass}? variables;')
            ..writeln();
        case OperationVariables.none:
          break;
      }
    }
    for (final p in params) {
      ctor.writeln(p.defaultValue == null
          ? '    this.${p.name},'
          : '    this.${p.name} = ${p.defaultValue},');
      fields.writeln('  final ${p.type} ${p.name};');
    }
    if (params.isNotEmpty) fields.writeln();
    for (final (type, name, doc) in extra) {
      ctor.writeln(
          type.endsWith('?') ? '    this.$name,' : '    required this.$name,');
      fields
        ..writeln('  /// $doc')
        ..writeln('  final $type $name;')
        ..writeln();
    }
    return (ctor.toString(), fields.toString().trimRight());
  }

  static const _clientDoc = 'The client to run on; null for the client of '
      'the nearest `GraphQLProvider`.';

  /// `this.` for options parameters that a widget's `build` shadows.
  static String _member(String name) =>
      name == 'context' ? 'this.context' : name;

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  static String _queryWidget(FlutterOperation op) {
    final name = widgetName(op);
    final t = op.resultType;
    final params = _params(op, 'Query');
    final (ctor, fields) = _widgetMembers(op, params, [
      ('graphql.GraphQLClient?', 'client', _clientDoc),
      (
        '$_gf.QueryBuilder<$t>',
        'builder',
        'Builds the widget from the latest result; its `parsedData` is typed.'
      ),
    ]);
    return '''
/// Runs the `${op.name}` query with [$_gf.Query] and rebuilds with
/// every result; `result.parsedData` is typed.
class $name extends $_w.StatelessWidget {
  const $name({
    super.key,
$ctor  });

$fields

  @override
  $_w.Widget build($_w.BuildContext context) {
    final options = ${_optionsCall(op, 'Query', params, arg: _member)};
    final client = this.client;
    if (client == null) {
      return $_gf.Query<$t>(options: options, builder: builder);
    }
    return $_gf.QueryOnClient<$t>(
      client: client,
      options: options,
      builder: builder,
    );
  }
}
''';
  }

  static String _queryHook(FlutterOperation op) {
    final t = op.resultType;
    final params = _params(op, 'Query');
    return '''
/// Runs the `${op.name}` query with [$_gf.useQuery];
/// `result.parsedData` is typed.
$_gf.QueryHookResult<$t> use${op.base}Query(${_hookParams(op, params)}) {
  return $_gf.useQuery<$t>(${_optionsCall(op, 'Query', params, indent: '  ')});
}
''';
  }

  static String _watchQueryHook(FlutterOperation op) {
    final t = op.resultType;
    final params = _params(op, 'WatchQuery');
    return '''
/// Watches the `${op.name}` query with [$_gf.useWatchQuery]; the
/// results of the returned query are typed. Pass `fetchResults: true`
/// (or call `fetchResults()`) to run it.
graphql.ObservableQuery<$t> use${op.base}WatchQuery(${_hookParams(op, params)}) {
  return $_gf.useWatchQuery<$t>(${_optionsCall(op, 'WatchQuery', params, indent: '  ')});
}
''';
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// `optimisticResult` is given per run; `variables` too.
  static List<OptionsParam> _mutationParams(FlutterOperation op) =>
      _params(op, 'Mutation', except: const {'optimisticResult'});

  static String _runMutationTypedef(FlutterOperation op) {
    final t = op.resultType;
    final params = switch (op.variables) {
      OperationVariables.required =>
        '${op.variablesClass} variables, {Object? optimisticResult}',
      OperationVariables.optional =>
        '{${op.variablesClass}? variables, Object? optimisticResult}',
      OperationVariables.none => '{Object? optimisticResult}',
    };
    return '''
/// Runs the `${op.name}` mutation provided by `${widgetName(op)}` or
/// `use${op.base}Mutation` with typed variables.
typedef ${runMutationName(op)} = graphql.MultiSourceResult<$t> Function(
    $params);
''';
  }

  /// A typed run function calling graphql_flutter's [run].
  static String _typedRun(FlutterOperation op, String run) =>
      switch (op.variables) {
        OperationVariables.required => '(variables, {optimisticResult}) => '
            '$run(variables.toJson(), optimisticResult: optimisticResult)',
        OperationVariables.optional => '({variables, optimisticResult}) => '
            '$run(variables?.toJson() ?? const {}, '
            'optimisticResult: optimisticResult)',
        OperationVariables.none => '({optimisticResult}) => '
            '$run(const {}, optimisticResult: optimisticResult)',
      };

  /// `MutationOptions` without variables (they are passed per run).
  static String _mutationOptions(FlutterOperation op, List<OptionsParam> params,
      {String Function(String name)? arg, String indent = '    '}) {
    final value = arg ?? (String name) => name;
    final buffer = StringBuffer()
      ..writeln('graphql.MutationOptions<${op.resultType}>(')
      ..writeln('$indent  document: ${op.camel}Document,')
      ..writeln('$indent  operationName: ${op.camel}OperationName,');
    for (final p in params) {
      buffer.writeln('$indent  ${p.name}: ${value(p.name)},');
    }
    buffer
      ..writeln('$indent  parserFn: parse${op.pascal}Data,')
      ..write('$indent)');
    return buffer.toString();
  }

  static String _mutationWidget(FlutterOperation op) {
    final name = widgetName(op);
    final t = op.resultType;
    final run = runMutationName(op);
    final params = _mutationParams(op);
    final (ctor, fields) = _widgetMembers(
        op,
        params,
        [
          ('graphql.GraphQLClient?', 'client', _clientDoc),
          (
            '$_w.Widget Function($run runMutation, '
                'graphql.QueryResult<$t>? result)',
            'builder',
            'Builds the widget; [runMutation] runs the mutation, and '
                '`result.parsedData` is typed.'
          ),
        ],
        variables: false);
    return '''
/// Provides the `${op.name}` mutation with [$_gf.Mutation]: [builder]
/// gets a [$run] taking typed variables, and the latest result.
class $name extends $_w.StatelessWidget {
  const $name({
    super.key,
$ctor  });

$fields

  @override
  $_w.Widget build($_w.BuildContext context) {
    final options = ${_mutationOptions(op, params, arg: _member)};
    $_w.Widget typedBuilder(
      $_gf.RunMutation<$t> runMutation,
      graphql.QueryResult<$t>? result,
    ) =>
        builder(${_typedRun(op, 'runMutation')}, result);
    final client = this.client;
    if (client == null) {
      return $_gf.Mutation<$t>(options: options, builder: typedBuilder);
    }
    return $_gf.MutationOnClient<$t>(
      client: client,
      options: options,
      builder: typedBuilder,
    );
  }
}
''';
  }

  static String _mutationHook(FlutterOperation op) {
    final t = op.resultType;
    final run = runMutationName(op);
    final params = _mutationParams(op);
    final named = params.map((p) => '  ${p.declaration},\n').join();
    return '''
/// Provides the `${op.name}` mutation with [$_gf.useMutation]:
/// `runMutation` runs it with typed variables, and `result.parsedData` is
/// typed.
({$run runMutation, graphql.QueryResult<$t> result}) use${op.base}Mutation(${named.isEmpty ? '' : '{\n$named}'}) {
  final mutation = $_gf.useMutation<$t>(${_mutationOptions(op, params, indent: '  ')});
  return (
    runMutation: ${_typedRun(op, 'mutation.runMutation')},
    result: mutation.result,
  );
}
''';
  }

  // ---------------------------------------------------------------------------
  // Subscriptions
  // ---------------------------------------------------------------------------

  static String _subscriptionWidget(FlutterOperation op) {
    final name = widgetName(op);
    final t = op.resultType;
    final params = _params(op, 'Subscription');
    final (ctor, fields) = _widgetMembers(op, params, [
      (
        '$_gf.OnSubscriptionResult<$t>?',
        'onSubscriptionResult',
        'Called with every result.'
      ),
      ('graphql.GraphQLClient?', 'client', _clientDoc),
      (
        '$_gf.SubscriptionBuilder<$t>',
        'builder',
        'Builds the widget from the latest result; its `parsedData` is typed.'
      ),
    ]);
    return '''
/// Subscribes to `${op.name}` with [$_gf.Subscription] and rebuilds
/// with every result; `result.parsedData` is typed.
class $name extends $_w.StatelessWidget {
  const $name({
    super.key,
$ctor  });

$fields

  @override
  $_w.Widget build($_w.BuildContext context) {
    final options = ${_optionsCall(op, 'Subscription', params, arg: _member)};
    final client = this.client;
    if (client == null) {
      return $_gf.Subscription<$t>(
        options: options,
        builder: builder,
        onSubscriptionResult: onSubscriptionResult,
      );
    }
    return $_gf.SubscriptionOnClient<$t>(
      client: client,
      options: options,
      builder: builder,
      onSubscriptionResult: onSubscriptionResult,
    );
  }
}
''';
  }

  static String _subscriptionHook(FlutterOperation op) {
    final t = op.resultType;
    final params = _params(op, 'Subscription');
    return '''
/// Subscribes to `${op.name}` with [$_gf.useSubscription] and returns
/// the latest result; its `parsedData` is typed.
graphql.QueryResult<$t> use${op.base}Subscription(${_hookParams(op, params, extra: [
          '$_gf.OnSubscriptionResult<$t>? onSubscriptionResult'
        ])}) {
  return $_gf.useSubscription<$t>(
    ${_optionsCall(op, 'Subscription', params, indent: '    ')},
    onSubscriptionResult: onSubscriptionResult,
  );
}
''';
  }
}
