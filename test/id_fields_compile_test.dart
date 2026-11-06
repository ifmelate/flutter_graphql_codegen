// End-to-end check of `add_id_fields`: the generated code must pass
// `dart analyze` and keep the normalized cache of `package:graphql` up to
// date when the documents forget `id`.
//
// Slow (creates a package and runs a script); skip locally with
// `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';

import 'support/compile_harness.dart';
import 'support/id_fields_fixture.dart';

/// Runs the operations against a server that returns only the fields asked
/// for and prints what the cache shows afterwards.
String _main(String dir) => '''
import 'package:fgc_compile_check/$dir/Me.g.dart';
import 'package:fgc_compile_check/$dir/Rename.g.dart';
import 'package:fgc_compile_check/$dir/Search.g.dart';
import 'package:fgc_compile_check/$dir/UserFull.g.dart';
import 'package:fgc_compile_check/$dir/fragments.dart';
import 'package:gql/language.dart';
import 'package:graphql/client.dart';

/// Whole objects; [selected] drops what the document doesn't ask for.
Map<String, dynamic> respond(String operation) => switch (operation) {
      'UserFull' => {
          'user': {'__typename': 'User', 'id': '1', 'name': 'Ann'},
        },
      'Rename' => {
          'rename': {'__typename': 'User', 'id': '1', 'name': 'Zoe'},
        },
      'Me' => {
          'me': {
            '__typename': 'User',
            'id': '1',
            'name': 'Ann',
            'friends': [
              {'__typename': 'User', 'id': '2', 'name': 'Bob'},
            ],
          },
        },
      'Search' => {
          'search': [
            {'__typename': 'User', 'id': '1', 'name': 'Ann'},
            {'__typename': 'Tag', 'name': 'news'},
          ],
        },
      _ => throw StateError(operation),
    };

/// [data] without `id` fields when the document selects none, like a real
/// server (the cache would otherwise find ids nobody asked for).
Map<String, dynamic> selected(Request request, Map<String, dynamic> data) {
  final document = printNode(request.operation.document);
  if (RegExp(r'(?<![\\\$\\w])id(?![\\w:])').hasMatch(document)) return data;
  Object? strip(Object? value) => switch (value) {
        Map<String, dynamic>() => {
            for (final MapEntry(:key, :value) in value.entries)
              if (key != 'id') key: strip(value),
          },
        List() => value.map(strip).toList(),
        _ => value,
      };
  return strip(data) as Map<String, dynamic>;
}

Future<void> main() async {
  final client = GraphQLClient(
    link: Link.function((request, [forward]) {
      final name = request.operation.operationName!;
      return Stream.value(Response(
        data: selected(request, {
          '__typename': name == 'Rename' ? 'Mutation' : 'Query',
          ...respond(name),
        }),
        response: const {},
      ));
    }),
    cache: GraphQLCache(),
  );

  // A mutation result updates the user another query shows.
  const vars = UserFullVariables(id: '1');
  final full = await client.query(userFullQueryOptions(vars));
  final renamed = await client.mutate(
      renameMutationOptions(const RenameVariables(id: '1', name: 'Zoe')));
  if (full.hasException || renamed.hasException) {
    throw StateError('\${full.exception ?? renamed.exception}');
  }
  print('AFTER RENAME: \${client.readUserFull(vars)?.name}');

  // An object a query returned can be read as a fragment by its id.
  final me = await client.query(meQueryOptions());
  print('ME: \${me.parsedData?.friends.single.name}');
  print('FRIEND FRAGMENT: \${client.readUserNameFragment({'id': '2'})?.name}');

  // Union members get id where they have one.
  final search = await client.query(searchQueryOptions());
  print('SEARCH: \${search.parsedData?.length}');
}
''';

void main() {
  test('with add_id_fields, mutations and fragment reads use the cache',
      () async {
    final files = {
      ...generateIds(dir: 'lib/ids/'),
      ...generateIds(dir: 'lib/ids_legacy/', strict: false),
      ...generateIds(dir: 'lib/plain/', addIds: false),
      'bin/ids.dart': _main('ids'),
      'bin/plain.dart': _main('plain'),
    };
    final result = await compileGenerated(files,
        runScripts: ['bin/ids.dart', 'bin/plain.dart']);
    expect(result.errors, isEmpty, reason: result.log);

    final runs = result.log.split(r'$ dart run bin/plain.dart');
    expect(runs, hasLength(2), reason: result.log);
    final (ids, plain) = (runs.first, runs.last);
    expect(ids, contains('AFTER RENAME: Zoe'), reason: result.log);
    expect(ids, contains('ME: Bob'));
    expect(ids, contains('FRIEND FRAGMENT: Bob'));
    expect(ids, contains('SEARCH: 2'));
    // Without the option the same steps show a stale name and can't read
    // the fragment: what the option is for.
    expect(plain, contains('AFTER RENAME: Ann'), reason: result.log);
    expect(plain, contains('FRIEND FRAGMENT: null'));
  });
}
