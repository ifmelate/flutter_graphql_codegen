import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:dart_style/dart_style.dart';
import 'package:flutter_graphql_codegen/src/builder.dart';
import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/operation_groups.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _schema = r'''
type Query { user(id: ID!): User  version: String users: [User!]! }
type Mutation { rename(id: ID!, name: String!): User }
type Subscription { renamed: User }
type User { id: ID! name: String }
''';

void main() {
  group('names', () {
    OperationGroup group(String path, {String naming = 'snake_case'}) =>
        OperationGroup.fromPath(path, fileNaming: naming);

    test('join the directories in camelCase', () {
      expect(group('users').name, 'users');
      expect(group('users').className, 'UsersOperations');
      expect(group('users').fileName, 'users_operations.dart');
      expect(group('users/admin').name, 'usersAdmin');
      expect(group('users/admin').className, 'UsersAdminOperations');
      expect(group('user-profiles').name, 'userProfiles');
      expect(group('user_profiles/Settings').name, 'userProfilesSettings');
      expect(group('API/keys').name, 'apiKeys');
      expect(group('2fa').name, 'group2fa');
      expect(group('2fa').className, 'Group2faOperations');
      expect(group('users/admin', naming: 'kebab-case').fileName,
          'users-admin-operations.dart');
    });

    test('getters avoid reserved words and taken names', () {
      expect(group('class').getterName(const {}), 'class_');
      expect(group('query').getterName(const {'query'}), 'query_');
      expect(group('users').getterName(const {'users', 'users_'}), 'users__');
      expect(group('users').getterName(const {'usersData'}), 'users');
    });

    test('documents directly in the root have no group', () {
      expect(
          OperationGroup.forDocument('lib/gql/a.graphql', 'lib/gql',
              fileNaming: 'snake_case'),
          isNull);
      expect(
          OperationGroup.forDocument('lib/other/a.graphql', 'lib/gql',
              fileNaming: 'snake_case'),
          isNull);
      expect(
          OperationGroup.forDocument('lib/gql/users/admin/a.graphql', 'lib/gql',
                  fileNaming: 'snake_case')!
              .path,
          'users/admin');
    });

    test('the root is the common literal part of the globs', () {
      expect(documentsRoot(['lib/graphql/documents/**/*.graphql']),
          'lib/graphql/documents');
      expect(documentsRoot(['lib/graphql/**.graphql']), 'lib/graphql');
      expect(documentsRoot(['lib/a/**.graphql', 'lib/b/*.graphql']), 'lib');
      expect(documentsRoot(['lib/a/x.graphql']), 'lib/a');
      expect(documentsRoot(['**.graphql']), '.');
      expect(documentsRoot(const []), isNull);
    });
  });

  group('builder', () {
    late Directory outDir;
    late List<String> logs;

    setUp(() async {
      CodegenConfigContext.reset();
      CodegenConfigContext.groupOperations = 'directory';
      outDir = await Directory.systemTemp.createTemp('fgc_groups_');
      logs = [];
    });

    tearDown(() async {
      CodegenConfigContext.reset();
      await outDir.delete(recursive: true);
    });

    Future<void> run(Map<String, String> assets,
        {String fileNaming = 'snake_case'}) async {
      try {
        await testBuilder(
          GraphQLCodegenBuilder(GraphQLCodegenConfig(
            schemaUrl: 'lib/schema.graphql',
            outputDir: outDir.path,
            documentPaths: ['lib/graphql/**.graphql'],
            fileNaming: fileNaming,
          )),
          {'a|lib/schema.graphql': _schema, ...assets},
          rootPackage: 'a',
          onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
        );
      } on CodegenException {
        // Logged as SEVERE as well.
      }
    }

    String? output(String name) {
      final file = File(p.join(outDir.path, name));
      return file.existsSync() ? file.readAsStringSync() : null;
    }

    Iterable<String> severe() => logs.where((l) => l.startsWith('SEVERE'));

    test('groups operations by directory', () async {
      await run({
        'a|lib/graphql/users/get_user.graphql': r'''
query GetUser($id: ID!) { user(id: $id) { id name } }
mutation Rename($id: ID!, $name: String!) { rename(id: $id, name: $name) { id } }
''',
        'a|lib/graphql/users/admin/renamed.graphql':
            'subscription Renamed { renamed { id } }',
        'a|lib/graphql/version.graphql': 'query GetVersion { version }',
      });
      expect(severe(), isEmpty);

      final users = output('users_operations.dart')!;
      expect(users, contains('// Operations of group: users'));
      expect(users, contains('final class UsersOperations {'));
      expect(users,
          contains('UsersOperations get users => UsersOperations(this);'));
      expect(users, contains("export 'get_user_graphql.g.dart';"));
      expect(users, contains("export 'rename_graphql.g.dart';"));
      expect(users, isNot(contains('renamed_graphql')));

      final getUser = output('get_user_graphql.g.dart')!;
      expect(getUser, contains('// Operation group: users'));
      expect(getUser, contains("import 'users_operations.dart';"));
      expect(
          getUser, contains('extension GetUserInGroup on UsersOperations {'));
      expect(getUser, contains('client.getUserData(variables)'));
      expect(getUser,
          contains('client.readGetUser(variables, optimistic: optimistic)'));
      expect(getUser, contains('client.evictGetUser(variables)'));
      final rename = output('rename_graphql.g.dart')!;
      expect(rename, contains('extension RenameInGroup on UsersOperations {'));
      expect(rename, isNot(contains('readRename')));

      final admin = output('users_admin_operations.dart')!;
      expect(admin, contains('UsersAdminOperations get usersAdmin =>'));
      expect(
          output('renamed_graphql.g.dart'),
          contains(
              'Stream<graphql.QueryResult<Map<String, dynamic>>> renamed('));

      // Root documents are not grouped.
      final version = output('get_version_graphql.g.dart')!;
      expect(version, isNot(contains('InGroup')));
      expect(version, isNot(contains('Operation group')));

      final index = output('index.dart')!;
      expect(index, contains("export 'users_operations.dart';"));
      expect(index, contains("export 'users_admin_operations.dart';"));

      final formatter =
          DartFormatter(languageVersion: DartFormatter.latestLanguageVersion);
      for (final name in ['users_operations.dart', 'get_user_graphql.g.dart']) {
        final code = output(name)!;
        expect(formatter.format(code), code, reason: '$name is not formatted');
      }
    });

    test('follow the file naming', () async {
      await run({
        'a|lib/graphql/users/get_user.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { id } }',
      }, fileNaming: 'kebab-case');
      expect(severe(), isEmpty);
      expect(output('users-operations.dart'), isNotNull);
      expect(output('get-user_graphql.g.dart'),
          contains("import 'users-operations.dart';"));
    });

    test('getters clashing with client members or operations are escaped',
        () async {
      await run({
        'a|lib/graphql/query/a.graphql': 'query GetVersion { version }',
        'a|lib/graphql/users/b.graphql': 'query Users { users { id } }',
        'a|lib/graphql/class/c.graphql': 'query Client { version }',
      });
      expect(severe(), isEmpty);
      expect(output('query_operations.dart'),
          contains('QueryOperations get query_ =>'));
      expect(output('users_operations.dart'),
          contains('UsersOperations get users_ =>'));
      expect(output('class_operations.dart'),
          contains('ClassOperations get class_ =>'));
      // The group class has a `client` field. Compared without whitespace:
      // line breaks depend on the dart_style version.
      expect(
          output('client_graphql.g.dart')!.replaceAll(RegExp(r'\s+'), ''),
          contains('>client_([Map<String,dynamic>?variables,])=>'
              'client.client(variables);'));
    });

    test('are off by default', () async {
      CodegenConfigContext.groupOperations = 'none';
      await run({
        'a|lib/graphql/users/get_user.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { id } }',
      });
      expect(output('users_operations.dart'), isNull);
      expect(output('get_user_graphql.g.dart'), isNot(contains('InGroup')));
      expect(output('index.dart'), isNot(contains('operations.dart')));
    });

    test('files of groups without operations are deleted', () async {
      await run({
        'a|lib/graphql/users/get_user.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { id } }',
      });
      expect(output('users_operations.dart'), isNotNull);
      CodegenConfigContext.groupOperations = 'none';
      await run({
        'a|lib/graphql/users/get_user.graphql':
            r'query GetUser($id: ID!) { user(id: $id) { id } }',
      });
      expect(severe(), isEmpty);
      expect(output('users_operations.dart'), isNull);
      expect(output('index.dart'), isNot(contains('users_operations.dart')));
    });

    test('directories with the same group name are reported', () async {
      await run({
        'a|lib/graphql/user-admin/a.graphql': 'query A { version }',
        'a|lib/graphql/user_admin/b.graphql': 'query B { version }',
      });
      expect(
          logs,
          contains(allOf(
            contains('BLD108'),
            contains('"user-admin"'),
            contains('"user_admin"'),
          )));
    });

    test('names clashing with fragments.dart are reported', () async {
      await run({
        'a|lib/graphql/fragments.graphql':
            'fragment UsersOperations on User { id }',
        'a|lib/graphql/users/a.graphql': 'query A { version }',
      });
      expect(
          logs,
          contains(allOf(
            contains('BLD108'),
            contains('"UsersOperations"'),
            contains('fragments.dart'),
          )));
    });
  });
}
