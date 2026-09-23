import 'dart:convert';
import 'dart:io';

import 'qr_payload_parser.dart';

class SubscriptionFetcher {
  static Future<Set<String>> fetchLinks(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'AurumProxy/1.0');
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      var text = utf8.decode(bytes, allowMalformed: true).trim();
      final out = <String>{};
      _collectText(text, out);
      if (out.isNotEmpty) return out;

      // Most classic V2Ray subscriptions are a base64-encoded list of URIs.
      try {
        text = utf8.decode(base64.decode(base64.normalize(text))).trim();
        _collectText(text, out);
      } catch (_) {}
      return out;
    } finally {
      client.close(force: true);
    }
  }

  static void _collectText(String text, Set<String> out) {
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final value = line.trim();
      if (QrPayloadParser.looksLikeNode(value)) out.add(value);
    }
  }
}
