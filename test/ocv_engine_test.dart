import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/features/ocv/models/ocv_evaluation_result.dart';
import 'package:exalted/features/ocv/models/ocv_rule.dart';
import 'package:exalted/features/ocv/services/ocv_engine.dart';
import 'package:exalted/features/ocv/services/ocv_rules_repository.dart';

void main() {
  final fixedClock = DateTime(2026, 11, 2, 12, 0);
  final engine = OcvEngine(clock: () => fixedClock);

  group('OcvEngine Rule Evaluation', () {
    test('Exact match passes on identical string', () {
      const rule = OcvRule(
        id: 'r1',
        name: 'Exact Code',
        type: OcvRuleType.exactMatch,
        pattern: 'BATCH-2026-X',
      );

      final result = engine.evaluate('BATCH-2026-X', rule);
      expect(result.status, equals(OcvStatus.pass));
      expect(result.isPass, isTrue);
      expect(result.diffs, isEmpty);
    });

    test('Exact match fails and reports character diffs on mismatch', () {
      const rule = OcvRule(
        id: 'r1',
        name: 'Exact Code',
        type: OcvRuleType.exactMatch,
        pattern: 'BATCH-2026-A',
      );

      final result = engine.evaluate('BATCH-2026-B', rule);
      expect(result.status, equals(OcvStatus.fail));
      expect(result.isFail, isTrue);
      expect(result.diffs.length, equals(1));
      expect(result.diffs.first.position, equals(11));
      expect(result.diffs.first.expectedChar, equals('A'));
      expect(result.diffs.first.actualChar, equals('B'));
    });

    test('Low confidence returns inconclusive', () {
      const rule = OcvRule(
        id: 'r1',
        name: 'High Confidence Lot',
        type: OcvRuleType.regex,
        pattern: r'LOT-[0-9]{4}',
        minConfidence: 0.85,
      );

      final result = engine.evaluate('LOT-9942', rule, confidence: 0.70);
      expect(result.status, equals(OcvStatus.inconclusive));
      expect(result.isInconclusive, isTrue);
      expect(result.explanation, contains('below the required industrial threshold'));
    });

    test('Empty text returns noText', () {
      const rule = OcvRule(
        id: 'r1',
        name: 'Any',
        type: OcvRuleType.regex,
        pattern: r'.*',
      );

      final result = engine.evaluate('   ', rule);
      expect(result.status, equals(OcvStatus.noText));
    });

    test('Expiry date in future passes', () {
      const rule = OcvRule(
        id: 'r_exp',
        name: 'Expiry Check',
        type: OcvRuleType.expiryDate,
        pattern: r'\d{2}/\d{4}',
      );

      // Current fixed clock is Nov 2026. Dec 2026 is future.
      final result = engine.evaluate('EXP: 12/2026', rule);
      expect(result.status, equals(OcvStatus.pass));
    });

    test('Expired date fails with explanation', () {
      const rule = OcvRule(
        id: 'r_exp',
        name: 'Expiry Check',
        type: OcvRuleType.expiryDate,
        pattern: r'\d{2}/\d{4}',
      );

      // Current fixed clock is Nov 2026. Oct 2026 has passed.
      final result = engine.evaluate('EXP: 10/2026', rule);
      expect(result.status, equals(OcvStatus.fail));
      expect(result.explanation, contains('Expired'));
    });

    test('Numeric range check validates bounds', () {
      const rule = OcvRule(
        id: 'r_num',
        name: 'Batch Limit',
        type: OcvRuleType.numericRange,
        pattern: r'\d+',
        minNumber: 100,
        maxNumber: 500,
      );

      expect(engine.evaluate('SERIAL 250', rule).status, equals(OcvStatus.pass));
      expect(engine.evaluate('SERIAL 50', rule).status, equals(OcvStatus.fail));
      expect(engine.evaluate('SERIAL 750', rule).status, equals(OcvStatus.fail));
    });
  });

  group('OcvRulesRepository', () {
    late Directory tempDir;
    late OcvRulesRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ocv_repo_test_');
      repo = OcvRulesRepository(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Loads factory presets on empty directory', () async {
      final rules = await repo.loadRules();
      expect(rules.length, greaterThanOrEqualTo(4));
      expect(rules.any((r) => r.type == OcvRuleType.lotCode), isTrue);
      expect(rules.any((r) => r.type == OcvRuleType.expiryDate), isTrue);
    });

    test('Saves and loads custom rules', () async {
      const customRule = OcvRule(
        id: 'custom_aerospace',
        name: 'Aerospace Part Spec',
        type: OcvRuleType.regex,
        pattern: r'AS-[0-9]{6}',
      );

      await repo.upsertRule(customRule);
      final reloaded = await repo.loadRules();
      expect(reloaded.any((r) => r.id == 'custom_aerospace'), isTrue);

      await repo.deleteRule('custom_aerospace');
      final afterDelete = await repo.loadRules();
      expect(afterDelete.any((r) => r.id == 'custom_aerospace'), isFalse);
    });
  });
}
