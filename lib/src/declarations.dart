/// Public top-level names of generated Dart files.
library;

/// GraphQL documents are embedded as raw triple-quoted strings; their lines
/// (`query X(...) {`) start at column 0 too.
final _rawStrings = RegExp(r'r?"""[\s\S]*?"""');

/// A top-level declaration in generated code: it starts at column 0, both in
/// the generator's output and after `dart format`, which may put the name
/// on its own line after a long type (`const String\nname =`,
/// `graphql.QueryOptions<\n  X?\n>\nname(`).
final _declaration = RegExp(
  r'^(?:(?:abstract |sealed |final |base |interface |mixin )*class'
  r'|extension|enum|typedef|mixin)\s+(\w+)'
  r'|^(?:final|const|var)(?:\s+[\w<>?,.\s]+?)?\s+(\w+)\s*='
  r'|^[A-Za-z][\w<>?,.\s]*\s(\w+)\(',
  multiLine: true,
);

/// Public names declared at the top level of generated [code], in order;
/// a name declared twice is listed twice.
List<String> topLevelDeclarations(String code) => [
      for (final m in _declaration.allMatches(code.replaceAll(_rawStrings, '')))
        if ((m.group(1) ?? m.group(2) ?? m.group(3))! case final name
            when !name.startsWith('_'))
          name,
    ];
