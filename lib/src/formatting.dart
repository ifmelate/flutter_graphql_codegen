/// Formatting of generated Dart code.
library;

import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

/// Formats generated [code] with `dart format` rules for [languageVersion]
/// (the language version of the package the code is written into, so the
/// result matches what `dart format` produces there; defaults to the
/// formatter's latest).
///
/// Throws [FormatterException] when [code] is not valid Dart.
String formatGeneratedCode(String code, {Version? languageVersion}) =>
    DartFormatter(
            languageVersion:
                languageVersion ?? DartFormatter.latestLanguageVersion)
        .format(code);
