library;

/// Global configuration context to be used by static generators
class CodegenConfigContext {
  static String fileNaming = 'snake_case';
  static bool strictNullability = false;
  static bool emitIndex = true;
  static String diagnosticsFormat = 'plain';
  static Map<String, String> scalarMapping = <String, String>{};

  /// Resets all fields to defaults. Useful for tests and watch-mode rebuilds.
  static void reset() {
    fileNaming = 'snake_case';
    strictNullability = false;
    emitIndex = true;
    diagnosticsFormat = 'plain';
    scalarMapping = <String, String>{};
  }
}
