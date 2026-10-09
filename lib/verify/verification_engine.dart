import 'dart:async';

import '../interpret/interpreter.dart';
import '../interpret/scan_field.dart';
import 'open_food_facts_source.dart';
import 'structural_source.dart';
import 'verification.dart';

class VerificationReport {
  const VerificationReport({
    this.results = const [],
    this.notChecked = const [],
    this.conflicts = const [],
  });

  final List<SourceResult> results;

  /// Relevant sources that were not run because the user has not allowed them.
  final List<SourceInfo> notChecked;
  final List<String> conflicts;
}

class VerificationEngine {
  VerificationEngine(
    List<VerificationSource> sources, {
    this.timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _sources = List.unmodifiable(sources),
       _clock = clock ?? DateTime.now;

  final List<VerificationSource> _sources;
  final Duration timeout;
  final DateTime Function() _clock;

  /// Never throws. Sources that send data run only when listed in
  /// [allowedSources].
  Future<VerificationReport> verify(
    Interpretation base, {
    Set<String> allowedSources = const {},
  }) async {
    final toRun = <VerificationSource>[];
    final skipped = <SourceInfo>[];
    for (final s in _sources) {
      var applies = false;
      try {
        applies = s.appliesTo(base);
      } catch (_) {}
      if (!applies) continue;
      if (s.info.sendsData && !allowedSources.contains(s.info.id)) {
        skipped.add(s.info);
        continue;
      }
      toRun.add(s);
    }
    final results = await Future.wait([for (final s in toRun) _guard(s, base)]);
    return VerificationReport(
      results: results,
      notChecked: skipped,
      conflicts: _conflicts(results),
    );
  }

  Future<SourceResult> _guard(VerificationSource s, Interpretation base) async {
    final at = _clock();
    try {
      return _normalize(await s.check(base).timeout(timeout));
    } on TimeoutException {
      return SourceResult.unavailable(
        s.info,
        at,
        '${s.info.name} did not answer in time.',
      );
    } catch (e) {
      return SourceResult.unavailable(
        s.info,
        at,
        '${s.info.name} failed (${e.runtimeType}).',
      );
    }
  }

  SourceResult _normalize(SourceResult r) {
    if (r.info.authoritative) return r;
    return SourceResult(
      info: r.info,
      checkedAt: r.checkedAt,
      fields: r.fields,
      dataUpdatedAt: r.dataUpdatedAt,
      error: r.error,
      claims: [
        for (final c in r.claims)
          c.status == VerificationStatus.verified
              ? c.withStatus(
                  VerificationStatus.recordFound,
                  '${c.detail ?? ''} ${r.info.name} is not an authoritative '
                          'source, so this is not reported as verified.'
                      .trim(),
                )
              : c,
      ],
    );
  }

  List<String> _conflicts(List<SourceResult> results) {
    final byAspect = <String, Map<String, String>>{};
    for (final r in results) {
      for (final c in r.claims) {
        final v = c.value;
        if (v == null) continue;
        (byAspect[c.aspect] ??= {})[r.info.name] = v;
      }
    }
    final out = <String>[];
    byAspect.forEach((aspect, bySource) {
      final distinct = bySource.values.map((v) => v.trim().toLowerCase()).toSet();
      if (bySource.length >= 2 && distinct.length > 1) {
        final says = bySource.entries
            .map((e) => '${e.key} says "${e.value}"')
            .join('; ');
        out.add('Conflict on "$aspect": $says.');
      }
    });
    return out;
  }
}

/// The sources EXALTED ships with. New sources are added here.
VerificationEngine defaultVerificationEngine({HttpFetch? fetch}) =>
    VerificationEngine([
      StructuralSource(),
      OpenFoodFactsSource(fetch: fetch),
    ]);

String _iso(DateTime t) => t.toUtc().toIso8601String();

/// Returns [base] with enrichment, verification and provenance sections
/// placed before the raw payload. The raw and technical sections are kept.
Interpretation applyVerification(
  Interpretation base,
  VerificationReport report,
) {
  if (report.results.isEmpty && report.notChecked.isEmpty) return base;

  final enrichment = <ScanSection>[];
  final claimFields = <ScanField>[];
  final provenance = <ScanField>[];
  final warnings = <String>[...base.warnings, ...report.conflicts];

  var n = 0;
  for (final r in report.results) {
    final external = r.info.sendsData;
    if (r.fields.isNotEmpty) {
      enrichment.add(
        ScanSection(
          id: 'enrich.${r.info.id}',
          title: '${r.info.name}: database information (not in the barcode)',
          fields: r.fields,
        ),
      );
    }
    for (final c in r.claims) {
      n++;
      final updated = c.dataUpdatedAt == null
          ? ''
          : ' Source data last updated ${_iso(c.dataUpdatedAt!)}.';
      claimFields.add(
        ScanField(
          id: 'verify.${r.info.id}.$n',
          label: c.aspect,
          value: c.status.label,
          origin: external ? FieldOrigin.external : FieldOrigin.calculated,
          standard: r.info.name,
          validation: c.status == VerificationStatus.validFormat
              ? FieldValidation.valid
              : c.status == VerificationStatus.invalidFormat
              ? FieldValidation.invalid
              : FieldValidation.notChecked,
          verification: c.status == VerificationStatus.verified
              ? FieldVerification.verified
              : c.status == VerificationStatus.mismatch
              ? FieldVerification.mismatch
              : FieldVerification.notVerified,
          note:
              '${c.detail ?? ''} Source: ${r.info.name} '
                      '(${r.info.kind.label}); checked ${_iso(r.checkedAt)}.$updated'
                  .trim(),
          warning: c.status.isProblem ? (c.detail ?? c.status.label) : null,
          updatedAt: c.dataUpdatedAt,
        ),
      );
      if (c.status.isProblem) {
        warnings.add('${c.aspect}: ${c.status.label} (${r.info.name}).');
      }
    }
    provenance.add(
      ScanField(
        id: 'source.${r.info.id}',
        label: r.info.name,
        value: r.error == null
            ? 'Checked ${_iso(r.checkedAt)}'
            : 'Source unavailable',
        origin: external ? FieldOrigin.external : FieldOrigin.calculated,
        note:
            '${r.info.kind.label}. '
            '${r.info.authoritative ? 'Authoritative source.' : 'Not an authoritative source.'} '
            '${r.info.requirement}',
        warning: r.error,
        updatedAt: r.dataUpdatedAt,
      ),
    );
  }
  for (final s in report.notChecked) {
    provenance.add(
      ScanField(
        id: 'source.${s.id}',
        label: s.name,
        presence: FieldPresence.unavailable,
        origin: FieldOrigin.external,
        note:
            'Not checked: this online source is off. If enabled it would '
            'send: ${s.dataSent} ${s.requirement}',
      ),
    );
  }

  final added = <ScanSection>[
    ...enrichment,
    if (claimFields.isNotEmpty)
      ScanSection(
        id: 'verification',
        title: 'Verification results',
        fields: claimFields,
      ),
    ScanSection(id: 'provenance', title: 'Sources checked', fields: provenance),
  ];

  final sections = <ScanSection>[];
  var inserted = false;
  for (final s in base.sections) {
    if (!inserted && s.id == 'raw') {
      sections.addAll(added);
      inserted = true;
    }
    sections.add(s);
  }
  if (!inserted) sections.addAll(added);

  return Interpretation(
    interpreterId: base.interpreterId,
    formatName: base.formatName,
    sections: sections,
    warnings: warnings,
    rawIsSensitive: base.rawIsSensitive,
  );
}