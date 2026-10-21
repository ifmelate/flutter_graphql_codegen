/// Formatting of generated Dart code.
library;

import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

/// Formats generated [code] with `dart format` rules for [languageVersion]
/// (the language version of the package the code is written into, so the
/// result matches what `dart format` produces there; defaults to the language
/// version of the running SDK).
///
/// Throws [FormatterException] when [code] is not valid Dart.
String formatGeneratedCode(String code, {Version? languageVersion}) =>
    _formatter(languageVersion ?? _sdkLanguageVersion()).format(code);

/// dart_style 2.3.7 added `languageVersion` (required since 3.0). Older
/// versions, which projects still get next to analyzer 6.4 (for example through
/// hive_generator), don't have it, so the argument is passed dynamically and
/// both compile.
DartFormatter _formatter(Version languageVersion) {
  try {
    return Function.apply(
            DartFormatter.new, const [], {#languageVersion: languageVersion})
        as DartFormatter;
  } on NoSuchMethodError {
    return Function.apply(DartFormatter.new, const []) as DartFormatter;
  }
}

Version _sdkLanguageVersion() {
  final sdk = Version.parse(Platform.version.split(' ').first);
  return Version(sdk.major, sdk.minor, 0);
}
