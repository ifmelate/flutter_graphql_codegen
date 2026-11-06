import 'dart:io';

import 'package:flutter_graphql_codegen/src/migrate_command.dart';

/// `dart run flutter_graphql_codegen:migrate --help`
Future<void> main(List<String> args) async {
  exitCode = await runMigrate(args);
}
