import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'open_food_facts_source.dart' show HttpReply;

export 'open_food_facts_source.dart' show HttpReply, HttpFetch;

/// HTTP GET with a hard time limit per attempt and one retry on network
/// failures. Slow mobile networks often fail the first attempt.
Future<HttpReply> robustHttpFetch(Uri uri) async {
  Object? lastError;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      return await _once(uri).timeout(const Duration(seconds: 10));
    } on TimeoutException catch (e) {
      lastError = e;
    } on SocketException catch (e) {
      lastError = e;
    } on HandshakeException catch (e) {
      lastError = e;
    } on HttpException catch (e) {
      lastError = e;
    }
    if (attempt == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  throw lastError ?? const SocketException('Network unavailable');
}

Future<HttpReply> _once(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 7)
    ..idleTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(uri);
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'EXALTED/1.0 (barcode scanner)',
    );
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      if (builder.length + chunk.length > 1024 * 1024) {
        throw const FormatException('Response exceeded the 1 MB limit.');
      }
      builder.add(chunk);
    }
    return HttpReply(
      res.statusCode,
      utf8.decode(builder.takeBytes(), allowMalformed: true),
    );
  } finally {
    client.close(force: true);
  }
}


