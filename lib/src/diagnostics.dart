/// Diagnostics utilities and structured exceptions for code generation
library;

import 'dart:convert';

/// Known error codes for the code generator
class CodegenErrorCodes {
  static const String cfgMissingSchema = 'CFG001';
  static const String cfgMissingDocuments = 'CFG002';
  static const String cfgInvalid = 'CFG999';

  static const String schemaFileNotFound = 'SCH404';
  static const String schemaInvalid = 'SCH400';
  static const String schemaDownloadFailed = 'SCH500';

  static const String buildOperationParse = 'BLD100';
  static const String buildIndexFailed = 'BLD200';
}

/// Structured exception with error code and optional cause
class CodegenException implements Exception {
  final String code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  CodegenException(this.code, this.message, {this.cause, this.stackTrace});

  @override
  String toString() => '[$code] $message';

  /// Formats the error for different consumers (plain or json)
  String format({String format = 'plain'}) {
    if (format.toLowerCase() == 'json') {
      final map = {
        'code': code,
        'message': message,
        if (cause != null) 'cause': cause.toString(),
      };
      return jsonEncode(map);
    }
    return toString();
  }
}
