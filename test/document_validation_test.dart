import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/diagnostics.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

const _schema = r'''
scalar DateTime
interface Node { id: ID! }
type User implements Node {
  id: ID!
  name: String
  posts(first: Int = 10, after: String): [Post!]!
  avatar(size: Int!): String
}
type Post implements Node { id: ID! title: String! author: User! }
union Hit = User | Post
enum Order { ASC DESC }
input PostFilter { author: ID, since: DateTime, order: Order }
type Query {
  me: User
  node(id: ID!): Node
  search(term: String!): [Hit!]!
  posts(filter: PostFilter, order: Order): [Post!]!
}
type Mutation { rename(id: ID!, name: String!): User }
''';

/// Generates [operation] from [document]; returns the error or null.
CodegenException? _generate(String document, {String? operation}) {
  final types = TypeGenerator.generateTypesFile(_schema);
  final doc = gql_lang.parseString(document);
  final name = operation ??
      doc.definitions.whereType<OperationDefinitionNode>().first.name!.value;
  try {
    GraphQLCodeGenerator.generateOperationFile(
      _schema,
      document,
      name,
      'query',
      types,
      fragments: DocumentUtils.collectFragments([doc]),
    );
    return null;
  } on CodegenException catch (e) {
    return e;
  }
}

Matcher _problem(String code, List<String> parts) =>
    isA<CodegenException>().having((e) => e.message, 'message',
        allOf([code, ...parts].map(contains).toList()));

void main() {
  setUp(CodegenConfigContext.reset);
  tearDown(CodegenConfigContext.reset);

  test('accepts a valid document using every kind of selection', () {
    expect(
      _generate(r'''
query Everything($id: ID!, $term: String!, $withName: Boolean!, $f: PostFilter) {
  __typename
  me { ...UserBits avatar(size: 32) }
  node(id: $id) { id ... on User { name @include(if: $withName) } }
  search(term: $term) {
    __typename
    ... on User { id }
    ... on Post { title author { id } }
  }
  latest: posts(filter: $f, order: DESC) { id }
}
fragment UserBits on User { id posts { id } }
'''),
      isNull,
    );
  });

  group('BLD103 unknown fields', () {
    test('are reported at any depth with path and line', () {
      expect(
        _generate('''
query Q {
  me {
    posts { titel }
  }
}
'''),
        _problem('BLD103', ['"titel"', '"Post"', 'me.posts.titel', 'line 3']),
      );
    });

    test('are reported inside fragments', () {
      expect(
        _generate('query Q { me { ...Bits } }\nfragment Bits on User { nope }'),
        _problem('BLD103', ['"nope"', '"User"', 'fragment Bits']),
      );
    });

    test('include plain fields selected on a union', () {
      expect(
        _generate(r'query Q($t: String!) { search(term: $t) { id } }'),
        _problem('BLD103', ['"id"', 'union "Hit"']),
      );
    });
  });

  group('BLD105 arguments', () {
    test('unknown arguments are reported', () {
      expect(
        _generate('query Q { me { posts(last: 1) { id } } }'),
        _problem('BLD105', ['"last"', 'User.posts']),
      );
    });

    test('missing required arguments are reported', () {
      expect(
        _generate('query Q { me { avatar } }'),
        _problem('BLD105', ['"size"', 'User.avatar', 'required']),
      );
    });
  });

  group('BLD106 variables', () {
    test('undeclared variables are reported, also in nested values', () {
      expect(
        _generate(r'query Q { posts(filter: {author: $who}) { id } }'),
        _problem('BLD106', [r'$who', 'not declared']),
      );
      expect(
        _generate(r'query Q { me { name @skip(if: $hide) } }'),
        _problem('BLD106', [r'$hide', 'not declared']),
      );
    });

    test('unused variables are reported', () {
      expect(
        _generate(r'query Q($id: ID!) { me { id } }'),
        _problem('BLD106', [r'$id', 'never used']),
      );
    });

    test('variables used only in a fragment count as used', () {
      expect(
        _generate(r'''
query Q($size: Int!) { me { ...Bits } }
fragment Bits on User { avatar(size: $size) }
'''),
        isNull,
      );
    });

    test('variables of unknown or output types are reported', () {
      expect(
        _generate(r'query Q($u: Usr) { node(id: $u) { id } }'),
        _problem('BLD106', [r'$u', '"Usr"']),
      );
      expect(
        _generate(r'query Q($u: User) { node(id: $u) { id } }'),
        _problem('BLD106', [r'$u', '"User"', 'input type']),
      );
    });
  });

  group('BLD107 selections', () {
    test('a scalar with a selection set is reported', () {
      expect(
        _generate('query Q { me { name { x } } }'),
        _problem('BLD107', ['"name"', 'String']),
      );
    });

    test('an object without a selection set is reported', () {
      expect(
        _generate('query Q { me }'),
        _problem('BLD107', ['"me"', 'User']),
      );
    });

    test('fragments on unknown or leaf types are reported', () {
      expect(
        _generate('query Q { me { ... on Usr { id } } }'),
        _problem('BLD107', ['"Usr"']),
      );
      expect(
        _generate('query Q { me { ...Bits } }\nfragment Bits on Order { x }'),
        _problem('BLD107', ['"Order"', 'fragment Bits']),
      );
    });
  });

  group('reserved aliases', () {
    test('aliases starting with __ are reported', () {
      expect(
        _generate('query Q { me { docs: posts { __typename: title } } }'),
        _problem('BLD107', ['"__typename"', 'reserved', 'me.docs.__typename']),
      );
      expect(
        _generate('query Q { __meta: me { id } }'),
        _problem('BLD107', ['"__meta"', 'reserved']),
      );
      expect(
        _generate('query Q { me { ...Bits } }\n'
            'fragment Bits on User { __typename: name }'),
        _problem('BLD107', ['"__typename"', 'fragment Bits']),
      );
    });

    test('__typename aliased to itself is fine', () {
      expect(_generate('query Q { me { __typename: __typename id } }'), isNull);
    });

    test('with validate_documents: false generation still fails clearly', () {
      CodegenConfigContext.validateDocuments = false;
      Matcher reserved(List<String> parts) => allOf(
          isA<CodegenException>().having((e) => e.code, 'code', 'BLD107'),
          _problem('', ['"__typename"', 'reserved', ...parts]));
      expect(
        _generate('query Q { me { docs: posts { __typename: title } } }'),
        reserved(['"title"', 'Q.me.docs']),
      );
      // At the root too (cache writes add __typename there).
      expect(
        _generate('query Q { __typename: me { id } }'),
        reserved(['"me"']),
      );
      // And in fragments.dart.
      expect(
        () => GraphQLCodeGenerator.generateFragmentsFile(
            _schema,
            DocumentUtils.collectFragments([
              gql_lang.parseString('fragment Bits on User { __typename: name }')
            ])),
        throwsA(reserved(['"name"', 'Bits'])),
      );
    });
  });

  test('all problems of a document are reported together', () {
    final error = _generate(r'query Q($x: Int) { me { nope avatar } }');
    expect(error, _problem('BLD103', ['nope']));
    expect(error!.message, contains('BLD105'));
    expect(error.message, contains('BLD106'));
  });

  test('validate_documents: false skips validation', () {
    CodegenConfigContext.validateDocuments = false;
    expect(_generate('query Q { me { nope } }'), isNull);
  });

  test('validate_documents is on by default and read from config', () {
    const base = 'schema_url: s.graphql\ndocument_paths: [a.graphql]\n';
    expect(GraphQLCodegenConfig.fromYaml(base).validateDocuments, isTrue);
    expect(
      GraphQLCodegenConfig.fromYaml('${base}validate_documents: false\n')
          .validateDocuments,
      isFalse,
    );
  });
}
