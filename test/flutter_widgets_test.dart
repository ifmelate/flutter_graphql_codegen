// Verifies the graphql_flutter widgets and hooks end to end: generated into
// a Flutter package, they must pass `flutter analyze`, and widget tests pump
// them with a GraphQLClient on a fake link (no network).
//
// Slow and needs the Flutter SDK on PATH (skipped otherwise). Part of the
// end-to-end tests (`dart test -t compile`); `-x flutter` leaves it out,
// `-t flutter` runs only it.
@Tags(['compile', 'flutter'])
@Timeout(Duration(minutes: 10))
library;

import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

import 'support/flutter_harness.dart';

const _schema = r'''
type User { id: ID! name: String }
type Query { user(id: ID!): User  version: String }
type Mutation { rename(id: ID!, name: String!): User  ping: Boolean }
type Subscription { userChanged(id: ID): User! }
''';

const _documents = [
  r'''
fragment UserFields on User { id name }

query GetUser($id: ID!) { user(id: $id) { ...UserFields } }
''',
  'query Version { version }',
  r'''
mutation Rename($id: ID!, $name: String!) {
  rename(id: $id, name: $name) { id name }
}
''',
  'mutation Ping { ping }',
  r'subscription UserChanged($id: ID) { userChanged(id: $id) { id name } }',
];

/// Generates types.dart, fragments.dart (operation result types), one file
/// per operation and `all.dart` exporting them into `lib/<dir>/`, with
/// widgets and hooks.
Map<String, String> _generate(String dir,
    {required String resultTypes, required bool strict}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.resultTypes = resultTypes;
  CodegenConfigContext.strictNullability = strict;
  CodegenConfigContext.flutterWidgets = true;
  CodegenConfigContext.flutterHooks = true;
  try {
    final types = TypeGenerator.generateTypesFile(_schema);
    final files = <String, String>{'lib/$dir/types.dart': types};
    final exports = ['types.dart'];
    final fragments =
        DocumentUtils.collectFragments(_documents.map(gql_lang.parseString));
    if (resultTypes == 'operation') {
      final code =
          GraphQLCodeGenerator.generateFragmentsFile(_schema, fragments);
      if (code != null) {
        files['lib/$dir/fragments.dart'] = code;
        exports.add('fragments.dart');
      }
    }
    for (final doc in _documents) {
      final ops = gql_lang
          .parseString(doc)
          .definitions
          .whereType<OperationDefinitionNode>();
      for (final op in ops) {
        final name = op.name!.value;
        files['lib/$dir/$name.g.dart'] =
            GraphQLCodeGenerator.generateOperationFile(
                _schema, doc, name, op.type.name, types,
                fragments: fragments);
        exports.add('$name.g.dart');
      }
    }
    files['lib/$dir/all.dart'] =
        exports.map((file) => "export '$file';\n").join();
    return files;
  } finally {
    CodegenConfigContext.reset();
  }
}

/// Widget tests of the generated code in `lib/<prefix>/`; [user],
/// [renamed] and [changed] are the result types of `GetUser`, `Rename` and
/// `UserChanged` there.
String _widgetTest(String prefix,
        {required String user,
        required String renamed,
        required String changed}) =>
    _widgetTestTemplate
        .replaceAll('USER_T', user)
        .replaceAll('RENAMED_T', renamed)
        .replaceAll('CHANGED_T', changed)
        .replaceAll('PFX', prefix);

const _widgetTestTemplate = r'''
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import 'package:fgc_flutter_check/PFX/all.dart' as PFX;

Map<String, dynamic> _user(Object? id, Object? name) =>
    {'__typename': 'User', 'id': id, 'name': name};

Response _response(Map<String, dynamic> data) =>
    Response(data: data, response: const {});

/// Answers operations with canned data and subscriptions with [events].
class FakeLink extends Link {
  final requests = <Request>[];
  final events = StreamController<Response>.broadcast();

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    requests.add(request);
    final variables = request.variables;
    switch (request.operation.operationName) {
      case 'GetUser':
        return Stream.value(_response(
            {'__typename': 'Query', 'user': _user(variables['id'], 'Ada')}));
      case 'Version':
        return Stream.value(
            _response({'__typename': 'Query', 'version': '1.2'}));
      case 'Rename':
        return Stream.value(_response({
          '__typename': 'Mutation',
          'rename': _user(variables['id'], variables['name']),
        }));
      case 'Ping':
        return Stream.value(
            _response({'__typename': 'Mutation', 'ping': true}));
      case 'UserChanged':
        return events.stream;
    }
    throw UnsupportedError(request.operation.operationName ?? 'anonymous');
  }
}

GraphQLClient _client(FakeLink link) =>
    GraphQLClient(link: link, cache: GraphQLCache());

Widget _app(GraphQLClient client, Widget child) => GraphQLProvider(
      client: ValueNotifier(client),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Disposes the widgets (closing their queries) and lets request timeouts
/// expire.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  // graphql_flutter's subscriptions listen to connectivity changes.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  testWidgets('Query widget builds with typed data', (tester) async {
    final link = FakeLink();
    final completed = <Map<String, dynamic>?>[];
    await tester.pumpWidget(_app(
      _client(link),
      PFX.GetUserQuery(
        variables: const PFX.GetUserVariables(id: '1'),
        onComplete: completed.add,
        builder: (result, {refetch, fetchMore}) {
          final USER_T? user = result.parsedData;
          return Text(user?.name ?? 'loading');
        },
      ),
    ));
    expect(find.text('loading'), findsOneWidget);
    await _settle(tester);
    expect(find.text('Ada'), findsOneWidget);
    expect(link.requests.single.variables, {'id': '1'});
    expect(completed, hasLength(1));
    await _unmount(tester);
  });

  testWidgets('Query widget runs on an explicit client', (tester) async {
    final link = FakeLink();
    final client = _client(link);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: PFX.VersionQuery(
        client: client,
        builder: (result, {refetch, fetchMore}) {
          final String? version = result.parsedData;
          return Text(version ?? 'loading');
        },
      ),
    ));
    await _settle(tester);
    expect(find.text('1.2'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('query hook returns typed data', (tester) async {
    final link = FakeLink();
    await tester.pumpWidget(_app(
      _client(link),
      HookBuilder(builder: (context) {
        final query = PFX.useGetUserQuery(const PFX.GetUserVariables(id: '2'));
        final USER_T? user = query.result.parsedData;
        return Text(user == null ? 'loading' : '${user.id}:${user.name}');
      }),
    ));
    await _settle(tester);
    expect(find.text('2:Ada'), findsOneWidget);
    // Rebuilds keep the same query.
    await tester.pump();
    await _settle(tester);
    expect(link.requests, hasLength(1));
    await _unmount(tester);
  });

  testWidgets('watch query hook streams typed results', (tester) async {
    final link = FakeLink();
    await tester.pumpWidget(_app(
      _client(link),
      HookBuilder(builder: (context) {
        final query = PFX.useGetUserWatchQuery(
            const PFX.GetUserVariables(id: '3'),
            fetchResults: true);
        final snapshot =
            useStream(query.stream, initialData: query.latestResult);
        final USER_T? user = snapshot.data?.parsedData;
        return Text(user?.id ?? 'loading');
      }),
    ));
    await _settle(tester);
    expect(find.text('3'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Mutation widget runs with typed variables', (tester) async {
    final link = FakeLink();
    final completed = <Map<String, dynamic>?>[];
    late PFX.RunRenameMutation rename;
    await tester.pumpWidget(_app(
      _client(link),
      PFX.RenameMutation(
        onCompleted: completed.add,
        builder: (runMutation, result) {
          rename = runMutation;
          final RENAMED_T? renamed = result?.parsedData;
          return Text(renamed?.name ?? 'idle');
        },
      ),
    ));
    expect(find.text('idle'), findsOneWidget);
    expect(link.requests, isEmpty);

    rename(const PFX.RenameVariables(id: '7', name: 'Bob'));
    await _settle(tester);
    expect(find.text('Bob'), findsOneWidget);
    expect(link.requests.single.variables, {'id': '7', 'name': 'Bob'});
    expect(completed, hasLength(1));
    await _unmount(tester);
  });

  testWidgets('mutation hooks run with typed variables', (tester) async {
    final link = FakeLink();
    late PFX.RunRenameMutation rename;
    late PFX.RunPingMutation ping;
    await tester.pumpWidget(_app(
      _client(link),
      HookBuilder(builder: (context) {
        final renameMutation = PFX.useRenameMutation();
        final pingMutation = PFX.usePingMutation();
        rename = renameMutation.runMutation;
        ping = pingMutation.runMutation;
        final RENAMED_T? renamed = renameMutation.result.parsedData;
        final bool? pong = pingMutation.result.parsedData;
        return Text('${renamed?.name ?? 'idle'} ${pong ?? 'idle'}');
      }),
    ));
    expect(find.text('idle idle'), findsOneWidget);

    rename(const PFX.RenameVariables(id: '8', name: 'Cy'));
    await _settle(tester);
    expect(find.text('Cy idle'), findsOneWidget);
    expect(link.requests.single.variables, {'id': '8', 'name': 'Cy'});

    ping();
    await _settle(tester);
    expect(find.text('Cy true'), findsOneWidget);
    expect(link.requests.last.variables, isEmpty);
    await _unmount(tester);
  });

  testWidgets('Subscription widget builds with typed events', (tester) async {
    final link = FakeLink();
    final seen = <CHANGED_T?>[];
    await tester.pumpWidget(_app(
      _client(link),
      PFX.UserChangedSubscription(
        variables: const PFX.UserChangedVariables(id: '5'),
        onSubscriptionResult: (result, client) => seen.add(result.parsedData),
        builder: (result) {
          final CHANGED_T? user = result.parsedData;
          return Text(user?.name ?? 'waiting');
        },
      ),
    ));
    await _settle(tester);
    expect(find.text('waiting'), findsOneWidget);
    expect(link.requests.single.variables, {'id': '5'});

    link.events.add(_response({
      '__typename': 'Subscription',
      'userChanged': _user('5', 'Eve'),
    }));
    await _settle(tester);
    expect(find.text('Eve'), findsOneWidget);
    expect(seen.map((user) => user?.name), contains('Eve'));
    await _unmount(tester);
  });

  testWidgets('subscription hook returns typed events', (tester) async {
    final link = FakeLink();
    await tester.pumpWidget(_app(
      _client(link),
      HookBuilder(builder: (context) {
        final result = PFX.useUserChangedSubscription();
        final CHANGED_T? user = result.parsedData;
        return Text(user?.name ?? 'waiting');
      }),
    ));
    await _settle(tester);
    expect(find.text('waiting'), findsOneWidget);
    expect(link.requests.single.variables, isEmpty);

    link.events.add(_response({
      '__typename': 'Subscription',
      'userChanged': _user('6', 'Fay'),
    }));
    await _settle(tester);
    expect(find.text('Fay'), findsOneWidget);
    link.events.add(_response({
      '__typename': 'Subscription',
      'userChanged': _user('6', 'Gus'),
    }));
    await _settle(tester);
    expect(find.text('Gus'), findsOneWidget);
    await _unmount(tester);
  });
}
''';

void main() {
  final flutter = findFlutter();

  test('generated widgets and hooks work in a Flutter app', () async {
    final files = {
      ..._generate('ops', resultTypes: 'operation', strict: true),
      // Only analyzed.
      ..._generate('ops_legacy', resultTypes: 'operation', strict: false),
      ..._generate('schema_ops', resultTypes: 'schema', strict: true),
      'test/ops_test.dart': _widgetTest('ops',
          user: 'ops.GetUser_User',
          renamed: 'ops.Rename_Rename',
          changed: 'ops.UserChanged_UserChanged'),
      'test/schema_ops_test.dart': _widgetTest('schema_ops',
          user: 'schema_ops.User',
          renamed: 'schema_ops.User',
          changed: 'schema_ops.User'),
    };
    final result =
        await testInFlutterPackage(flutter!, files, buildRunner: true);
    expect(result.errors, isEmpty, reason: result.log);
  }, skip: flutter == null ? 'flutter is not on PATH' : false);
}
