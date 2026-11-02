import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ocv_evaluation_result.dart';
import '../models/ocv_rule.dart';

/// Industrial Optical Character Verification (OCV) Engine.
///
/// Validates OCR output against industrial quality, formatting, expiry, and batch rules,
/// generating explainable PASS / FAIL / INCONCLUSIVE verdicts.
class OcvEngine {
  const OcvEngine({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Evaluates the extracted text against an OCV rule.
  OcvEvaluationResult evaluate(
    String extractedText,
    OcvRule rule, {
    double confidence = 1.0,
  }) {
    final now = _clock();
    final cleanText = extractedText.trim();

    if (cleanText.isEmpty) {
      return OcvEvaluationResult(
        status: OcvStatus.noText,
        rule: rule,
        extractedText: extractedText,
        explanation: 'No text extracted from target region of interest.',
        timestamp: now,
        confidence: 0.0,
      );
    }

    if (confidence < rule.minConfidence) {
      return OcvEvaluationResult(
        status: OcvStatus.inconclusive,
        rule: rule,
        extractedText: extractedText,
        explanation:
            'Recognition confidence (${(confidence * 100).toStringAsFixed(1)}%) '
            'is below the required industrial threshold (${(rule.minConfidence * 100).toStringAsFixed(1)}%). '
            'Reposition camera or adjust lighting.',
        timestamp: now,
        confidence: confidence,
      );
    }

    switch (rule.type) {
      case OcvRuleType.exactMatch:
        return _evaluateExactMatch(cleanText, rule, confidence, now);

      case OcvRuleType.expiryDate:
        return _evaluateExpiryDate(cleanText, rule, confidence, now);

      case OcvRuleType.numericRange:
        return _evaluateNumericRange(cleanText, rule, confidence, now);

      case OcvRuleType.regex:
      case OcvRuleType.lotCode:
      case OcvRuleType.serialNumber:
        return _evaluatePattern(cleanText, rule, confidence, now);
    }
  }

  OcvEvaluationResult _evaluateExactMatch(
    String text,
    OcvRule rule,
    double confidence,
    DateTime now,
  ) {
    final expected = rule.pattern.trim();
    final actual = text;

    final matches = rule.caseSensitive
        ? expected == actual
        : expected.toLowerCase() == actual.toLowerCase();

    if (matches) {
      return OcvEvaluationResult(
        status: OcvStatus.pass,
        rule: rule,
        extractedText: text,
        matchedSubstring: text,
        explanation: 'Text exactly matches expected target string "${rule.pattern}".',
        timestamp: now,
        confidence: confidence,
      );
    }

    final diffs = _computeCharacterDiffs(expected, actual);
    return OcvEvaluationResult(
      status: OcvStatus.fail,
      rule: rule,
      extractedText: text,
      explanation:
          'Text mismatch. Expected "${rule.pattern}", but found "$actual". '
          '(${diffs.length} character differences detected).',
      timestamp: now,
      confidence: confidence,
      diffs: diffs,
    );
  }

  OcvEvaluationResult _evaluatePattern(
    String text,
    OcvRule rule,
    double confidence,
    DateTime now,
  ) {
    try {
      final reg = RegExp(rule.pattern, caseSensitive: rule.caseSensitive);
      final match = reg.firstMatch(text);

      if (match == null) {
        return OcvEvaluationResult(
          status: OcvStatus.fail,
          rule: rule,
          extractedText: text,
          explanation: 'Extracted text does not match pattern "${rule.pattern}".',
          timestamp: now,
          confidence: confidence,
        );
      }

      final matchedValue = match.group(0)!;

      // Prefix check
      if (rule.expectedPrefix != null &&
          !matchedValue.startsWith(rule.expectedPrefix!)) {
        return OcvEvaluationResult(
          status: OcvStatus.fail,
          rule: rule,
          extractedText: text,
          matchedSubstring: matchedValue,
          explanation: 'Found pattern but missing expected prefix "${rule.expectedPrefix}".',
          timestamp: now,
          confidence: confidence,
        );
      }

      // Suffix check
      if (rule.expectedSuffix != null &&
          !matchedValue.endsWith(rule.expectedSuffix!)) {
        return OcvEvaluationResult(
          status: OcvStatus.fail,
          rule: rule,
          extractedText: text,
          matchedSubstring: matchedValue,
          explanation: 'Found pattern but missing expected suffix "${rule.expectedSuffix}".',
          timestamp: now,
          confidence: confidence,
        );
      }

      return OcvEvaluationResult(
        status: OcvStatus.pass,
        rule: rule,
        extractedText: text,
        matchedSubstring: matchedValue,
        explanation: 'Matched rule pattern "${rule.name}": "$matchedValue".',
        timestamp: now,
        confidence: confidence,
      );
    } catch (e) {
      return OcvEvaluationResult(
        status: OcvStatus.fail,
        rule: rule,
        extractedText: text,
        explanation: 'Invalid rule regex expression: $e',
        timestamp: now,
        confidence: confidence,
      );
    }
  }

  OcvEvaluationResult _evaluateExpiryDate(
    String text,
    OcvRule rule,
    double confidence,
    DateTime now,
  ) {
    // Look for MM/YYYY, MM/YY, or YYYY-MM
    final dateReg = RegExp(
      r'(?:EXP[:\.\s]*)?((?:0[1-9]|1[0-2])[\/\.-](?:20)?\d{2})|((?:20)?\d{2}[\/\.-](?:0[1-9]|1[0-2]))',
      caseSensitive: false,
    );

    final match = dateReg.firstMatch(text);
    if (match == null) {
      return OcvEvaluationResult(
        status: OcvStatus.fail,
        rule: rule,
        extractedText: text,
        explanation: 'Could not find a valid expiration date format in text.',
        timestamp: now,
        confidence: confidence,
      );
    }

    final dateStr = match.group(1) ?? match.group(2)!;
    final parts = dateStr.split(RegExp(r'[\/\.-]'));

    int month;
    int year;

    if (parts[0].length == 4) {
      year = int.parse(parts[0]);
      month = int.parse(parts[1]);
    } else {
      month = int.parse(parts[0]);
      year = int.parse(parts[1]);
      if (year < 100) year += 2000;
    }

    // End of expiration month (e.g. 11/2026 expires on last day of November)
    final expiryDate = DateTime(year, month + 1, 0, 23, 59, 59);

    if (expiryDate.isBefore(now)) {
      return OcvEvaluationResult(
        status: OcvStatus.fail,
        rule: rule,
        extractedText: text,
        matchedSubstring: dateStr,
        explanation: 'Expired: $dateStr passed on ${expiryDate.toIso8601String().substring(0, 10)}.',
        timestamp: now,
        confidence: confidence,
      );
    }

    if (rule.dateWithinDays != null) {
      final daysLeft = expiryDate.difference(now).inDays;
      if (daysLeft < rule.dateWithinDays!) {
        return OcvEvaluationResult(
          status: OcvStatus.fail,
          rule: rule,
          extractedText: text,
          matchedSubstring: dateStr,
          explanation: 'Near expiry: Only $daysLeft days remaining (required: ${rule.dateWithinDays} days).',
          timestamp: now,
          confidence: confidence,
        );
      }
    }

    return OcvEvaluationResult(
      status: OcvStatus.pass,
      rule: rule,
      extractedText: text,
      matchedSubstring: dateStr,
      explanation: 'Valid expiration date $dateStr (expires ${expiryDate.toIso8601String().substring(0, 10)}).',
      timestamp: now,
      confidence: confidence,
    );
  }

  OcvEvaluationResult _evaluateNumericRange(
    String text,
    OcvRule rule,
    double confidence,
    DateTime now,
  ) {
    final numReg = RegExp(r'\d+');
    final match = numReg.firstMatch(text);

    if (match == null) {
      return OcvEvaluationResult(
        status: OcvStatus.fail,
        rule: rule,
        extractedText: text,
        explanation: 'No numeric values detected for numeric range validation.',
        timestamp: now,
        confidence: confidence,
      );
    }

    final value = num.parse(match.group(0)!);

    if (rule.minNumber != null && value < rule.minNumber!) {
      return OcvEvaluationResult(
        status: OcvStatus.fail,
        rule: rule,
        extractedText: text,
        matchedSubstring: value.toString(),
        explanation: 'Value $value is below minimum required (${rule.minNumber}).',
        timestamp: now,
        confidence: confidence,
      );
    }

    if (rule.maxNumber != null && value > rule.maxNumber!) {
      return OcvEvaluationResult(
        status: OcvStatus.fail,
        rule: rule,
        extractedText: text,
        matchedSubstring: value.toString(),
        explanation: 'Value $value exceeds maximum allowed (${rule.maxNumber}).',
        timestamp: now,
        confidence: confidence,
      );
    }

    return OcvEvaluationResult(
      status: OcvStatus.pass,
      rule: rule,
      extractedText: text,
      matchedSubstring: value.toString(),
      explanation: 'Numeric value $value is within valid bounds [${rule.minNumber ?? '-∞'}..${rule.maxNumber ?? '∞'}].',
      timestamp: now,
      confidence: confidence,
    );
  }

  List<CharacterDiff> _computeCharacterDiffs(String expected, String actual) {
    final diffs = <CharacterDiff>[];
    final maxLen = max(expected.length, actual.length);

    for (var i = 0; i < maxLen; i++) {
      final expChar = i < expected.length ? expected[i] : '∅';
      final actChar = i < actual.length ? actual[i] : '∅';

      if (expChar != actChar) {
        diffs.add(CharacterDiff(
          position: i,
          expectedChar: expChar,
          actualChar: actChar,
        ));
      }
    }

    return diffs;
  }
}

final ocvEngineProvider = Provider<OcvEngine>((ref) {
  return const OcvEngine();
});
