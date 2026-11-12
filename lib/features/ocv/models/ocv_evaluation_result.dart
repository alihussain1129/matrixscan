import 'ocv_rule.dart';

/// Outcome status of an Optical Character Verification check.
enum OcvStatus {
  /// Extracted characters comply strictly with rule criteria and confidence thresholds.
  pass,

  /// Extracted characters fail the rule's criteria (pattern mismatch, expired date, wrong prefix).
  fail,

  /// The text matched superficially, but recognition confidence was below industrial threshold,
  /// or text was partially obscured.
  inconclusive,

  /// No text was detected in the region of interest.
  noText,
}

/// A specific character-level discrepancy between expected and actual text.
class CharacterDiff {
  const CharacterDiff({
    required this.position,
    required this.expectedChar,
    required this.actualChar,
  });

  final int position;
  final String expectedChar;
  final String actualChar;

  Map<String, dynamic> toJson() => {
    'position': position,
    'expectedChar': expectedChar,
    'actualChar': actualChar,
  };

  @override
  String toString() =>
      'Pos $position: expected "$expectedChar", found "$actualChar"';
}

/// Detailed, explainable result of an OCV verification inspection.
class OcvEvaluationResult {
  const OcvEvaluationResult({
    required this.status,
    required this.rule,
    required this.extractedText,
    required this.explanation,
    required this.timestamp,
    this.matchedSubstring,
    this.confidence = 1.0,
    this.diffs = const [],
  });

  final OcvStatus status;
  final OcvRule rule;
  final String extractedText;
  final String explanation;
  final DateTime timestamp;
  final String? matchedSubstring;
  final double confidence;
  final List<CharacterDiff> diffs;

  bool get isPass => status == OcvStatus.pass;
  bool get isFail => status == OcvStatus.fail;
  bool get isInconclusive => status == OcvStatus.inconclusive;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'rule': rule.toJson(),
    'extractedText': extractedText,
    'explanation': explanation,
    'timestamp': timestamp.toIso8601String(),
    'matchedSubstring': matchedSubstring,
    'confidence': confidence,
    'diffs': diffs.map((d) => d.toJson()).toList(),
  };
}
