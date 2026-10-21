library;

/// Global configuration context to be used by static generators
class CodegenConfigContext {
  static String fileNaming = 'snake_case';
  static bool strictNullability = false;
  static bool emitIndex = true;
  static String diagnosticsFormat = 'plain';
  static Map<String, String> scalarMapping = <String, String>{};
  static bool unknownEnumFallback = false;
  static bool deprecatedAnnotations = false;
  static bool validateDocuments = true;
  static Map<String, String> scalarImports = <String, String>{};
  static Map<String, String> scalarConverters = <String, String>{};
  static bool strictScalars = false;
  static bool includeNullInputs = false;

  /// `operation` or `schema`, see `GraphQLCodegenConfig.resultTypes`.
  static String resultTypes = 'operation';

  /// Whether result classes are generated per operation.
  static bool get operationResultTypes => resultTypes == 'operation';

  /// Resets all fields to defaults. Useful for tests and watch-mode rebuilds.
  static void reset() {
    fileNaming = 'snake_case';
    strictNullability = false;
    emitIndex = true;
    diagnosticsFormat = 'plain';
    scalarMapping = <String, String>{};
    unknownEnumFallback = false;
    deprecatedAnnotations = false;
    validateDocuments = true;
    scalarImports = <String, String>{};
    scalarConverters = <String, String>{};
    strictScalars = false;
    includeNullInputs = false;
    resultTypes = 'operation';
  }
}
