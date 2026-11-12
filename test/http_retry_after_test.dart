import 'package:exalted/verify/http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uri = 'https://verification.example.test/item';

  test('a zero second Retry-After allows one bounded retry', () async {
    var calls = 0;
    final result = await fetchRespectingRetryAfter((_) async {
      calls++;
      return calls == 1
          ? const HttpReply(429, '', headers: {'Retry-After': '0'})
          : const HttpReply(200, 'ok');
    }, Uri.parse(uri));

    expect(calls, 2);
    expect(result.statusCode, 200);
  });

  test('a long Retry-After is never retried early', () async {
    var calls = 0;
    final result = await fetchRespectingRetryAfter(
      (_) async {
        calls++;
        return const HttpReply(429, '', headers: {'retry-after': '30'});
      },
      Uri.parse(uri),
      maximumWait: const Duration(seconds: 1),
    );

    expect(calls, 1);
    expect(result.statusCode, 429);
  });

  test('429 without Retry-After is not retried', () async {
    var calls = 0;
    final result = await fetchRespectingRetryAfter((_) async {
      calls++;
      return const HttpReply(429, '');
    }, Uri.parse(uri));

    expect(calls, 1);
    expect(result.statusCode, 429);
  });

  test('HTTP-date Retry-After is recognized', () async {
    var calls = 0;
    final result = await fetchRespectingRetryAfter(
      (_) async {
        calls++;
        return const HttpReply(
          429,
          '',
          headers: {'Retry-After': 'Wed, 21 Oct 2015 07:28:00 GMT'},
        );
      },
      Uri.parse(uri),
      clock: () => DateTime.utc(2015, 10, 21, 7, 29),
    );

    expect(calls, 2);
    expect(result.statusCode, 429);
  });
}
