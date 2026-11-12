/// Which half of an inspection a waiting record is still missing.
enum PairSide { barcode, image }

/// Tracks the single most recent record that is waiting for its other half
/// (the barcode from the TCP link, or the image from FTP).
///
/// The two arrive on separate channels in either order. A new arrival may join
/// the waiting record only if it supplies the missing half and the record is
/// no older than [window]. Anything else starts a new record.
class PairingWindow {
  PairingWindow({
    this.window = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _clock;

  String? _id;
  PairSide? _missing;
  DateTime? _openedAt;

  /// Marks [id] as waiting for the [missing] half. Replaces any earlier one.
  void open(String id, {required PairSide missing}) {
    _id = id;
    _missing = missing;
    _openedAt = _clock();
  }

  /// If a fresh record is waiting for [arriving], returns its id and closes
  /// it. Otherwise returns null and leaves the waiting record unchanged,
  /// unless it has expired, in which case it is dropped.
  String? claim(PairSide arriving) {
    final id = _id;
    final openedAt = _openedAt;
    if (id == null || openedAt == null) return null;
    if (_clock().difference(openedAt) > window) {
      clear();
      return null;
    }
    if (_missing != arriving) return null;
    clear();
    return id;
  }

  void clear() {
    _id = null;
    _missing = null;
    _openedAt = null;
  }
}
