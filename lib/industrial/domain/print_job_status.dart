/// Print job lifecycle.
enum PrintJobStatus {
  queued('queued'),
  printing('printing'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const PrintJobStatus(this.dbValue);

  final String dbValue;

  static PrintJobStatus? fromDb(String value) {
    for (final s in PrintJobStatus.values) {
      if (s.dbValue == value) return s;
    }
    return null;
  }

  Set<PrintJobStatus> get allowedNext => switch (this) {
    PrintJobStatus.queued => {PrintJobStatus.printing, PrintJobStatus.cancelled},
    PrintJobStatus.printing => {
      PrintJobStatus.completed,
      PrintJobStatus.failed,
      PrintJobStatus.cancelled,
    },
    PrintJobStatus.failed => {PrintJobStatus.queued, PrintJobStatus.cancelled},
    PrintJobStatus.completed => <PrintJobStatus>{},
    PrintJobStatus.cancelled => <PrintJobStatus>{},
  };

  bool canMoveTo(PrintJobStatus next) => allowedNext.contains(next);

  bool get isFinal => allowedNext.isEmpty;
}
