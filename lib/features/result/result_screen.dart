import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../verify/verification_engine.dart';
import 'result_body.dart';

/// Full-screen details of one decoded code.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.raw,
    required this.symbology,
    this.source,
    this.scannedAt,
    this.decodeMicros,
    this.verifier,
    this.allowedSources = const {},
  });

  final String raw;
  final String symbology;
  final String? source;
  final DateTime? scannedAt;
  final int? decodeMicros;
  final VerificationEngine? verifier;
  final Set<String> allowedSources;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Decoded details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            ResultBody(
              raw: raw,
              symbology: symbology,
              source: source,
              scannedAt: scannedAt,
              decodeMicros: decodeMicros,
              verifier: verifier,
              allowedSources: allowedSources,
            ),
          ],
        ),
      ),
    );
  }
}