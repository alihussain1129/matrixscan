import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:exalted/features/devices/core/reconnect_backoff.dart';
import 'package:exalted/features/devices/keyence/keyence_sr751_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// A timer that only fires when the test says so. No wall-clock waiting.
class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _cancelled = false;
  bool _fired = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled && !_fired;

  @override
  int get tick => _fired ? 1 : 0;

  void fire() {
    if (!isActive) return;
    _fired = true;
    _callback();
  }
}

/// Scripted network: connect attempts fail while [failing] is true, otherwise
/// they open a real loopback socket to [port].
class _Net {
  _Net(this.port);

  final int port;
  bool failing = true;
  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  Future<Socket> connect(String host, int port, Duration timeout) async {
    calls++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      // Yield so overlapping attempts would be observable.
      await Future<void>.delayed(Duration.zero);
      if (failing) {
        throw const SocketException('simulated network down');
      }
      return await Socket.connect(host, this.port);
    } finally {
      inFlight--;
    }
  }
}

Future<void> until(bool Function() condition, {int ms = 4000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Condition not met within ${ms}ms');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  group('ReconnectBackoff', () {
    test('doubles from the base delay and stops at the maximum', () {
      final b = ReconnectBackoff(
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 16),
      );
      expect(
        [for (var i = 1; i <= 8; i++) b.delayFor(i).inSeconds],
        [1, 2, 4, 8, 16, 16, 16, 16],
      );
    });

    test('is safe for huge attempt numbers and attempts below 1', () {
      final b = ReconnectBackoff(
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 16),
      );
      expect(b.delayFor(1000000), const Duration(seconds: 16));
      expect(b.delayFor(0), const Duration(seconds: 1));
      expect(b.delayFor(-5), const Duration(seconds: 1));
    });

    test('jitter only shortens the delay and never exceeds the maximum', () {
      final b = ReconnectBackoff(
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 16),
        jitter: 0.25,
        random: Random(42),
      );
      var sawShortened = false;
      for (var attempt = 1; attempt <= 200; attempt++) {
        final nominal = ReconnectBackoff(
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 16),
        ).delayFor(attempt);
        final d = b.delayFor(attempt);
        expect(d <= nominal, isTrue, reason: 'attempt $attempt');
        expect(d <= const Duration(seconds: 16), isTrue);
        expect(
          d.inMicroseconds >= (nominal.inMicroseconds * 0.75).floor() - 1,
          isTrue,
          reason: 'attempt $attempt below the jitter floor',
        );
        if (d < nominal) sawShortened = true;
      }
      expect(sawShortened, isTrue);
    });

    test('jitter outside 0..1 is clamped', () {
      final b = ReconnectBackoff(
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 1),
        jitter: 5,
      );
      expect(b.jitter, 1.0);
      expect(
        ReconnectBackoff(
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 1),
          jitter: -1,
        ).jitter,
        0.0,
      );
    });
  });

  group('KeyenceSr751Client reconnect (deterministic)', () {
    late ServerSocket server;
    late _Net net;
    late KeyenceSr751Client client;
    final accepted = <Socket>[];
    final timers = <_ManualTimer>[];
    final statuses = <KeyenceConnectionStatus>[];
    StreamSubscription<KeyenceConnectionStatus>? statusSub;
    var now = DateTime(2026, 1, 1);

    const base = Duration(seconds: 1);
    const max = Duration(seconds: 8);

    KeyenceSr751Client makeClient({
      double jitter = 0,
      Random? random,
      Duration stable = const Duration(seconds: 10),
    }) {
      client = KeyenceSr751Client(
        defaultHost: '127.0.0.1',
        defaultPort: server.port,
        reconnectBaseDelay: base,
        reconnectMaxDelay: max,
        reconnectJitter: jitter,
        stableConnectionThreshold: stable,
        random: random,
        clock: () => now,
        timerFactory: (delay, cb) {
          final t = _ManualTimer(delay, cb);
          timers.add(t);
          return t;
        },
        socketFactory: net.connect,
      );
      statusSub = client.statusStream.listen(statuses.add);
      return client;
    }

    _ManualTimer pendingTimer() {
      final active = timers.where((t) => t.isActive).toList();
      expect(active.length, 1, reason: 'exactly one pending reconnect timer');
      return active.single;
    }

    /// Fires the pending timer and waits for the resulting attempt to finish.
    Future<void> fireAndSettle() async {
      final before = net.calls;
      pendingTimer().fire();
      await until(() => net.calls == before + 1 && net.inFlight == 0);
      await until(() => client.status != KeyenceConnectionStatus.connecting);
    }

    void expectNoConsecutiveDuplicates() {
      for (var i = 1; i < statuses.length; i++) {
        if (statuses[i] == statuses[i - 1]) {
          // error -> error is allowed only if the messages differ, which the
          // status stream cannot show; connecting/connected/disconnected must
          // never repeat.
          expect(
            statuses[i] == KeyenceConnectionStatus.error,
            isTrue,
            reason: 'duplicate ${statuses[i]} at index $i in $statuses',
          );
        }
      }
    }

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(accepted.add);
      net = _Net(server.port);
      accepted.clear();
      timers.clear();
      statuses.clear();
      now = DateTime(2026, 1, 1);
    });

    tearDown(() async {
      await statusSub?.cancel();
      client.dispose();
      for (final s in accepted) {
        s.destroy();
      }
      await server.close();
    });

    test(
      'initial connection failure schedules one retry at the base delay',
      () async {
        makeClient();
        expect(await client.connect(), isFalse);

        expect(client.status, KeyenceConnectionStatus.error);
        expect(client.reconnectAttempts, 1);
        expect(pendingTimer().delay, base);
      },
    );

    test(
      'connects after a temporary failure and resets the attempt count',
      () async {
        makeClient();
        expect(await client.connect(), isFalse);
        await fireAndSettle();
        expect(client.status, KeyenceConnectionStatus.error);

        net.failing = false;
        await fireAndSettle();

        expect(client.status, KeyenceConnectionStatus.connected);
        expect(client.reconnectAttempts, 0);
        expect(timers.where((t) => t.isActive), isEmpty);
        expect(
          statuses.where((s) => s == KeyenceConnectionStatus.connected).length,
          1,
          reason: 'connected is announced exactly once',
        );
        expectNoConsecutiveDuplicates();
      },
    );

    test(
      'keeps retrying beyond ten attempts with doubling then capped delays',
      () async {
        makeClient();
        expect(await client.connect(), isFalse);
        for (var i = 0; i < 12; i++) {
          await fireAndSettle();
        }
        expect(client.reconnectAttempts, 13);
        final delays = timers.map((t) => t.delay.inSeconds).toList();
        expect(delays.length, 13);
        expect(delays.take(6).toList(), [1, 2, 4, 8, 8, 8]);
        expect(delays.every((d) => d <= max.inSeconds), isTrue);
        expect(delays.skip(3).every((d) => d == max.inSeconds), isTrue);
      },
    );

    test('jittered delays stay within the bound and never overlap', () async {
      makeClient(jitter: 0.5, random: Random(7));
      expect(await client.connect(), isFalse);
      for (var i = 0; i < 10; i++) {
        await fireAndSettle();
      }
      for (final t in timers) {
        expect(t.delay <= max, isTrue);
        expect(t.delay >= const Duration(milliseconds: 500), isTrue);
      }
      expect(net.maxInFlight, 1, reason: 'attempts never overlap');
    });

    test('never has more than one pending reconnect timer', () async {
      makeClient();
      expect(await client.connect(), isFalse);
      for (var i = 0; i < 6; i++) {
        expect(timers.where((t) => t.isActive).length, 1);
        await fireAndSettle();
      }
      // A manual connect while a retry is pending replaces it.
      final callsBefore = net.calls;
      expect(await client.connect(), isFalse);
      expect(net.calls, callsBefore + 1);
      expect(timers.where((t) => t.isActive).length, 1);
      expect(net.maxInFlight, 1);
    });

    test('manual disconnect during backoff cancels the retry', () async {
      makeClient();
      expect(await client.connect(), isFalse);
      final pending = pendingTimer();

      await client.disconnect();

      expect(pending.isActive, isFalse);
      expect(client.status, KeyenceConnectionStatus.disconnected);
      final calls = net.calls;
      pending.fire(); // a cancelled timer must be inert
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(net.calls, calls);
      expect(timers.where((t) => t.isActive), isEmpty);
      expectNoConsecutiveDuplicates();
    });

    test(
      'dispose during backoff cancels the retry and is idempotent',
      () async {
        makeClient();
        expect(await client.connect(), isFalse);
        final pending = pendingTimer();

        client.dispose();
        client.dispose();

        expect(pending.isActive, isFalse);
        final calls = net.calls;
        pending.fire();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(net.calls, calls);
      },
    );

    test('recovers after the reader closes the socket', () async {
      makeClient(stable: const Duration(seconds: 10));
      net.failing = false;
      expect(await client.connect(), isTrue);
      await until(() => accepted.length == 1);

      // The connection was healthy for longer than the stable threshold.
      now = now.add(const Duration(seconds: 30));
      accepted.first.destroy();
      await until(() => timers.any((t) => t.isActive));

      expect(client.status, KeyenceConnectionStatus.disconnected);
      expect(pendingTimer().delay, base, reason: 'healthy drop: base delay');

      await fireAndSettle();
      expect(client.status, KeyenceConnectionStatus.connected);
      await until(() => accepted.length == 2);
      expect(client.reconnectAttempts, 0);
      expectNoConsecutiveDuplicates();
    });

    test(
      'a connection that drops straight away does not reset the backoff',
      () async {
        makeClient(stable: const Duration(seconds: 10));
        net.failing = false;
        expect(await client.connect(), isTrue);

        final delays = <int>[];
        for (var round = 0; round < 4; round++) {
          await until(() => accepted.length == round + 1);
          // Drop with no time passing: not a stable connection.
          accepted[round].destroy();
          await until(() => timers.where((t) => t.isActive).length == 1);
          delays.add(pendingTimer().delay.inSeconds);
          await fireAndSettle();
          expect(client.status, KeyenceConnectionStatus.connected);
        }

        // Without the flap penalty every round would wait 1 s (a fast loop).
        expect(delays, [2, 4, 8, 8]);
      },
    );

    test('status notifications are never repeated back to back', () async {
      makeClient();
      expect(await client.connect(), isFalse);
      for (var i = 0; i < 4; i++) {
        await fireAndSettle();
      }
      net.failing = false;
      await fireAndSettle();
      await client.disconnect();
      await client.disconnect(); // second call must not re-announce

      expect(statuses.last, KeyenceConnectionStatus.disconnected);
      expect(
        statuses.where((s) => s == KeyenceConnectionStatus.disconnected).length,
        1,
      );
      expectNoConsecutiveDuplicates();
    });
  });
}
