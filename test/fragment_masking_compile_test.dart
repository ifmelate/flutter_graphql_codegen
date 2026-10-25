// End-to-end check of `fragment_masking`: the generated code must pass
// `dart analyze` and work against a GraphQLClient and its cache.
//
// Slow (creates a package and runs a script); skip locally with
// `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';

import 'support/compile_harness.dart';
import 'support/masking_fixture.dart';

const _main = r'''
import 'package:fgc_compile_check/mask/Conditional.g.dart';
import 'package:fgc_compile_check/mask/GetNode.g.dart';
import 'package:fgc_compile_check/mask/Me.g.dart';
import 'package:fgc_compile_check/mask/MeOnly.g.dart';
import 'package:fgc_compile_check/mask/Search.g.dart';
import 'package:fgc_compile_check/mask/fragments.dart';
import 'package:graphql/client.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: $message');
}

/// Consumers that only know their fragment, like widgets would.
String avatarLabel(AvatarBits bits) =>
    '${bits.id}:${bits.avatar}:${bits.friends.map((f) => f.name).join('+')}';
String cardLabel(UserCard card) =>
    '${card.name} ${avatarLabel(card.avatarBits)}';

const meJson = {
  '__typename': 'User',
  'id': '1',
  'name': 'Ann',
  'avatar': 'a.png',
  'friends': [
    {'__typename': 'User', 'id': '2', 'name': 'Bob'},
  ],
};

void main() {
  final me = parseMeData({'me': meJson});
  check(me.id == '1', 'own field');
  check(me.friends.single.id == '2', 'own subfields');
  check(cardLabel(me.userCard) == 'Ann 1:a.png:Bob', 'fragment data');
  check(me.toJson()['friends'][0]['name'] == 'Bob',
      'toJson keeps the subfields only the fragment selects');
  check(Me_Me.fromJson(me.toJson()) == me, 'round trip');
  final renamed =
      me.copyWith(userCard: UserCardData.fromJson({...meJson, 'name': 'Zoe'}));
  check(renamed.userCard.name == 'Zoe', 'copyWith');

  final client = GraphQLClient(
    link: Link.function((request, [forward]) => const Stream.empty()),
    cache: GraphQLCache(),
  );
  client.writeMe(me);
  check(client.readMe() == me, 'cache round trip');
  check(client.readUserCardFragment({'id': '1'})?.avatarBits.avatar == 'a.png',
      'fragment read from the cache');

  // A fragment on an interface: its type-specific data.
  final user = parseGetNodeData({
    'node': {'__typename': 'User', 'id': '1', 'name': 'Ann'},
  })!;
  switch (user) {
    case GetNode_Node_Other(:final nodeBits):
      check(nodeBits is NodeBits_OnUser && nodeBits.name == 'Ann',
          'type-specific fragment data');
    case GetNode_Node_OnPost():
      check(false, 'a user is no post');
  }
  final post = parseGetNodeData({
    'node': {'__typename': 'Post', 'id': 'p', 'title': 'Hi'},
  });
  check(post is GetNode_Node_OnPost && post.title == 'Hi',
      'own field of a type');
  check(post!.nodeBits.id == 'p', 'fragment of the sealed base');

  // Fragments in a union, and in a nested field.
  final results = parseSearchData({
    'search': [
      {'__typename': 'User', 'id': '1', 'avatar': null, 'friends': []},
      {'__typename': 'Post', 'title': 'Hi', 'author': meJson},
    ],
  });
  final labels = [
    for (final r in results)
      switch (r) {
        Search_Search_OnUser(:final avatarBits) =>
          'user ${avatarLabel(avatarBits)}',
        Search_Search_OnPost(:final title, :final author) =>
          'post $title by ${avatarLabel(author.avatarBits)}',
        Search_Search_Other() => 'other',
      },
  ];
  check(labels.join(',') == 'user 1:null:,post Hi by 1:a.png:Bob', 'union');

  // A fragment on the root type.
  final root = parseMeOnlyData({
    'me': {'__typename': 'User', 'id': '1'},
  });
  check(root.rootBits.me.id == '1', 'root fragment');
  client.writeMeOnly(root);
  check(client.readMeOnly() == root, 'root fragment in the cache');

  // A conditional spread stays unmasked.
  final conditional = parseConditionalData({
    'me': {'__typename': 'User', 'id': '1'},
  });
  check(conditional.avatar == null, 'conditional spread');
  print('MASKING OK');
}
''';

void main() {
  test('masked fragments compile and work', () async {
    final files = {
      for (final MapEntry(:key, :value)
          in generateMasked(dir: 'lib/mask/').entries)
        key: value,
      for (final MapEntry(:key, :value)
          in generateMasked(dir: 'lib/mask_legacy/', strict: false).entries)
        key: value,
      'bin/mask.dart': _main,
    };
    final result = await compileGenerated(files, runScripts: ['bin/mask.dart']);
    expect(result.errors, isEmpty, reason: result.log);
  });
}
