import '../gs1/gs1_parser.dart';
import '../gs1/gtin.dart';
import 'text_diff.dart';

/// Overall result of one inspection.
enum InspectionOutcome { pass, fail, noRead, review }

/// Fields compared in an inspection.
enum InspectionField { gtin, lot, expiry, serial }

enum Verdict { match, review, mismatch }

/// Rule set for an inspection. The defaults are configuration, not a standard.
class InspectionPolicy {
  const InspectionPolicy({
    this.version = 'default-1',
    this.ocrMinConfidence = 0.80,
    this.trimWhitespace = true,
    this.caseSensitive = true,
    this.confusablesNeedReview = true,
    this.requireBarcode = true,
    this.assumeGs1 = false,
  });

  /// Recorded with every result so a result can be traced to its rules.
  final String version;

  /// OCR confidence (0..1) below which a result needs review.
  final double ocrMinConfidence;
  final bool trimWhitespace;
  final bool caseSensitive;

  /// A difference only in look-alike characters (O/0, I/1 ...) is REVIEW,
  /// never PASS.
  final bool confusablesNeedReview;

  /// A missing barcode is NO READ.
  final bool requireBarcode;

  /// Treat barcode text without a symbology prefix as GS1 element strings.
  final bool assumeGs1;
}

/// Expected values received from outside (serialization software or manual
/// entry). A read-only snapshot: Exalted does not own or change it.
class ExpectedValues {
  const ExpectedValues({
    this.gtin,
    this.lot,
    this.expiry,
    this.serial,
    this.source = 'manual',
    this.externalRef,
  });

  final String? gtin;
  final String? lot;
  final DateTime? expiry;
  final String? serial;

  /// Where the values came from, for example "manual" or "file import".
  final String source;

  /// Opaque reference to the external record, kept for traceability only.
  final String? externalRef;
}

class OcrFieldReading {
  const OcrFieldReading(this.value, {this.confidence});
  final String value;

  /// 0..1, or null when the engine gave none.
  final double? confidence;
}

/// OCR output. Per-field values are supplied by the caller; an expiry value
/// must be an ISO date (YYYY-MM-DD).
class OcrReading {
  const OcrReading({this.rawText = '', this.fields = const {}});
  final String rawText;
  final Map<InspectionField, OcrFieldReading> fields;
  bool get hasData => rawText.trim().isNotEmpty || fields.isNotEmpty;
}

class Comparison {
  const Comparison(this.verdict, this.reason, {this.diffs = const []});
  final Verdict verdict;
  final String reason;
  final List<FieldDiff> diffs;
}

class FieldResult {
  const FieldResult({
    required this.field,
    this.expected,
    this.barcode,
    this.ocr,
    this.ocrConfidence,
    this.barcodeVsExpected,
    this.ocrVsExpected,
    this.barcodeVsOcr,
  });

  final InspectionField field;
  final String? expected;
  final String? barcode;
  final String? ocr;
  final double? ocrConfidence;
  final Comparison? barcodeVsExpected;
  final Comparison? ocrVsExpected;
  final Comparison? barcodeVsOcr;

  Verdict get verdict {
    final all = [
      barcodeVsExpected,
      ocrVsExpected,
      barcodeVsOcr,
    ].whereType<Comparison>().map((c) => c.verdict).toList();
    if (all.contains(Verdict.mismatch)) return Verdict.mismatch;
    if (all.contains(Verdict.review)) return Verdict.review;
    return Verdict.match;
  }
}

class InspectionResult {
  const InspectionResult({
    required this.outcome,
    required this.fields,
    required this.reasons,
    required this.policyVersion,
    required this.crossChecked,
    required this.timestamp,
    this.expectedSource,
    this.expectedRef,
  });

  final InspectionOutcome outcome;
  final List<FieldResult> fields;

  /// Human-readable reasons for anything that is not a clean match.
  final List<String> reasons;
  final String policyVersion;

  /// True when both a barcode and OCR text were available to compare.
  final bool crossChecked;
  final DateTime timestamp;
  final String? expectedSource;
  final String? expectedRef;
}

const Map<String, String> _lookAlikes = {
  'O': '0',
  'I': '1',
  'l': '1',
  'S': '5',
  'B': '8',
  'Z': '2',
};

String _norm(String s, InspectionPolicy p) {
  var v = s;
  if (p.trimWhitespace) v = v.trim();
  if (!p.caseSensitive) v = v.toUpperCase();
  return v;
}

String _fold(String s) => s.split('').map((c) => _lookAlikes[c] ?? c).join();

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Compares two strings under [policy]. Differences are never normalized
/// into a match: look-alike-only and low-confidence cases become REVIEW.
Comparison compareText({
  required String expected,
  required String actual,
  required InspectionPolicy policy,
  double? confidence,
}) {
  final e = _norm(expected, policy);
  final a = _norm(actual, policy);
  final low = confidence != null && confidence < policy.ocrMinConfidence;
  final conf = confidence?.toStringAsFixed(2);
  if (e == a) {
    return low
        ? Comparison(
            Verdict.review,
            'values match but OCR confidence $conf is below ${policy.ocrMinConfidence}',
          )
        : const Comparison(Verdict.match, 'match');
  }
  final diffs = diffStrings(e, a);
  if (policy.confusablesNeedReview && _fold(e) == _fold(a)) {
    return Comparison(
      Verdict.review,
      'differs only by look-alike characters',
      diffs: diffs,
    );
  }
  if (low) {
    return Comparison(
      Verdict.review,
      'differs, but OCR confidence $conf is below ${policy.ocrMinConfidence}',
      diffs: diffs,
    );
  }
  return Comparison(Verdict.mismatch, 'does not match', diffs: diffs);
}

/// Verifies one inspection: barcode vs expected, OCR vs expected, and
/// barcode vs OCR. Priority: FAIL, then NO READ, then REVIEW, then PASS.
InspectionResult verifyInspection({
  String? barcodeText,
  OcrReading? ocr,
  ExpectedValues? expected,
  InspectionPolicy policy = const InspectionPolicy(),
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final raw = barcodeText ?? '';
  final hasBarcode = raw.trim().isNotEmpty;
  final ocrRan = ocr != null;
  final hasOcr = ocr != null && ocr.hasData;

  if (!hasBarcode && !hasOcr) {
    return InspectionResult(
      outcome: InspectionOutcome.noRead,
      fields: const [],
      reasons: const ['Nothing was read: no barcode and no OCR text'],
      policyVersion: policy.version,
      crossChecked: false,
      timestamp: clock,
      expectedSource: expected?.source,
      expectedRef: expected?.externalRef,
    );
  }

  var hardFail = false;
  var noRead = false;
  var needsReview = false;
  final reasons = <String>[];

  Gs1ParseResult? gs1;
  if (hasBarcode) {
    gs1 = parseGs1(raw, assumeGs1: policy.assumeGs1, now: clock);
    if (gs1 != null) {
      for (final f in gs1.fields) {
        if (f.status == Gs1FieldStatus.invalid) {
          reasons.add('GS1 (${f.ai}) ${f.name}: ${f.error}');
          hardFail = true;
        }
      }
      if (gs1.unparsed.isNotEmpty) {
        reasons.add('Barcode has trailing data that could not be parsed');
        needsReview = true;
      }
    }
  } else if (policy.requireBarcode) {
    noRead = true;
    reasons.add('Barcode was not read');
  }

  if (ocrRan && !hasOcr) {
    reasons.add('OCR ran but read no text');
    needsReview = true;
  }

  // Expected values, normalized.
  final exp = <InspectionField, String>{};
  if (expected != null) {
    final g = expected.gtin;
    if (g != null && g.trim().isNotEmpty) {
      final r = validateGtin(g.trim());
      if (r.isValid) {
        exp[InspectionField.gtin] = r.normalized14!;
      } else {
        reasons.add('Expected GTIN is not valid (${r.label})');
        needsReview = true;
      }
    }
    final lot = expected.lot;
    if (lot != null && lot.trim().isNotEmpty) exp[InspectionField.lot] = lot;
    final serial = expected.serial;
    if (serial != null && serial.trim().isNotEmpty) {
      exp[InspectionField.serial] = serial;
    }
    final expiry = expected.expiry;
    if (expiry != null) exp[InspectionField.expiry] = _iso(expiry);
  }

  // Values carried by the barcode.
  String? barcodeValue(InspectionField f) {
    final g = gs1;
    if (g == null) return null;
    String? ai(String code) {
      final field = g.field(code);
      return (field != null && field.isValid) ? field.value : null;
    }

    switch (f) {
      case InspectionField.gtin:
        return ai('01');
      case InspectionField.lot:
        return ai('10');
      case InspectionField.serial:
        return ai('21');
      case InspectionField.expiry:
        final v = ai('17');
        final d = v == null ? null : parseGs1Date(v, now: clock);
        return d == null ? null : _iso(d.date);
    }
  }

  void note(InspectionField f, String what, Comparison c) {
    if (c.verdict == Verdict.match) return;
    final detail = c.diffs.isEmpty
        ? c.reason
        : '${c.reason} (${describeDiffs(c.diffs)})';
    reasons.add('${f.name}: $what $detail');
    if (c.verdict == Verdict.mismatch) {
      hardFail = true;
    } else {
      needsReview = true;
    }
  }

  final results = <FieldResult>[];
  for (final f in InspectionField.values) {
    final e = exp[f];
    final b = barcodeValue(f);
    final o = ocr?.fields[f];
    if (e == null && b == null && o == null) continue;

    Comparison? bVsE;
    Comparison? oVsE;
    Comparison? bVsO;

    if (e != null) {
      if (hasBarcode) {
        if (b != null) {
          bVsE = compareText(expected: e, actual: b, policy: policy);
          note(f, 'barcode vs expected:', bVsE);
        } else {
          reasons.add('${f.name}: barcode does not carry it, but it is expected');
          hardFail = true;
        }
      }
      if (hasOcr) {
        if (o != null) {
          oVsE = compareText(
            expected: e,
            actual: o.value,
            policy: policy,
            confidence: o.confidence,
          );
          note(f, 'OCR vs expected:', oVsE);
        } else {
          reasons.add('${f.name}: not found in the OCR text');
          needsReview = true;
        }
      }
    }
    if (b != null && o != null) {
      bVsO = compareText(
        expected: b,
        actual: o.value,
        policy: policy,
        confidence: o.confidence,
      );
      note(f, 'barcode vs OCR:', bVsO);
    }

    results.add(
      FieldResult(
        field: f,
        expected: e,
        barcode: b,
        ocr: o?.value,
        ocrConfidence: o?.confidence,
        barcodeVsExpected: bVsE,
        ocrVsExpected: oVsE,
        barcodeVsOcr: bVsO,
      ),
    );
  }

  final outcome = hardFail
      ? InspectionOutcome.fail
      : noRead
      ? InspectionOutcome.noRead
      : needsReview
      ? InspectionOutcome.review
      : InspectionOutcome.pass;

  return InspectionResult(
    outcome: outcome,
    fields: List.unmodifiable(results),
    reasons: List.unmodifiable(reasons),
    policyVersion: policy.version,
    crossChecked: hasBarcode && hasOcr,
    timestamp: clock,
    expectedSource: expected?.source,
    expectedRef: expected?.externalRef,
  );
}
