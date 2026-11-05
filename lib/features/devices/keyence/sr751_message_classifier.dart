/// What an incoming line from the reader turned out to be.
enum Sr751MessageKind {
  /// Decoded barcode data.
  barcode,

  /// The reader reported a failed read or an error.
  readFailure,

  /// The reply to a command Exalted just sent.
  commandResponse,

  /// A status message that is not barcode data.
  status,

  /// Not recognised. Logged, never stored as a barcode.
  unknown,

  /// A blank line.
  ignored,
}

/// How to tell the reader's reply kinds apart.
///
/// Nothing here is a verified SR-751 format. Fill these in from the official
/// manual or from replies captured from the reader.
class Sr751ReplyProfile {
  const Sr751ReplyProfile({
    required this.name,
    this.errorPatterns = const <String>[],
    this.acknowledgements = const <String>{},
    this.statusPatterns = const <String>[],
    this.barcodePrefix,
    this.commandReplyWindow = const Duration(seconds: 2),
  });

  /// The behaviour the existing client has today: `ERROR...` and `NG` are
  /// failures and every other line is barcode data.
  const Sr751ReplyProfile.legacy()
    : this(name: 'legacy', errorPatterns: const <String>[r'^ERROR', r'^NG$']);

  /// The replies listed in docs/KEYENCE_SR751_GUIDE.md. Opt-in only: that
  /// table has not been checked against the official manual.
  const Sr751ReplyProfile.guideDocumented()
    : this(
        name: 'guide-documented (not verified against the manual)',
        errorPatterns: const <String>[r'^ERROR', r'^NG$'],
        acknowledgements: const <String>{'OK'},
      );

  final String name;

  /// Regular expressions for lines that mean a failed read or an error.
  final List<String> errorPatterns;

  /// Exact lines that acknowledge a command. A line equal to one of these is
  /// never treated as a barcode.
  final Set<String> acknowledgements;

  /// Regular expressions for status lines.
  final List<String> statusPatterns;

  /// A header the reader is configured to put in front of read data. When
  /// set, only lines that start with it are barcodes.
  final String? barcodePrefix;

  /// How long after a command an acknowledgement is accepted as its reply.
  final Duration commandReplyWindow;
}

class Sr751Classification {
  const Sr751Classification(
    this.kind,
    this.raw, {
    this.payload = '',
    this.command,
    this.detail,
  });

  final Sr751MessageKind kind;
  final String raw;

  /// The barcode data, for [Sr751MessageKind.barcode].
  final String payload;

  /// The command being answered, for [Sr751MessageKind.commandResponse].
  final String? command;
  final String? detail;
}

/// Sorts incoming lines into barcodes, failures, command replies, status and
/// unknown messages. Unknown lines are never barcodes.
class Sr751MessageClassifier {
  Sr751MessageClassifier({
    this.profile = const Sr751ReplyProfile.legacy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _errors = [for (final p in profile.errorPatterns) RegExp(p)],
       _statuses = [for (final p in profile.statusPatterns) RegExp(p)];

  final Sr751ReplyProfile profile;
  final DateTime Function() _clock;
  final List<RegExp> _errors;
  final List<RegExp> _statuses;

  String? _pendingCommand;
  DateTime? _pendingAt;

  String get profileName => profile.name;

  /// Remember the command just sent, so its acknowledgement can be matched.
  void noteCommandSent(String command) {
    _pendingCommand = command;
    _pendingAt = _clock();
  }

  void clearPending() {
    _pendingCommand = null;
    _pendingAt = null;
  }

  String? _takePending() {
    final command = _pendingCommand;
    final at = _pendingAt;
    clearPending();
    if (command == null || at == null) return null;
    if (_clock().difference(at) > profile.commandReplyWindow) return null;
    return command;
  }

  Sr751Classification classify(String line) {
    final text = line.trim();
    if (text.isEmpty) {
      return Sr751Classification(Sr751MessageKind.ignored, text);
    }
    for (final pattern in _errors) {
      if (pattern.hasMatch(text)) {
        return Sr751Classification(
          Sr751MessageKind.readFailure,
          text,
          detail: text,
        );
      }
    }
    final prefix = profile.barcodePrefix;
    if (prefix != null && prefix.isNotEmpty && text.startsWith(prefix)) {
      final payload = text.substring(prefix.length);
      if (payload.isEmpty) {
        return Sr751Classification(
          Sr751MessageKind.unknown,
          text,
          detail: 'header without data',
        );
      }
      return Sr751Classification(
        Sr751MessageKind.barcode,
        text,
        payload: payload,
      );
    }
    if (profile.acknowledgements.contains(text)) {
      final command = _takePending();
      if (command == null) {
        return Sr751Classification(
          Sr751MessageKind.unknown,
          text,
          detail: 'acknowledgement with no pending command',
        );
      }
      return Sr751Classification(
        Sr751MessageKind.commandResponse,
        text,
        command: command,
      );
    }
    for (final pattern in _statuses) {
      if (pattern.hasMatch(text)) {
        return Sr751Classification(Sr751MessageKind.status, text);
      }
    }
    if (prefix != null && prefix.isNotEmpty) {
      return Sr751Classification(
        Sr751MessageKind.unknown,
        text,
        detail: 'no barcode header',
      );
    }
    return Sr751Classification(Sr751MessageKind.barcode, text, payload: text);
  }
}
