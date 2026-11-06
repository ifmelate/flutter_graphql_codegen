// Schema and documents for the `add_id_fields` tests.
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/document_utils.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;

const idSchema = r'''
scalar Uuid
interface Node { id: ID! }
interface Named { name: String! }
type User implements Node & Named {
  id: ID!
  name: String!
  friends: [User!]!
}
type Post implements Node { id: ID! title: String! author: User! }
type Tag implements Named { name: String! }
type Comment { id(format: String!): ID! text: String! }
type Order { id: Uuid! total: Int! }
union Hit = User | Post | Tag
type Query {
  me: User!
  user(id: ID!): User
  node(id: ID!): Node
  search: [Hit!]!
  named: [Named!]!
  tags: [Tag!]!
  comments: [Comment!]!
  orders: [Order!]!
}
type Mutation { rename(id: ID!, name: String!): User! }
''';

const idDocuments = [
  'fragment UserName on User { name }',
  r'''
query Me { me { name friends { name } ...UserName } }
query MeWithId { me { id name } }
query Aliased { me { id: name } }
query AliasedId { me { userId: id name } }
query Search {
  search { ... on User { name } ... on Post { title } ... on Tag { name } }
}
query GetNode($id: ID!) { node(id: $id) { ... on User { name } } }
query GetNamed { named { name ... on User { friends { name } } } }
query NoIds { tags { name } comments { text } }
query Orders { orders { total } }
''',
  r'''
query UserFull($id: ID!) { user(id: $id) { id name } }
query UserName($id: ID!) { user(id: $id) { name } }
mutation Rename($id: ID!, $name: String!) { rename(id: $id, name: $name) { name } }
''',
];

/// types.dart, fragments.dart and the operation files of [idDocuments] with
/// `add_id_fields` [addIds], by file name.
Map<String, String> generateIds(
    {bool addIds = true, bool strict = true, String dir = ''}) {
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = strict;
  CodegenConfigContext.addIdFields = addIds;
  try {
    final types = TypeGenerator.generateTypesFile(idSchema);
    final files = <String, String>{'${dir}types.dart': types};
    final fragments =
        DocumentUtils.collectFragments(idDocuments.map(gql_lang.parseString));
    files['${dir}fragments.dart'] =
        GraphQLCodeGenerator.generateFragmentsFile(idSchema, fragments)!;
    for (final doc in idDocuments) {
      for (final op in gql_lang
          .parseString(doc)
          .definitions
          .whereType<OperationDefinitionNode>()) {
        final name = op.name!.value;
        files['$dir$name.g.dart'] = GraphQLCodeGenerator.generateOperationFile(
            idSchema, doc, name, op.type.name, types,
            fragments: fragments);
      }
    }
    return files;
  } finally {
    CodegenConfigContext.reset();
  }
}
