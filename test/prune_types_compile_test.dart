// prune_types end to end: the pruned types.dart, fragments.dart and the
// operation files must compile together and work at runtime.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

import 'support/compile_harness.dart';

const _schema = r'''
scalar Money
scalar Unused

enum Role { ADMIN USER }
enum Sort { NEWEST OLDEST }
enum Lonely { A B }

input Page { first: Int sort: Sort }
input Filter { name: String page: Page roles: [Role!] }
input Forgotten { lonely: Lonely }

interface Named { name: String }
union Hit = User | Post

type User implements Named { id: ID! name: String role: Role! balance: Money }
type Post { id: ID! title: String }

type Query {
  users(filter: Filter): [User!]!
  search: [Hit!]!
  forgotten(input: Forgotten): Boolean
}
''';

const _documents = [
  r'''
fragment Wallet on User { balance }
query Users($filter: Filter) { users(filter: $filter) { id role ...Wallet } }
''',
  r'''
query Search { search { ... on Post { title } ... on Named { name } } }
''',
];

Map<String, String> _generate(String dir, {required bool strict}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = strict;
  try {
    final used = GraphQLCodeGenerator.usedTypes(_schema, _documents);
    final types = GraphQLCodeGenerator.generateTypesFile(_schema, only: used);
    final files = <String, String>{'lib/$dir/types.dart': types};
    final fragments =
        DocumentUtils.collectFragments(_documents.map(gql_lang.parseString));
    final code = GraphQLCodeGenerator.generateFragmentsFile(_schema, fragments);
    if (code != null) files['lib/$dir/fragments.dart'] = code;
    for (final doc in _documents) {
      for (final op in gql_lang
          .parseString(doc)
          .definitions
          .whereType<OperationDefinitionNode>()) {
        final name = op.name!.value;
        files['lib/$dir/$name.g.dart'] =
            GraphQLCodeGenerator.generateOperationFile(
                _schema, doc, name, op.type.name, types,
                fragments: fragments);
      }
    }
    return files;
  } finally {
    CodegenConfigContext.reset();
  }
}

String _main(String dir) => '''
import 'package:fgc_compile_check/$dir/Search.g.dart';
import 'package:fgc_compile_check/$dir/Users.g.dart';
import 'package:fgc_compile_check/$dir/fragments.dart';
import 'package:fgc_compile_check/$dir/types.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: \$message');
}
'''
    r'''

void main() {
  // Variables: an input with a nested input, enums and an enum list.
  const vars = UsersVariables(
      filter: Filter(
          name: 'a',
          page: Page(first: 10, sort: Sort.NEWEST),
          roles: [Role.ADMIN]));
  final json = vars.toJson();
  final filter = json['filter'] as Map<String, dynamic>;
  check((filter['page'] as Map)['sort'] == 'NEWEST', 'nested input enum');
  check(graphqlDeepEquals(filter['roles'], ['ADMIN']), 'enum list');

  // Results: an enum, a custom scalar through a fragment.
  final users = parseUsersData({
    'users': [
      {'__typename': 'User', 'id': '1', 'role': 'USER', 'balance': '9.99'},
    ],
  });
  final user = users!.first!;
  check(user.role == Role.USER, 'enum field');
  final Wallet wallet = user;
  check(wallet.balance?.value == '9.99', 'custom scalar from a fragment');

  // An abstract type: possibleTypes keeps it.
  check(possibleTypes['Hit']!.contains('Post'), 'possibleTypes has Hit');
  final hits = parseSearchData({
    'search': [
      {'__typename': 'Post', 'title': 'T'},
      {'__typename': 'User', 'name': 'N'},
    ],
  });
  check(hits!.length == 2, 'union parsed');
  print('PRUNED OK');
}
''';

void main() {
  test('pruned types.dart compiles with the operation files', () async {
    final files = {
      ..._generate('pruned', strict: true),
      ..._generate('pruned_legacy', strict: false),
      'bin/pruned.dart': _main('pruned'),
      'bin/pruned_legacy.dart': _main('pruned_legacy'),
    };
    final types = files['lib/pruned/types.dart']!;
    expect(types, isNot(contains('Lonely')));
    expect(types, isNot(contains('class Unused')));
    final result = await compileGenerated(files,
        runScripts: ['bin/pruned.dart', 'bin/pruned_legacy.dart']);
    expect(result.errors, isEmpty, reason: result.log);
  });
}
