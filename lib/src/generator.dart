import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'parser.dart';

class GraphQLCodeGenerator {
  static String generateClientCode(String schema, List<String> documents) {
    final operations =
        documents.expand((doc) => GraphQLParser.parseOperations(doc)).toList();

    final clientClass = Class((b) => b
      ..name = 'GeneratedGraphQLClient'
      ..fields.add(Field((f) => f
        ..name = '_client'
        ..type = refer('GraphQLClient')
        ..modifier = FieldModifier.final$))
      ..constructors.add(Constructor((c) => c
        ..requiredParameters.add(Parameter((p) => p
          ..name = 'url'
          ..type = refer('String')))
        ..initializers.add(Code(
            "_client = GraphQLClient(link: HttpLink(url), cache: GraphQLCache())"))))
      ..methods.addAll(operations.map(_generateMethod)));

    final library = Library((b) => b
      ..directives
          .add(Directive.import('package:graphql_flutter/graphql_flutter.dart'))
      ..body.add(clientClass));

    final emitter = DartEmitter();
    return DartFormatter().format('${library.accept(emitter)}');
  }

  static Method _generateMethod(GraphQLOperation operation) {
    return Method((m) => m
      ..name = operation.name.toLowerCase()
      ..returns = refer('Future<QueryResult>')
      ..modifier = MethodModifier.async
      ..body = Code('''
        final options = ${_getOptionsType(operation.type)}(
          document: gql(r"""
            ${operation.content}
          """),
        );
        return await _client.${_getClientMethod(operation.type)}(options);
      '''));
  }

  static String _getOptionsType(String type) {
    switch (type) {
      case 'query':
        return 'QueryOptions';
      case 'mutation':
        return 'MutationOptions';
      case 'subscription':
        return 'SubscriptionOptions';
      default:
        return 'QueryOptions';
    }
  }

  static String _getClientMethod(String type) {
    switch (type) {
      case 'query':
        return 'query';
      case 'mutation':
        return 'mutate';
      case 'subscription':
        return 'subscribe';
      default:
        return 'query';
    }
  }
}
