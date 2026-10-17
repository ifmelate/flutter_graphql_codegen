import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';
import 'package:test/test.dart';

void main() {
  setUp(CodegenConfigContext.reset);

  test('lists the concrete types of every interface and union', () {
    final types = TypeGenerator.generateTypesFile('''
interface Node { id: ID! }
type User implements Node { id: ID! }
type Post implements Node { id: ID! }
type Ad { id: ID! }
union Hit = Post | Ad | User
type Query { node: Node }
''');
    expect(
        types,
        contains('const Map<String, Set<String>> possibleTypes = {\n'
            "  'Hit': {'Ad', 'Post', 'User'},\n"
            "  'Node': {'Post', 'User'},\n"
            '};'));
  });

  test('is empty when the schema has no abstract types', () {
    final types = TypeGenerator.generateTypesFile('type Query { a: String }');
    expect(
        types, contains('const Map<String, Set<String>> possibleTypes = {};'));
  });
}
