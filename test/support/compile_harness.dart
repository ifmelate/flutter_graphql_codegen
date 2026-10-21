/// Helpers for verifying that generated code actually compiles.
///
/// Creates a throwaway Dart package, writes generated sources into it, runs
/// json_serializable via build_runner and then `dart analyze`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class CompileResult {
  final bool ok;
  final List<String> errors;
  final String log;

  CompileResult(this.ok, this.errors, this.log);
}

/// Writes [files] (package-relative path -> content) into a fresh package,
/// runs build_runner and dart analyze and returns analyzer errors.
///
/// Analyzer infos and warnings are reported as errors too for files where
/// [mustBeClean] returns true (by default everything under `lib/`).
///
/// Each of [runScripts] (package-relative paths) is then executed with
/// `dart run`; a non-zero exit code is reported as an error.
Future<CompileResult> compileGenerated(
  Map<String, String> files, {
  Directory? workDir,
  List<String> runScripts = const [],
  bool Function(String path)? mustBeClean,
}) async {
  final clean = mustBeClean ?? (path) => path.startsWith('lib/');
  final dir = workDir ?? await Directory.systemTemp.createTemp('fgc_compile_');
  final log = StringBuffer();
  // The package's language version follows the running SDK: json_serializable
  // 6.10+ (picked on newer SDKs) emits null-aware elements, which need 3.8.
  final sdk = Platform.version.split(' ').first.split('.');

  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: fgc_compile_check
publish_to: none
environment:
  sdk: ^${sdk[0]}.${sdk[1]}.0
dependencies:
  graphql: ^5.1.3
  json_annotation: ^4.8.1
dev_dependencies:
  build_runner: ^2.4.6
  json_serializable: ^6.7.1
  # source_helper 1.4.0 breaks json_serializable 6.14.1, the newest one for
  # Dart < 3.12 (constructorByName is defined twice).
  source_helper: ">=1.3.0 <1.4.0"
''');
  File(p.join(dir.path, 'analysis_options.yaml')).writeAsStringSync('');

  for (final entry in files.entries) {
    final file = File(p.join(dir.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  Future<ProcessResult> run(List<String> args) async {
    final r = await Process.run(Platform.resolvedExecutable, args,
        workingDirectory: dir.path);
    log
      ..writeln('\$ dart ${args.join(' ')} (exit ${r.exitCode})')
      ..writeln(r.stdout)
      ..writeln(r.stderr);
    return r;
  }

  var r = await run(['pub', 'get', '--offline']);
  if (r.exitCode != 0) r = await run(['pub', 'get']);
  if (r.exitCode != 0) {
    return CompileResult(false, ['pub get failed'], log.toString());
  }

  r = await run(
      ['run', 'build_runner', 'build', '--delete-conflicting-outputs']);
  final buildErrors = <String>[];
  if (r.exitCode != 0) {
    buildErrors.add('build_runner failed');
  }

  r = await run(['analyze', '--no-fatal-warnings', '.']);
  final issue = RegExp(r'^(?:info|warning) - (\S+?):\d+');
  final errors = [
    ...buildErrors,
    ...'${r.stdout}'.split('\n').map((l) => l.trim()).where((l) {
      if (l.startsWith('error -')) return true;
      final path = issue.firstMatch(l)?.group(1);
      return path != null && clean(path.replaceAll(r'\', '/'));
    }),
  ];

  if (errors.isEmpty) {
    for (final script in runScripts) {
      r = await run(['run', script]);
      if (r.exitCode != 0) {
        errors.add('$script failed: ${r.stdout}\n${r.stderr}');
      }
    }
  }

  if (workDir == null && errors.isEmpty) {
    await dir.delete(recursive: true);
  }
  return CompileResult(errors.isEmpty, errors, log.toString());
}
