import 'package:flutter/material.dart';
import '../../core/constants/brand.dart';
import '../../core/widgets/exalted_logo.dart';

/// Temporary home screen. Becomes the real scanner in Phase 3.
class ScannerPlaceholder extends StatelessWidget {
  const ScannerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              ExaltedLogo(),
              SizedBox(height: 32),
              Text(
                'Phase 1 · Foundation ready',
                style: TextStyle(
                  color: Brand.gray,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}