import 'package:build/build.dart';
import 'package:flutter_graphql_codegen/flutter_graphql_codegen.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    final awesome = Awesome();

    setUp(() {
      // Additional setup goes here.
    });

    test('First Test', () {
      expect(awesome.isAwesome, isTrue);
      final builderOptions = BuilderOptions({
        'config_path': 'test/fixtures/graphql_codegen.yaml',
      });
      var builder = graphqlCodegenBuilder(builderOptions);
      /* builder.build(BuildStep()); */
    });
  });
}
