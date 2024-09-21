import 'package:http/http.dart' as http;

class SchemaDownloader {
  static Future<String> downloadSchema(String url) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body:
          '{"operationName":"IntrospectionQuery","query":"query IntrospectionQuery {  __type(name: \"__Schema\") {    name    fields {      name    }  }}"}',
    );

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception(
          'Failed to download schema: ${response.statusCode} and response body: ${response.body}');
    }
  }
}
