/// Serial number lifecycle. The database checks the value is valid; the
/// allowed moves are enforced here.
enum SerialStatus {
  allocated('allocated'),
  printed('printed'),
  verified('verified'),
  rejected('rejected'),
  voided('voided');

  const SerialStatus(this.dbValue);

  final String dbValue;

  static SerialStatus? fromDb(String value) {
    for (final s in SerialStatus.values) {
      if (s.dbValue == value) return s;
    }
    return null;
  }

  Set<SerialStatus> get allowedNext => switch (this) {
    SerialStatus.allocated => {SerialStatus.printed, SerialStatus.voided},
    SerialStatus.printed => {
      SerialStatus.verified,
      SerialStatus.rejected,
      SerialStatus.voided,
    },
    SerialStatus.rejected => {SerialStatus.voided},
    SerialStatus.verified => <SerialStatus>{},
    SerialStatus.voided => <SerialStatus>{},
  };

  bool canMoveTo(SerialStatus next) => allowedNext.contains(next);

  bool get isFinal => allowedNext.isEmpty;
}
