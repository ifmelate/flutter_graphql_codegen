import 'dart:io';

import 'package:graphql/client.dart';
import 'package:live_check_rick_and_morty/graphql/generated/index.dart';

void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) exitCode = 1;
}

/// Takes the fragment interface, so objects from both queries fit.
String card(CharacterCard c) =>
    '${c.name} (${c.status}) from ${c.origin?.name ?? '?'}';

Future<void> main() async {
  final client = GraphQLClient(
    link: HttpLink('https://rickandmortyapi.com/graphql'),
    cache: GraphQLCache(possibleTypes: possibleTypes),
    // The server is often slower than the 5 s default.
    queryRequestTimeout: const Duration(seconds: 30),
  );

  final page = await client.characterPageData(const CharacterPageVariables(
          page: 2, filter: FilterCharacter(status: 'Alive', species: 'Human'))
      .toJson());
  final results = page?.results ?? const [];
  check(results.isNotEmpty, 'page 2 of alive humans: ${results.length}');
  check(results.every((r) => r?.status == 'Alive'), 'filter applied');
  check((page?.info?.next ?? 0) > 2, 'info.next: ${page?.info?.next}');
  final first = results.first!;
  print('     ${card(first)}, ${first.episode?.length} episodes, '
      'first aired ${first.episode?.first?.air_date}');

  final byIds = await client.charactersByIdsData(
      const CharactersByIdsVariables(ids: ['1', '2']).toJson());
  check(byIds?.length == 2, 'charactersByIds: ${byIds?.length}');
  final rick = byIds!.first!;
  print('     ${card(rick)}; lives in ${rick.location?.name}');
  check(rick.name == 'Rick Sanchez', 'id 1 is Rick');

  // The same function takes objects from two different queries.
  final cards = <CharacterCard>[first, rick];
  check(cards.map(card).length == 2, 'fragment interface across queries');

  // Fragment cache access.
  final fromCache = client.readCharacterCardFragment({'id': '1'});
  check(fromCache?.name == 'Rick Sanchez',
      'readCharacterCardFragment: ${fromCache?.name}');
  client.writeCharacterCardFragment(
      {'id': '1'}, rick.copyWith(name: 'Pickle Rick'));
  final reread = client
      .readCharactersByIds(const CharactersByIdsVariables(ids: ['1', '2']));
  check(reread?.first?.name == 'Pickle Rick',
      'a fragment write is visible in the query: ${reread?.first?.name}');
}
