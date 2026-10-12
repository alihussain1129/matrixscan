import 'dart:async';
import 'dart:convert';

import 'package:exalted/interpret/default_registry.dart';
import 'package:exalted/interpret/interpreter.dart';
import 'package:exalted/verify/open_food_facts_source.dart';
import 'package:flutter_test/flutter_test.dart';

final _registry = defaultInterpreterRegistry();

const _gs1 = '(01)04006381333931(17)270924(10)ABC123(21)XYZ789';

Interpretation _interpretation() => _registry.interpret(
  const ScanPayload(raw: _gs1, symbology: 'Data Matrix', source: 'live'),
);

final _found = jsonEncode({
  'status': 1,
  'code': '4006381333931',
  'product': {
    'code': '4006381333931',
    'product_name': 'Test Biscuit',
    'brands': 'Acme',
    'quantity': '200 g',
    'allergens_tags': ['en:gluten', 'en:milk'],
    'nutriments': {'sugars_100g': 12.5},
    'last_modified_t': 1700000000,
  },
});

void main() {
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 10, 10);
  });

  test('successful record is cached and checkedAt is refreshed', () async {
    var calls = 0;
    final source = OpenFoodFactsSource(
      clock: () => now,
      fetch: (_) async {
        calls++;
        return HttpReply(200, _found);
      },
    );

    final first = await source.check(_interpretation());
    now = now.add(const Duration(minutes: 1));
    final second = await source.check(_interpretation());

    expect(calls, 1);
    expect(first.claims, isNotEmpty);
    expect(second.checkedAt, now);
    expect(second.fields.length, first.fields.length);
    expect(second.dataUpdatedAt, first.dataUpdatedAt);
  });

  test('cached record expires after five minutes', () async {
    var calls = 0;
    final source = OpenFoodFactsSource(
      clock: () => now,
      fetch: (_) async {
        calls++;
        return HttpReply(200, _found);
      },
    );

    await source.check(_interpretation());
    now = now.add(const Duration(minutes: 5));
    await source.check(_interpretation());

    expect(calls, 2);
  });

  test('concurrent checks for the same GTIN share one request', () async {
    var calls = 0;
    final response = Completer<HttpReply>();

    final source = OpenFoodFactsSource(
      clock: () => now,
      fetch: (_) {
        calls++;
        return response.future;
      },
    );

    final firstFuture = source.check(_interpretation());
    final secondFuture = source.check(_interpretation());

    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    response.complete(HttpReply(200, _found));
    final results = await Future.wait([firstFuture, secondFuture]);

    expect(calls, 1);
    expect(results, hasLength(2));
    expect(results[0].claims, isNotEmpty);
    expect(results[1].claims, isNotEmpty);
  });

  test('temporary HTTP failure is not cached', () async {
    var calls = 0;
    final source = OpenFoodFactsSource(
      clock: () => now,
      fetch: (_) async {
        calls++;
        if (calls == 1) {
          return const HttpReply(503, '{"status":1}');
        }
        return HttpReply(200, _found);
      },
    );

    final first = await source.check(_interpretation());
    final second = await source.check(_interpretation());

    expect(calls, 2);
    expect(first.error, isNotNull);
    expect(second.fields, isNotEmpty);
  });

  test('not-found response is cached', () async {
    var calls = 0;
    final source = OpenFoodFactsSource(
      clock: () => now,
      fetch: (_) async {
        calls++;
        return const HttpReply(
          200,
          '{"status":0,"status_verbose":"product not found"}',
        );
      },
    );

    final first = await source.check(_interpretation());
    now = now.add(const Duration(minutes: 1));
    final second = await source.check(_interpretation());

    expect(calls, 1);
    expect(first.claims, isNotEmpty);
    expect(second.checkedAt, now);
  });
}
