import 'package:http/http.dart' as http;

class SchemaDownloader {
  static Future<String> downloadSchema(String url) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body:
          '{"query": "{ __schema { types { name kind description fields { name type { name kind ofType { name kind } } } } } }"}',
    );

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to download schema: ${response.statusCode}');
    }
  }
}
