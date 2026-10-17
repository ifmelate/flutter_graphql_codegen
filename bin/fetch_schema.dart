import 'dart:io';

import 'package:flutter_graphql_codegen/src/fetch_schema_command.dart';

/// `dart run flutter_graphql_codegen:fetch_schema --help`
Future<void> main(List<String> args) async {
  exitCode = await runFetchSchema(args);
}
