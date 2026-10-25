// Schema and documents for the `fragment_masking` tests.
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

const maskingSchema = r'''
interface Node { id: ID! }
type User implements Node {
  id: ID!
  name: String!
  avatar: String
  friends: [User!]!
}
type Post implements Node { id: ID! title: String! author: User! }
union SearchResult = User | Post
type Query { me: User! node(id: ID!): Node search: [SearchResult!]! }
''';

const maskingDocuments = [
  'fragment AvatarBits on User { id avatar friends { id name } }',
  'fragment UserCard on User { name ...AvatarBits }',
  'fragment NodeBits on Node { id ... on User { name } }',
  'fragment RootBits on Query { me { id } }',
  r'''
query Me { me { id friends { id } ...UserCard } }
query GetNode($id: ID!) { node(id: $id) { ...NodeBits ... on Post { title } } }
query Search {
  search {
    ... on User { ...AvatarBits }
    ... on Post { title author { ...AvatarBits } }
  }
}
query MeOnly { ...RootBits }
query Conditional($withAvatar: Boolean!) {
  me { id ...AvatarBits @include(if: $withAvatar) }
}
''',
];

/// types.dart, fragments.dart and the operation files of [documents] with
/// `fragment_masking` [masking], by file name.
Map<String, String> generateMasked(
    {bool masking = true, bool strict = true, String dir = ''}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = strict;
  CodegenConfigContext.fragmentMasking = masking;
  try {
    final types = TypeGenerator.generateTypesFile(maskingSchema);
    final files = <String, String>{'${dir}types.dart': types};
    final fragments = DocumentUtils.collectFragments(
        maskingDocuments.map(gql_lang.parseString));
    files['${dir}fragments.dart'] =
        GraphQLCodeGenerator.generateFragmentsFile(maskingSchema, fragments)!;
    for (final doc in maskingDocuments) {
      for (final op in gql_lang
          .parseString(doc)
          .definitions
          .whereType<OperationDefinitionNode>()) {
        final name = op.name!.value;
        files['$dir$name.g.dart'] = GraphQLCodeGenerator.generateOperationFile(
            maskingSchema, doc, name, op.type.name, types,
            fragments: fragments);
      }
    }
    return files;
  } finally {
    CodegenConfigContext.reset();
  }
}
