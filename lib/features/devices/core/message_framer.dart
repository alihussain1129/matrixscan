import 'dart:typed_data';

/// Splits a TCP byte stream into complete messages.
///
/// Network reads do not line up with device messages: one read can hold half
/// a message, or several. This keeps raw bytes until a full terminator has
/// arrived, so text is decoded only once a message is complete. The terminator
/// must match the delimiter configured on the device.
class MessageFramer {
  MessageFramer({
    List<int> terminator = const [0x0D],
    this.maxMessageBytes = 65536,
    this.skipEmpty = true,
  }) : _terminator = List<int>.unmodifiable(terminator) {
    if (_terminator.isEmpty) {
      throw ArgumentError.value(terminator, 'terminator', 'must not be empty');
    }
    if (maxMessageBytes <= 0) {
      throw ArgumentError.value(
        maxMessageBytes,
        'maxMessageBytes',
        'must be positive',
      );
    }
  }

  final List<int> _terminator;
  final int maxMessageBytes;
  final bool skipEmpty;
  final List<int> _buffer = <int>[];
  int _overflowCount = 0;

  /// Number of messages or partial buffers discarded for exceeding the limit.
  int get overflowCount => _overflowCount;

  /// Bytes received that are still waiting for a terminator.
  int get pendingBytes => _buffer.length;

  /// Adds received bytes and returns every message completed by them.
  List<Uint8List> add(List<int> chunk) {
    _buffer.addAll(chunk);
    final messages = <Uint8List>[];
    var start = 0;
    while (true) {
      final end = _indexOfTerminator(start);
      if (end < 0) break;
      final length = end - start;
      if (length > maxMessageBytes) {
        _overflowCount++;
      } else if (length > 0 || !skipEmpty) {
        messages.add(Uint8List.fromList(_buffer.sublist(start, end)));
      }
      start = end + _terminator.length;
    }
    if (start > 0) _buffer.removeRange(0, start);
    if (_buffer.length > maxMessageBytes) {
      _buffer.clear();
      _overflowCount++;
    }
    return messages;
  }

  /// Drops any partial message, for example after a reconnect.
  void reset() => _buffer.clear();

  int _indexOfTerminator(int from) {
    final last = _buffer.length - _terminator.length;
    for (var i = from; i <= last; i++) {
      var match = true;
      for (var j = 0; j < _terminator.length; j++) {
        if (_buffer[i + j] != _terminator[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
