import 'package:flutter_graphql_codegen/src/schema_downloader.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

Map<String, dynamic> _named(String kind, String name) =>
    {'kind': kind, 'name': name, 'ofType': null};

Map<String, dynamic> _nonNull(Map<String, dynamic> of) =>
    {'kind': 'NON_NULL', 'name': null, 'ofType': of};

Map<String, dynamic> _list(Map<String, dynamic> of) =>
    {'kind': 'LIST', 'name': null, 'ofType': of};

void main() {
  test('introspectionToSdl produces a parseable equivalent schema', () {
    final data = {
      '__schema': {
        'queryType': {'name': 'Query'},
        'mutationType': null,
        'subscriptionType': null,
        'types': [
          {
            'kind': 'OBJECT',
            'name': 'Query',
            'interfaces': <dynamic>[],
            'fields': [
              {
                'name': 'search',
                'args': [
                  {
                    'name': 'first',
                    'type': _named('SCALAR', 'Int'),
                    'defaultValue': '10',
                  },
                ],
                'type': _nonNull(_list(_nonNull(_named('UNION', 'Result')))),
                'isDeprecated': false,
              },
              {
                'name': 'old',
                'args': <dynamic>[],
                'type': _named('SCALAR', 'String'),
                'isDeprecated': true,
                'deprecationReason': 'Use "search"',
              },
            ],
          },
          {
            'kind': 'INTERFACE',
            'name': 'Node',
            'interfaces': <dynamic>[],
            'fields': [
              {
                'name': 'id',
                'args': <dynamic>[],
                'type': _nonNull(_named('SCALAR', 'ID')),
              },
            ],
          },
          {
            'kind': 'OBJECT',
            'name': 'User',
            'interfaces': [_named('INTERFACE', 'Node')],
            'fields': [
              {
                'name': 'id',
                'args': <dynamic>[],
                'type': _nonNull(_named('SCALAR', 'ID')),
              },
              {
                'name': 'role',
                'args': <dynamic>[],
                'type': _named('ENUM', 'Role'),
              },
            ],
          },
          {
            'kind': 'UNION',
            'name': 'Result',
            'possibleTypes': [_named('OBJECT', 'User')],
          },
          {
            'kind': 'ENUM',
            'name': 'Role',
            'enumValues': [
              {'name': 'ADMIN', 'isDeprecated': false},
            ],
          },
          {
            'kind': 'INPUT_OBJECT',
            'name': 'Filter',
            'inputFields': [
              {'name': 'q', 'type': _named('SCALAR', 'String')},
            ],
          },
          {'kind': 'SCALAR', 'name': 'DateTime'},
          {'kind': 'SCALAR', 'name': 'String'},
          {'kind': 'OBJECT', 'name': '__Type', 'fields': <dynamic>[]},
        ],
      },
    };

    final sdl = SchemaDownloader.introspectionToSdl(data);
    final doc = gql_lang.parseString(sdl);

    expect(sdl, contains('search(first: Int = 10): [Result!]!'));
    expect(sdl, contains('type User implements Node {'));
    expect(sdl, contains('union Result = User'));
    expect(
        sdl, contains('old: String @deprecated(reason: "Use \\"search\\"")'));
    expect(sdl, contains('scalar DateTime'));
    expect(sdl, isNot(contains('scalar String')));
    expect(sdl, isNot(contains('__Type')));
    expect(doc.definitions.whereType<TypeDefinitionNode>().length, 7);
  });
}
