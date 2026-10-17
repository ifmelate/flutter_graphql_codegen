import 'package:flutter_graphql_codegen/src/formatting.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('formats generated code', () {
    expect(formatGeneratedCode('class  A{int x=1;}'),
        'class A {\n  int x = 1;\n}\n');
  });

  test('a language version newer than the formatter knows is accepted', () {
    expect(
        formatGeneratedCode('class  A{}', languageVersion: Version(99, 0, 0)),
        'class A {}\n');
  });
}
