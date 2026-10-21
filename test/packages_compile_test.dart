// Several packages in one repository, end to end: a shared package with the
// schema and common fragments, and a feature package using its types and
// fragments (types_import, fragment_imports). Both are built with the real
// builder through build_runner, analyzed and run.
//
// Slow; skip locally with `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 8))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _schema = r'''
enum Role { ADMIN EDITOR }

input UserFilter { role: Role, name: String }

type User { id: ID! name: String! role: Role! friend: User }

type Query {
  user(id: ID!): User
  users(filter: UserFilter): [User!]!
}
''';

const _sharedDocuments = {
  'lib/graphql/fragments.graphql': 'fragment UserBits on User { id name role }',
  'lib/graphql/shared_users.graphql': r'''
query SharedUsers($filter: UserFilter) { users(filter: $filter) { ...UserBits } }
''',
};

const _featureDocuments = {
  'lib/graphql/fragments.graphql': '''
fragment UserCard on User { ...UserBits friend { ...UserBits } }
''',
  'lib/graphql/users.graphql': r'''
query FeatureUsers($filter: UserFilter) { users(filter: $filter) { ...UserBits } }
query FeatureUser($id: ID!) { user(id: $id) { ...UserCard } }
''',
};

const _featureMain = r'''
import 'package:feature/graphql/generated/index.dart';
// The app may import both packages' code: shared libraries are exported by
// both indexes without conflicts.
import 'package:shared/graphql/generated/index.dart';
import 'package:graphql/client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

/// Takes the shared fragment interface.
String label(UserBits user) => '${user.id}:${user.name}:${user.role.name}';

const ann = {'__typename': 'User', 'id': '1', 'name': 'Ann', 'role': 'ADMIN'};
const bob = {'__typename': 'User', 'id': '2', 'name': 'Bob', 'role': 'EDITOR'};

class FakeLink extends Link {
  final requests = <Request>[];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    requests.add(request);
    yield Response(data: {
      '__typename': 'Query',
      'users': [ann, bob],
    }, response: const {});
  }
}

Future<void> main() async {
  // Variables of a feature operation use the shared input and enum types.
  const variables = FeatureUsersVariables(
      filter: UserFilter(role: Role.ADMIN, name: 'A'));
  final json = variables.toJson();
  check((json['filter'] as Map)['role'] == 'ADMIN', 'shared enum in input');

  // Feature and shared results both implement the shared interface.
  final featureUsers = parseFeatureUsersData({'users': [ann, bob]});
  final sharedUsers = parseSharedUsersData({'users': [bob]});
  final all = <UserBits>[...featureUsers, ...sharedUsers];
  check(all.map(label).join(',') == '1:Ann:ADMIN,2:Bob:EDITOR,2:Bob:EDITOR',
      'shared fragment interface');
  check(featureUsers.first.role == Role.ADMIN, 'shared enum in result');

  // A local fragment spreading the shared one.
  final user = parseFeatureUserData({
    'user': {...ann, 'friend': bob},
  })!;
  final UserCard card = user;
  check(label(card) == '1:Ann:ADMIN', 'local fragment implements shared');
  check(label(card.friend!) == '2:Bob:EDITOR', 'nested shared interface');

  // The document carries the shared fragment's definition.
  final link = FakeLink();
  final client = GraphQLClient(link: link, cache: GraphQLCache());
  final fetched = await client.featureUsersData(variables.toJson());
  check(fetched.length == 2 && fetched.last.name == 'Bob', 'typed fetch');
  final document = link.requests.single.operation.document;
  check(
      document.definitions.length == 2 &&
          featureUserDocument.definitions.length == 3,
      'fragment definitions in the documents');

  // Shared fragment cache helpers accept feature results.
  client.writeUserBitsFragment({'id': '1'}, featureUsers.first);
  final cached = client.readUserBitsFragment({'id': '1'});
  check(cached != null && label(cached) == '1:Ann:ADMIN', 'shared cache API');
  print('ok');
}
''';

void main() {
  test('a feature package uses the types and fragments of a shared package',
      () async {
    final root = await Directory.systemTemp.createTemp('fgc_packages_');
    final log = StringBuffer();
    final sdk = Platform.version.split(' ').first.split('.');
    final codegen = Directory.current.path;

    void write(String dir, String path, String content) {
      final file = File(p.join(root.path, dir, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    String pubspec(String name, String extraDependencies) => '''
name: $name
publish_to: none
environment:
  sdk: ^${sdk[0]}.${sdk[1]}.0
dependencies:
  graphql: ^5.1.3
  json_annotation: ^4.8.1
$extraDependencies
dev_dependencies:
  build_runner: ^2.4.6
  flutter_graphql_codegen:
    path: "${codegen.replaceAll(r'\', '/')}"
''';

    write('shared', 'pubspec.yaml', pubspec('shared', ''));
    write('shared', 'analysis_options.yaml', '');
    write('shared', 'lib/graphql/schema.graphql', _schema);
    write('shared', 'graphql_codegen.yaml', '''
schema_url: lib/graphql/schema.graphql
document_paths: [lib/graphql/**.graphql]
output_dir: lib/graphql/generated
strict_nullability: true
''');
    _sharedDocuments.forEach((path, text) => write('shared', path, text));

    write('feature', 'pubspec.yaml', pubspec('feature', '''
  shared:
    path: ../shared'''));
    write('feature', 'analysis_options.yaml', '');
    write('feature', 'graphql_codegen.yaml', '''
schema_url: package:shared/graphql/schema.graphql
document_paths: [lib/graphql/**.graphql]
output_dir: lib/graphql/generated
strict_nullability: true
types_import: package:shared/graphql/generated/types.dart
fragment_imports:
  - dart: package:shared/graphql/generated/fragments.dart
    documents: "package:shared/graphql/**.graphql"
''');
    _featureDocuments.forEach((path, text) => write('feature', path, text));
    write('feature', 'bin/main.dart', _featureMain);

    final errors = <String>[];
    Future<bool> run(String dir, List<String> args,
        {bool mayFail = false}) async {
      final r = await Process.run(Platform.resolvedExecutable, args,
          workingDirectory: p.join(root.path, dir));
      log
        ..writeln('\$ ($dir) dart ${args.join(' ')} (exit ${r.exitCode})')
        ..writeln(r.stdout)
        ..writeln(r.stderr);
      if (args.first == 'analyze') {
        final issue = RegExp(r'^(?:info|warning) - (\S+?):\d+');
        for (final line in '${r.stdout}'.split('\n').map((l) => l.trim())) {
          final path = issue.firstMatch(line)?.group(1)?.replaceAll(r'\', '/');
          if (line.startsWith('error -') ||
              (path != null && path.startsWith('lib/'))) {
            errors.add('$dir: $line');
          }
        }
        return true;
      }
      if (r.exitCode != 0 && !mayFail) {
        errors.add('$dir: dart ${args.join(' ')} failed');
      }
      return r.exitCode == 0;
    }

    Future<bool> pubGet(String dir) async =>
        await run(dir, ['pub', 'get', '--offline'], mayFail: true) ||
        await run(dir, ['pub', 'get']);

    const build = [
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs'
    ];
    final ok = await pubGet('shared') &&
        await run('shared', build) &&
        await pubGet('feature') &&
        await run('feature', build) &&
        await run('shared', ['analyze', '--no-fatal-warnings', '.']) &&
        await run('feature', ['analyze', '--no-fatal-warnings', '.']);
    if (ok && errors.isEmpty) await run('feature', ['run', 'bin/main.dart']);

    String? generated(String dir, String name) {
      final file = File(p.join(root.path, dir, 'lib/graphql/generated', name));
      return file.existsSync() ? file.readAsStringSync() : null;
    }

    expect(errors, isEmpty, reason: '$log');
    expect('$log', contains('(feature) dart run bin/main.dart (exit 0)'));
    expect(generated('feature', 'types.dart'), isNull);
    final fragments = generated('feature', 'fragments.dart')!;
    expect(fragments, contains('abstract interface class UserCard'));
    expect(fragments, isNot(contains('abstract interface class UserBits')));
    expect(generated('shared', 'fragments.dart'),
        contains('abstract interface class UserBits'));
    await root.delete(recursive: true);
  });
}
