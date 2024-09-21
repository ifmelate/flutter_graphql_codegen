import 'dart:convert';
import 'dart:io';

class SchemaDownloader {
  static Future<String> downloadSchema(String url) async {
    HttpClient client = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);

    final request = await client.postUrl(Uri.parse(url));
    request.headers.set('Content-Type', 'application/json');
    request.write(
        '{"query": "{ __schema { types { name kind description fields { name type { name kind ofType { name kind } } } } } }"}');

    final response = await request.close();

    if (response.statusCode == 200) {
      return await response.transform(utf8.decoder).join();
    } else {
      throw Exception('Failed to download schema: ${response.statusCode}');
    }
  }
}
