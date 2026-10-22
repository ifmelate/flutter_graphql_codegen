/// Operation groups (`group_operations: directory`): the operations of the
/// documents in one directory are reachable through a getter on
/// `GraphQLClient`, e.g. `client.users.getProfile()` for
/// `<documents root>/users/get_profile.graphql`.
///
/// Each group has a file with a small class wrapping the client
/// (`UsersOperations`) and an extension adding the getter (`client.users`).
/// Every operation file of the group adds its methods to that class with an
/// extension (`GetProfileInGroup`) that delegates to the operation's
/// `GraphQLClient` extension, so the group file only needs to know which
/// operation files belong to it. It exports them, so importing the group
/// file (or index.dart) is enough.
library;

import 'package:path/path.dart' as p;

import 'code_utils.dart';
import 'naming.dart';

/// The group of the operations in one documents directory.
class OperationGroup {
  OperationGroup._(this.path, this.name, this.className, this.fileName);

  /// Builds the group of directory [path] (POSIX, relative to the documents
  /// root, e.g. `users/admin`).
  ///
  /// The name joins the words of all directories in camelCase
  /// (`users/admin` -> `usersAdmin`, `user-profiles` -> `userProfiles`);
  /// words that are all capitals are lowercased (`API` -> `api`), and a name
  /// starting with a digit gets a `group` prefix (`2fa` -> `group2fa`).
  factory OperationGroup.fromPath(String path, {required String fileNaming}) {
    final words = [
      for (final segment in path.split('/'))
        for (final word in segment.split(RegExp('[^A-Za-z0-9]+')))
          if (word.isNotEmpty) word,
    ];
    var name = '';
    for (final (i, word) in words.indexed) {
      final shaped = word.toUpperCase() == word && word.length > 1
          ? word.toLowerCase()
          : word;
      name += i == 0 ? shaped.toCamelCase() : shaped.capitalize();
    }
    if (name.isEmpty || RegExp('^[0-9]').hasMatch(name)) {
      name = 'group${name.capitalize()}';
    }
    final className = '${name.capitalize()}Operations';
    return OperationGroup._(path, name, className,
        '${transformFileBaseName(className, fileNaming)}.dart');
  }

  /// The group of the document at package-relative [documentPath], or null
  /// when it is directly in [root] (or outside it, or [root] is null).
  static OperationGroup? forDocument(String documentPath, String? root,
      {required String fileNaming}) {
    if (root == null) return null;
    final dir = p.posix.dirname(documentPath);
    if (dir == root || !p.posix.isWithin(root, dir)) return null;
    return OperationGroup.fromPath(p.posix.relative(dir, from: root),
        fileNaming: fileNaming);
  }

  /// Directory of the documents, relative to the documents root.
  final String path;

  /// Name of the getter on `GraphQLClient`, before [getterName] escapes it.
  final String name;

  /// The class wrapping the client (`UsersOperations`).
  final String className;

  /// The group file, in the output directory.
  final String fileName;

  /// Name of the extension adding the getter to `GraphQLClient`.
  String get clientExtension => '${className}OnClient';

  /// Name of the extension adding operation [operationName] to the group.
  static String operationExtension(String operationName) =>
      '${operationName}InGroup';

  /// The getter name: [name], with a trailing underscore while it is a Dart
  /// reserved word or one of [taken] (members of `GraphQLClient` and the
  /// operations' extension methods on it, which the getter would clash
  /// with).
  String getterName(Set<String> taken) {
    var getter = name;
    while (dartReservedWords.contains(getter) || taken.contains(getter)) {
      getter = '${getter}_';
    }
    return getter;
  }

  /// Header line of an operation file in this group.
  String get operationHeader => '// Operation group: $path';

  /// Group directory recorded in the header of operation file [code], or
  /// null when the operation is not grouped.
  static String? groupOfOperationFile(String code) =>
      _operationHeader.firstMatch(code)?.group(1);

  /// Group directory recorded in the header of group file [code], or null
  /// when it is not a group file.
  static String? groupOfGroupFile(String code) =>
      _groupFileHeader.firstMatch(code)?.group(1);

  static final _operationHeader =
      RegExp(r'^// Operation group: (.+)$', multiLine: true);
  static final _groupFileHeader =
      RegExp(r'^// Operations of group: (.+)$', multiLine: true);

  /// The group file: the class, the getter on `GraphQLClient` named
  /// [getter], and exports of the operation files [operationFiles].
  String groupFile(String getter, List<String> operationFiles) {
    final exports = [...operationFiles]..sort();
    return '''
${CodeGenerationConstants.generatedFileWarning}
// Operations of group: $path
${CodeGenerationConstants.ignoreForFile}

import 'package:graphql/client.dart' as graphql;

${exports.map((f) => "export '$f';").join('\n')}

/// The operations of the documents in `$path`, as `client.$getter`.
///
/// Its methods are those of the operations' `GraphQLClient` extensions
/// (`client.$getter.getUser()` runs `client.getUser()`).
final class $className {
  const $className(this.client);

  /// The client the operations run on.
  final graphql.GraphQLClient client;
}

/// Adds [$className] to `GraphQLClient`.
extension $clientExtension on graphql.GraphQLClient {
  /// The operations of the documents in `$path`.
  $className get $getter => $className(this);
}
''';
  }
}

/// Characters that start a glob pattern in a path segment.
final _globChars = RegExp(r'[*?\[\]{}]');

/// The directory groups are relative to: the longest directory shared by the
/// literal parts of [patterns] (package-relative POSIX globs from
/// `document_paths`), e.g. `lib/graphql/documents` for
/// `lib/graphql/documents/**/*.graphql`. Null when there are no patterns.
String? documentsRoot(Iterable<String> patterns) {
  List<String>? common;
  for (final pattern in patterns) {
    final segments = pattern.split('/');
    final literal = segments.takeWhile((s) => !s.contains(_globChars)).toList();
    // A pattern without wildcards names a file.
    if (literal.length == segments.length) literal.removeLast();
    if (common == null) {
      common = literal;
    } else {
      var i = 0;
      while (
          i < common.length && i < literal.length && common[i] == literal[i]) {
        i++;
      }
      common = common.sublist(0, i);
    }
  }
  if (common == null) return null;
  final root = common.where((s) => s.isNotEmpty && s != '.').join('/');
  return root.isEmpty ? '.' : root;
}
