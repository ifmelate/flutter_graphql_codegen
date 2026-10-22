import 'dart:io';

import 'package:graphql/client.dart';
import 'package:live_check_countries/graphql/generated/index.dart';

void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) exitCode = 1;
}

String describe(LanguageBits l) =>
    '${l.name} (${l.code}${l.rtl ? ', rtl' : ''})';

Future<void> main() async {
  final client = GraphQLClient(
    link: HttpLink('https://countries.trevorblades.com/graphql'),
    cache: GraphQLCache(possibleTypes: possibleTypes),
    queryRequestTimeout: const Duration(seconds: 30),
  );

  // Partial selection, alias with an argument, @include with a default.
  const vars = CountryCardVariables(code: 'DE', lang: 'de');
  final de = await client.countryCardData(vars.toJson());
  check(de?.name == 'Germany', 'country name: ${de?.name}');
  check(de?.localName == 'Deutschland',
      'alias with an argument: ${de?.localName}');
  check(de?.states == null, 'states left out: withStates defaults to false');
  check(de?.continent.name == 'Europe', 'nested object: ${de?.continent.name}');
  print('     languages: ${de?.languages.map(describe).join(', ')}');

  final withStates = await client.countryCardData(
      const CountryCardVariables(code: 'AT', withStates: true).toJson());
  check((withStates?.states?.length ?? 0) > 0,
      '@include(if: true): ${withStates?.states?.length} states');

  // Round trip and equality.
  final copy = CountryCard_Country.fromJson(de!.toJson());
  check(copy == de && copy.hashCode == de.hashCode, 'toJson/fromJson ==');
  check(de.copyWith(capital: null).capital == null, 'copyWith(capital: null)');

  // Cache: the result was cached under the same variables.
  check(client.readCountryCard(vars) == de, 'readCountryCard');
  client.writeCountryCard(vars, de.copyWith(capital: 'Bonn'));
  check(client.readCountryCard(vars)?.capital == 'Bonn',
      'writeCountryCard, then readCountryCard');

  // A filter with only `eq` set: the nullable lists must stay out.
  const oceania =
      CountryFilterInput(continent: StringQueryOperatorInput(eq: 'OC'));
  print('     filter json: ${oceania.toJson()}');
  check(!(oceania.toJson()['continent'] as Map).containsKey('in'),
      'unset nullable list is left out');
  final eq = await client.filteredCountriesData(
      const FilteredCountriesVariables(filter: oceania).toJson());
  check(
      eq.countries.isNotEmpty &&
          eq.countries.every((c) => c.continent.code == 'OC'),
      'filter eq: ${eq.countries.length} countries, all in OC');
  check(eq.europe?.name == 'Europe', 'second root field through an alias');

  // A keyword field (`in`).
  final inList = await client.filteredCountriesData(FilteredCountriesVariables(
      filter: CountryFilterInput(
          code: StringQueryOperatorInput(in_: ['FR', 'JP']))).toJson());
  final codes = inList.countries.map((c) => c.code).toSet();
  check(codes.length == 2 && codes.containsAll(['FR', 'JP']),
      'filter in: ${codes.join(', ')}');
}
