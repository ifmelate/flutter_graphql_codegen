import 'package:test/test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:flutter_graphql_codegen/src/code_utils.dart';
import 'package:flutter_graphql_codegen/src/schema_analyzer.dart';
import 'package:flutter_graphql_codegen/src/type_generator.dart';

void main() {
  group('Type Nullability Tests', () {
    setUp(() {
      // Clear type registry before each test
      TypeRegistry.clear();
    });

    test('isNonNull extension should correctly detect non-null types', () {
      final schema = '''
      type RepertorySymptomDTO {
        hasChildren: Boolean!
        isRegistered: Boolean!
        nullableBool: Boolean
        requiredString: String!
        nullableString: String
        requiredInt: Int!
        nullableInt: Int
      }
      ''';

      final schemaDoc = gql_lang.parseString(schema);
      final typeDef = schemaDoc.definitions.first as ObjectTypeDefinitionNode;

      // Test each field type
      final hasChildrenField = typeDef.fields[0]; // Boolean!
      final isRegisteredField = typeDef.fields[1]; // Boolean!
      final nullableBoolField = typeDef.fields[2]; // Boolean
      final requiredStringField = typeDef.fields[3]; // String!
      final nullableStringField = typeDef.fields[4]; // String
      final requiredIntField = typeDef.fields[5]; // Int!
      final nullableIntField = typeDef.fields[6]; // Int

      expect(hasChildrenField.type.isNonNull, isTrue,
          reason: 'hasChildren should be non-null (Boolean!)');
      expect(isRegisteredField.type.isNonNull, isTrue,
          reason: 'isRegistered should be non-null (Boolean!)');
      expect(nullableBoolField.type.isNonNull, isFalse,
          reason: 'nullableBool should be nullable (Boolean)');
      expect(requiredStringField.type.isNonNull, isTrue,
          reason: 'requiredString should be non-null (String!)');
      expect(nullableStringField.type.isNonNull, isFalse,
          reason: 'nullableString should be nullable (String)');
      expect(requiredIntField.type.isNonNull, isTrue,
          reason: 'requiredInt should be non-null (Int!)');
      expect(nullableIntField.type.isNonNull, isFalse,
          reason: 'nullableInt should be nullable (Int)');
    });

    test('getDartType should respect GraphQL type nullability', () {
      final schema = '''
      type RepertorySymptomDTO {
        hasChildren: Boolean!
        isRegistered: Boolean!
        nullableBool: Boolean
        requiredString: String!
        nullableString: String
        requiredList: [String!]!
        nullableList: [String]
      }
      ''';

      final schemaDoc = gql_lang.parseString(schema);
      final typeDef = schemaDoc.definitions.first as ObjectTypeDefinitionNode;

      // Test getDartType for each field
      final hasChildrenType =
          SchemaAnalyzer.getDartType(typeDef.fields[0].type);
      final isRegisteredType =
          SchemaAnalyzer.getDartType(typeDef.fields[1].type);
      final nullableBoolType =
          SchemaAnalyzer.getDartType(typeDef.fields[2].type);
      final requiredStringType =
          SchemaAnalyzer.getDartType(typeDef.fields[3].type);
      final nullableStringType =
          SchemaAnalyzer.getDartType(typeDef.fields[4].type);
      final requiredListType =
          SchemaAnalyzer.getDartType(typeDef.fields[5].type);
      final nullableListType =
          SchemaAnalyzer.getDartType(typeDef.fields[6].type);

      expect(hasChildrenType, equals('bool'),
          reason: 'Boolean! should map to bool (non-nullable)');
      expect(isRegisteredType, equals('bool'),
          reason: 'Boolean! should map to bool (non-nullable)');
      expect(nullableBoolType, equals('bool?'),
          reason: 'Boolean should map to bool? (nullable)');
      expect(requiredStringType, equals('String'),
          reason: 'String! should map to String (non-nullable)');
      expect(nullableStringType, equals('String?'),
          reason: 'String should map to String? (nullable)');
      expect(requiredListType, equals('List<String>?'),
          reason: 'All lists are made nullable for graceful null handling');
      expect(nullableListType, equals('List<String?>?'),
          reason: 'Nullable list with nullable items');
    });

    test('full type generation should produce correct nullability', () {
      final schema = '''
      type RepertorySymptomDTO {
        hasChildren: Boolean!
        isRegistered: Boolean!
        nullableBool: Boolean
        name: String!
        description: String
        id: Int!
        rating: Float
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Non-nullable fields should now use safe converters instead of being made nullable
      expect(generatedCode, contains('@SafeBoolConverter()'),
          reason: 'Non-nullable boolean fields should use SafeBoolConverter');
      expect(generatedCode, contains('@SafeIntConverter()'),
          reason: 'Non-nullable int fields should use SafeIntConverter');

      // Check that non-null fields are marked as required in constructor
      expect(generatedCode, contains('required this.hasChildren,'),
          reason: 'hasChildren (Boolean!) should be required');
      expect(generatedCode, contains('required this.isRegistered,'),
          reason: 'isRegistered (Boolean!) should be required');
      expect(generatedCode, contains('required this.name,'),
          reason: 'name (String!) should be required');
      expect(generatedCode, contains('required this.id,'),
          reason: 'id (Int!) should be required');

      // Check that nullable fields are NOT marked as required
      expect(generatedCode, contains('this.nullableBool,'),
          reason: 'nullableBool (Boolean) should not be required');
      expect(generatedCode, contains('this.description,'),
          reason: 'description (String) should not be required');
      expect(generatedCode, contains('this.rating,'),
          reason: 'rating (Float) should not be required');

      // Check field type declarations - now fields keep their original types
      expect(generatedCode, contains('bool hasChildren;'),
          reason: 'hasChildren should be bool (converter handles safety)');
      expect(generatedCode, contains('bool isRegistered;'),
          reason: 'isRegistered should be bool (converter handles safety)');
      expect(generatedCode, contains('bool? nullableBool;'),
          reason: 'nullableBool should be bool? (nullable)');
      expect(generatedCode, contains('String name;'),
          reason: 'name should be String (non-nullable)');
      expect(generatedCode, contains('String? description;'),
          reason: 'description should be String? (nullable)');
      expect(generatedCode, contains('int id;'),
          reason: 'id should be int (converter handles safety)');
      expect(generatedCode, contains('double? rating;'),
          reason: 'rating should be double? (nullable)');

      // Check that safe converters are included
      expect(generatedCode, contains('class SafeBoolConverter'),
          reason: 'Should include SafeBoolConverter class');
      expect(generatedCode, contains('class SafeIntConverter'),
          reason: 'Should include SafeIntConverter class');
    });

    test('nested types with nullability should work correctly', () {
      final schema = '''
      type Query {
        symptom: RepertorySymptomDTO!
        optionalSymptom: RepertorySymptomDTO
      }
      
      type RepertorySymptomDTO {
        hasChildren: Boolean!
        isRegistered: Boolean!
        nullableBool: Boolean
        childSymptoms: [RepertorySymptomDTO!]!
        optionalChildSymptoms: [RepertorySymptomDTO]
      }
      ''';

      final generatedCode = TypeGenerator.generateTypesFile(schema);

      // Check Query type fields
      expect(generatedCode, contains('required this.symptom,'),
          reason: 'symptom (RepertorySymptomDTO!) should be required');
      expect(generatedCode, contains('this.optionalSymptom,'),
          reason:
              'optionalSymptom (RepertorySymptomDTO) should not be required');

      // Check list types - all lists are made nullable for graceful handling
      expect(
          generatedCode, contains('List<RepertorySymptomDTO>? childSymptoms;'),
          reason:
              'childSymptoms should be List<RepertorySymptomDTO>? even if defined as non-null list');
      expect(generatedCode,
          contains('List<RepertorySymptomDTO?>? optionalChildSymptoms;'),
          reason:
              'optionalChildSymptoms should be List<RepertorySymptomDTO?>?');
    });

    test('TypeNodeExtensions with parsed GraphQL schema', () {
      // Test our extension with real parsed GraphQL types
      final schema = '''
      type TestType {
        nonNullField: String!
        nullableField: String
      }
      ''';

      final schemaDoc = gql_lang.parseString(schema);
      final typeDef = schemaDoc.definitions.first as ObjectTypeDefinitionNode;

      final nonNullField = typeDef.fields[0]; // String!
      final nullableField = typeDef.fields[1]; // String

      expect(nonNullField.type.isNonNull, isTrue,
          reason: 'String! field should be detected as non-null');
      expect(nullableField.type.isNonNull, isFalse,
          reason: 'String field should be detected as nullable');
    });
  });
}
