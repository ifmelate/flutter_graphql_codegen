/// Helpers for checking generated code in a Flutter package.
///
/// Creates a throwaway Flutter package with graphql_flutter and
/// flutter_hooks, writes generated sources and tests into it, then runs
/// `flutter pub get`, build_runner (optional), `flutter analyze` and
/// `flutter test`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'compile_harness.dart';

/// Path of the `flutter` executable on `PATH`, or null when there is none.
String? findFlutter() {
  final names =
      Platform.isWindows ? ['flutter.bat', 'flutter.exe'] : ['flutter'];
  final path = Platform.environment['PATH'] ?? '';
  for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    for (final name in names) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) return file.path;
    }
  }
  return null;
}

/// Writes [files] (package-relative path -> content) into a fresh Flutter
/// package and runs `flutter pub get`, build_runner when [buildRunner] is
/// set, `flutter analyze` and `flutter test`.
///
/// Analyzer errors anywhere and infos or warnings in `lib/` are reported as
/// errors; `flutter test` runs only when there are none.
Future<CompileResult> testInFlutterPackage(
  String flutter,
  Map<String, String> files, {
  bool buildRunner = false,
  Directory? workDir,
}) async {
  final dir = workDir ?? await Directory.systemTemp.createTemp('fgc_flutter_');
  final log = StringBuffer();

  Future<ProcessResult> run(List<String> args) async {
    final r = await Process.run(flutter, args,
        workingDirectory: dir.path, runInShell: Platform.isWindows);
    log
      ..writeln('\$ flutter ${args.join(' ')} (exit ${r.exitCode})')
      ..writeln(r.stdout)
      ..writeln(r.stderr);
    return r;
  }

  // The language version follows Flutter's Dart (see compile_harness.dart).
  final version = await run(['--version', '--machine']);
  String? dartVersion;
  try {
    final out = '${version.stdout}';
    final json = jsonDecode(out.substring(out.indexOf('{'))) as Map;
    dartVersion = json['dartSdkVersion'] as String?;
  } catch (_) {
    // Falls back to the oldest Dart the generator supports.
  }
  final sdk = (dartVersion ?? '3.4.0').split(' ').first.split('.');

  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fgc_flutter_check
publish_to: none
environment:
  sdk: ^${sdk[0]}.${sdk[1]}.0
dependencies:
  flutter:
    sdk: flutter
  flutter_hooks: ">=0.18.2 <0.21.0"
  graphql: ^5.2.0
  graphql_flutter: ^5.2.0
  json_annotation: ^4.8.1
dev_dependencies:
  flutter_test:
    sdk: flutter
${buildRunner ? '''
  build_runner: ^2.4.6
  json_serializable: ^6.7.1
  # See compile_harness.dart.
  source_helper: ">=1.3.0 <1.4.0"
''' : ''}''');
  File(p.join(dir.path, 'analysis_options.yaml')).writeAsStringSync('');

  for (final entry in files.entries) {
    final file = File(p.join(dir.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  var r = await run(['pub', 'get', '--offline']);
  if (r.exitCode != 0) r = await run(['pub', 'get']);
  if (r.exitCode != 0) {
    return CompileResult(false, ['flutter pub get failed'], log.toString());
  }

  final errors = <String>[];
  if (buildRunner) {
    r = await run([
      'pub',
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs'
    ]);
    if (r.exitCode != 0) errors.add('build_runner failed');
  }

  r = await run(['analyze', '--no-fatal-infos', '--no-fatal-warnings']);
  // `   info • Message • lib/a.dart:3:8 • code`
  final issue = RegExp(r'^(error|warning|info) • .* • (\S+?):\d+:\d+ • \S+$');
  for (final line in '${r.stdout}'.split('\n').map((l) => l.trim())) {
    final m = issue.firstMatch(line);
    if (m == null) continue;
    final path = m.group(2)!.replaceAll(r'\', '/');
    if (m.group(1) == 'error' || path.startsWith('lib/')) errors.add(line);
  }

  if (errors.isEmpty) {
    r = await run(['test', '--reporter', 'expanded']);
    if (r.exitCode != 0) {
      errors.add('flutter test failed:\n${r.stdout}\n${r.stderr}');
    }
  }

  if (workDir == null && errors.isEmpty) {
    await dir.delete(recursive: true);
  }
  return CompileResult(errors.isEmpty, errors, log.toString());
}
