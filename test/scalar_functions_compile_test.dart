// scalar_mapping with from_json/to_json: the generated code must pass
// `dart analyze` and convert fields, lists, variables and inputs with the
// functions, in both result modes.
//
// Slow (creates a package and runs a script); skip locally with
// `dart test -x compile`.
@Tags(['compile'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/config_context.dart';
import 'package:flutter_graphql_codegen/src/generator.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:test/test.dart';

import 'support/compile_harness.dart';

const _schema = r'''
scalar Money
scalar Stamp
scalar _text
type Item {
  ref: ID!
  tags: _text
  price: Money!
  prices: [Money!]!
  maybe: [Money]
  stamp: Stamp
}
input ItemInput { price: Money! stamp: Stamp }
type Query { item(price: Money, input: ItemInput): Item! total: Money! }
''';

const _document = r'''
query GetItem($price: Money, $input: ItemInput) {
  item(price: $price, input: $input) { ref tags price prices maybe stamp }
  total
}
''';

// Functions as Artemis and graphql_codegen users have them: one takes the
// JSON type it expects, the other `dynamic`.
const _library = r'''
class Money {
  const Money(this.cents);
  final int cents;
  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;
  @override
  int get hashCode => cents.hashCode;
}

Money moneyFromJson(int json) => Money(json);
int moneyToJson(Money money) => money.cents;

DateTime stampFromJson(dynamic json) =>
    DateTime.fromMillisecondsSinceEpoch(json as int, isUtc: true);
dynamic stampToJson(DateTime stamp) => stamp.millisecondsSinceEpoch;

// Hasura's `_text` (a Postgres array literal) and a built-in scalar.
List<String> textFromJson(String json) =>
    json.substring(1, json.length - 1).split(',');
String textToJson(List<String> tags) => '{${tags.join(',')}}';

class Ref {
  const Ref(this.value);
  final String value;
}

Ref refFromJson(String json) => Ref(json);
String refToJson(Ref ref) => ref.value;
''';

const _config = '''
schema_url: schema.graphql
document_paths: [lib/**.graphql]
scalar_mapping:
  Money:
    type: Money
    import: package:fgc_compile_check/scalars/money.dart
    from_json: moneyFromJson
    to_json: moneyToJson
  Stamp:
    type: DateTime
    import: package:fgc_compile_check/scalars/money.dart
    from_json: stampFromJson
    to_json: stampToJson
  _text:
    type: List<String>
    import: package:fgc_compile_check/scalars/money.dart
    from_json: textFromJson
    to_json: textToJson
  ID:
    type: Ref
    import: package:fgc_compile_check/scalars/money.dart
    from_json: refFromJson
    to_json: refToJson
''';

String _main(String dir) => '''
import 'package:fgc_compile_check/$dir/GetItem.g.dart';
import 'package:fgc_compile_check/$dir/types.dart';
import 'package:fgc_compile_check/scalars/money.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError('Check failed: \$message');
}

void main() {
  final data = parseGetItemData({
    'item': {
      '__typename': 'Item',
      'price': 150,
      'prices': [1, 2],
      'maybe': [3, null],
      'stamp': 86400000,
      'ref': 'r1',
      'tags': '{a,b}',
    },
    'total': 999,
  });
  check(data${dir == 'schema' ? '!' : ''}.item${dir == 'schema' ? '!' : ''}.price${dir == 'schema' ? '!' : ''}.cents == 150, 'field');
  final item = data${dir == 'schema' ? '!' : ''}.item${dir == 'schema' ? '!' : ''};
  check(item.prices${dir == 'schema' ? '!' : ''}[1]${dir == 'schema' ? '!' : ''}.cents == 2, 'list elements');
  check(item.maybe![1] == null, 'null list element');
  check(item.stamp!.day == 2, 'function taking dynamic');
  check(item.toJson()['price'] == 150, 'toJson');
  check(item.ref.value == 'r1', 'built-in scalar with functions');
  check(item.tags![1] == 'b' && item.toJson()['tags'] == '{a,b}',
      'scalar named with an underscore');
  final vars = GetItemVariables(
    price: const Money(5),
    input: ItemInput(price: const Money(6), stamp: DateTime.utc(1970, 1, 2)),
  ).toJson();
  check(vars['price'] == 5, 'variable');
  final input = vars['input'] as Map<String, dynamic>;
  check(input['price'] == 6 && input['stamp'] == 86400000, 'input');
  print('FUNCTIONS OK');
}
''';

Map<String, String> _generate(String dir, String resultTypes) {
  final config = GraphQLCodegenConfig.fromYaml(_config);
  CodegenConfigContext.reset();
  CodegenConfigContext.strictNullability = true;
  CodegenConfigContext.resultTypes = resultTypes;
  CodegenConfigContext.scalarMapping = Map.of(config.scalarMapping);
  CodegenConfigContext.scalarImports = Map.of(config.scalarImports);
  CodegenConfigContext.scalarConverters = Map.of(config.scalarConverters);
  CodegenConfigContext.scalarFunctions = Map.of(config.scalarFunctions);
  try {
    final types = GraphQLCodeGenerator.generateTypesFile(_schema);
    final op = gql_lang
        .parseString(_document)
        .definitions
        .whereType<OperationDefinitionNode>()
        .single;
    return {
      'lib/$dir/types.dart': types,
      'lib/$dir/GetItem.g.dart': GraphQLCodeGenerator.generateOperationFile(
          _schema, _document, op.name!.value, op.type.name, types),
      'bin/$dir.dart': _main(dir),
    };
  } finally {
    CodegenConfigContext.reset();
  }
}

void main() {
  test('from_json/to_json scalars compile and convert', () async {
    final files = {
      ..._generate('operation', 'operation'),
      ..._generate('schema', 'schema'),
      'lib/scalars/money.dart': _library,
    };
    expect(files['lib/operation/types.dart'],
        contains('class MoneyFunctionsConverter'));
    expect(
        files['lib/operation/types.dart'],
        allOf(contains('class TextFunctionsConverter'),
            contains('class IDFunctionsConverter')));
    final result = await compileGenerated(files,
        runScripts: ['bin/operation.dart', 'bin/schema.dart']);
    expect(result.errors, isEmpty, reason: result.log);
    expect(RegExp('FUNCTIONS OK').allMatches(result.log), hasLength(2));
  });
}
