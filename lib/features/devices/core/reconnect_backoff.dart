import 'dart:math';

/// Exponential reconnect delay with an upper bound and optional jitter.
///
/// `delayFor(1)` is [baseDelay]; every further attempt doubles it until
/// [maxDelay] is reached. With [jitter] > 0 the result is reduced by a random
/// fraction of at most [jitter] (so 0.2 yields 80%..100% of the nominal
/// delay). Jitter only ever shortens the delay, so [maxDelay] is a hard bound
/// and many clients retrying after one outage do not all fire in lockstep.
class ReconnectBackoff {
  ReconnectBackoff({
    required this.baseDelay,
    required this.maxDelay,
    double jitter = 0,
    Random? random,
  }) : jitter = jitter.isNaN ? 0 : jitter.clamp(0.0, 1.0).toDouble(),
       _random = random ?? Random();

  final Duration baseDelay;
  final Duration maxDelay;
  final double jitter;
  final Random _random;

  /// Delay before reconnect attempt number [attempt] (1-based).
  Duration delayFor(int attempt) {
    final n = attempt < 1 ? 1 : attempt;
    final shift = n > 21 ? 20 : n - 1;
    final raw = baseDelay.inMicroseconds * (1 << shift);
    final cap = maxDelay.inMicroseconds < baseDelay.inMicroseconds
        ? baseDelay.inMicroseconds
        : maxDelay.inMicroseconds;
    final nominal = raw > cap ? cap : raw;
    if (jitter == 0) return Duration(microseconds: nominal);
    final factor = 1 - jitter * _random.nextDouble();
    return Duration(microseconds: (nominal * factor).round());
  }
}
