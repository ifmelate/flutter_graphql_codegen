// migrate: graphql_codegen.yaml from the build.yaml options of Artemis or
// graphql_codegen.
import 'dart:io';

import 'package:flutter_graphql_codegen/src/config.dart';
import 'package:flutter_graphql_codegen/src/migrate_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _artemis = r'''
targets:
  $default:
    sources:
      - lib/**
      - graphql/**
    builders:
      artemis:
        options:
          fragments_glob: graphql/fragments/**.graphql
          scalar_mapping:
            - graphql_type: Date
              dart_type: DateTime
            - graphql_type: BigDecimal
              custom_parser_import: package:app/coercers.dart
              dart_type:
                name: Decimal
                imports:
                  - package:decimal/decimal.dart
            - graphql_type: Upload
              custom_parser_import: package:app/coercers.dart
              dart_type: MultipartFile
          schema_mapping:
            - schema: graphql/schema.graphql
              queries_glob: graphql/queries/**.graphql
              output: lib/graphql/api.graphql.dart
              naming_scheme: pathedWithFields
''';

const _graphqlCodegen = r'''
targets:
  $default:
    builders:
      graphql_codegen:
        options:
          assetsPath: graphql/**.graphql
          outputDirectory: /lib/__generated
          clients:
            - graphql
            - graphql_flutter
          scalars:
            ISODateTime:
              type: DateTime
            JSON:
              type: Map<String, dynamic>
            Money:
              type: Money
              fromJsonFunctionName: moneyFromJson
              toJsonFunctionName: moneyToJson
              import: package:app/money.dart
          enums:
            Status:
              fallbackEnumValue: OTHER
            Role:
              type: AppRole
              fromJsonFunctionName: roleFromJson
              toJsonFunctionName: roleToJson
              import: package:app/role.dart
          namingSeparator: ___
''';

/// The written config, parsed the way the builder parses it.
GraphQLCodegenConfig _parse(Migration m) {
  final config = GraphQLCodegenConfig.fromYaml(m.config);
  expect(config.warnings, isEmpty, reason: m.config);
  return config;
}

void main() {
  group('from Artemis', () {
    late Migration migration;
    late GraphQLCodegenConfig config;
    setUpAll(() {
      migration = migrateBuildYaml(_artemis);
      config = _parse(migration);
    });

    test('takes the schema, the documents and the output directory', () {
      expect(migration.from, 'artemis');
      expect(config.schemaUrl, 'graphql/schema.graphql');
      expect(config.documentPaths, [
        'graphql/queries/**.graphql',
        'graphql/fragments/**.graphql',
      ]);
      expect(config.outputDir, 'lib/graphql/generated');
      expect(config.strictNullability, isTrue);
      expect(config.unknownEnumFallback, isTrue);
    });

    test('maps scalars, coercers to from_json/to_json', () {
      expect(config.scalarMapping, {
        'Date': 'DateTime',
        'BigDecimal': 'Decimal',
        'Upload': 'MultipartFile'
      });
      expect(config.scalarFunctions['Upload']?.fromJson,
          'fromGraphQLUploadToDartMultipartFile');
      expect(config.scalarFunctions['Upload']?.toJson,
          'fromDartMultipartFileToGraphQLUpload');
      expect(config.scalarImports['BigDecimal'], 'package:app/coercers.dart');
    });

    test('takes the shared parser import of older Artemis versions', () {
      final m = migrateBuildYaml(r'''
targets:
  $default:
    builders:
      artemis:
        options:
          custom_parser_import: package:app/coercers.dart
          scalar_mapping:
            - {graphql_type: Date, dart_type: DateTime, use_custom_parser: true}
            - {graphql_type: MBID, dart_type: String}
          schema_mapping:
            - {schema: s.graphql, queries_glob: q.graphql, output: lib/q.dart}
''');
      final config = _parse(m);
      expect(config.scalarFunctions['Date']?.fromJson,
          'fromGraphQLDateToDartDateTime');
      expect(config.scalarImports['Date'], 'package:app/coercers.dart');
      expect(config.scalarFunctions, isNot(contains('MBID')));
      expect(config.scalarMapping['MBID'], 'String');
    });

    test('lists what to check by hand', () {
      final notes = migration.notes.join('\n');
      expect(notes, contains('lib/graphql/generated/index.dart'));
      expect(notes, contains('naming_scheme: pathedWithFields'));
      expect(notes, contains('ArtemisClient'));
      expect(notes, contains('artemisUnknown'));
      expect(notes, contains('Export package:decimal/decimal.dart'));
    });

    test('refuses several schemas', () {
      expect(
          () => migrateBuildYaml(r'''
targets:
  $default:
    builders:
      artemis:
        options:
          schema_mapping:
            - {schema: a.graphql, queries_glob: a/**.graphql, output: lib/a.dart}
            - {schema: b.graphql, queries_glob: b/**.graphql, output: lib/b.dart}
'''),
          throwsA(isA<MigrationException>().having((e) => e.message, 'message',
              contains('one schema per package'))));
    });
  });

  group('from graphql_codegen', () {
    late Migration migration;
    late GraphQLCodegenConfig config;
    setUpAll(() {
      migration = migrateBuildYaml(_graphqlCodegen,
          schemaFiles: (glob) =>
              glob == 'graphql/**.graphql' ? ['graphql/schema.graphql'] : []);
      config = _parse(migration);
    });

    test('finds the schema among the documents', () {
      expect(migration.from, 'graphql_codegen');
      expect(config.schemaUrl, 'graphql/schema.graphql');
      expect(config.documentPaths, ['graphql/**.graphql']);
      expect(config.outputDir, 'lib/__generated');
    });

    test('turns graphql_flutter into widgets and hooks', () {
      expect(config.flutterWidgets, isTrue);
      expect(config.flutterHooks, isTrue);
      expect(config.unknownEnumFallback, isTrue);
    });

    test('maps scalars and enums', () {
      expect(config.scalarMapping['ISODateTime'], 'DateTime');
      expect(config.scalarMapping['JSON'], 'Map<String, dynamic>');
      expect(config.scalarFunctions['Money']?.fromJson, 'moneyFromJson');
      expect(config.scalarImports['Money'], 'package:app/money.dart');
      expect(config.enums['Status']?.fallback, 'OTHER');
      expect(config.enums['Role']?.type, 'AppRole');
      expect(config.enums['Role']?.fromJson, 'roleFromJson');
    });

    test('lists what to check by hand', () {
      final notes = migration.notes.join('\n');
      expect(notes, contains('GetUser_User'));
      expect(notes, contains('useGetUserQuery'));
      expect(notes, contains('namingSeparator'));
    });

    test('says when the schema is not found', () {
      final m = migrateBuildYaml(_graphqlCodegen, schemaFiles: (_) => []);
      expect(m.notes.join('\n'), contains('No schema file found'));
    });

    test('refuses several scopes', () {
      expect(() => migrateBuildYaml(r'''
targets:
  $default:
    builders:
      graphql_codegen:
        options:
          scopes: [lib/a/**, lib/b/**]
''', schemaFiles: (_) => []), throwsA(isA<MigrationException>()));
    });
  });

  test('refuses a build.yaml without either generator', () {
    expect(() => migrateBuildYaml('targets: {}'),
        throwsA(isA<MigrationException>()));
  });

  group('runMigrate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fgc_migrate_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<(int, String, String)> run(List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code =
          await runMigrate(args, stdout: out, stderr: err, root: dir.path);
      return (code, '$out', '$err');
    }

    test('writes the config and the steps, and keeps an existing file',
        () async {
      File(p.join(dir.path, 'build.yaml')).writeAsStringSync(_graphqlCodegen);
      Directory(p.join(dir.path, 'graphql')).createSync();
      File(p.join(dir.path, 'graphql', 'schema.graphql'))
          .writeAsStringSync('type Query { a: Int }');
      File(p.join(dir.path, 'graphql', 'a.graphql'))
          .writeAsStringSync('query A { a }');

      final (code, out, _) = await run([]);
      expect(code, 0);
      expect(out, contains('Check by hand:'));
      final written = File(p.join(dir.path, 'graphql_codegen.yaml'));
      expect(
          GraphQLCodegenConfig.fromYaml(written.readAsStringSync()).schemaUrl,
          'graphql/schema.graphql');

      final (again, _, err) = await run([]);
      expect(again, 1);
      expect(err, contains('--force'));
      expect((await run(['--force'])).$1, 0);
    });

    test('--from picks one generator when build.yaml has both', () async {
      File(p.join(dir.path, 'build.yaml')).writeAsStringSync(
          '$_artemis      graphql_codegen:\n        options: {}\n');
      final (code, _, err) = await run([]);
      expect(code, 1);
      expect(err, contains('--from'));
      final (picked, out, _) = await run(['--from', 'artemis']);
      expect(picked, 0, reason: out);
      expect(out, contains('from the artemis options'));
    });

    test('reports a missing build.yaml as wrong usage', () async {
      expect((await run([])).$1, 64);
    });
  });
}
