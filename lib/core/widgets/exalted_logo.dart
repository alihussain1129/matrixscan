import 'package:flutter/material.dart';

import '../constants/brand.dart';

/// Temporary code-built logo. Replaced by the official SVG in Phase 2.
class ExaltedLogo extends StatelessWidget {
  const ExaltedLogo({super.key, this.width = 240});
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Brand.red,
            padding: EdgeInsets.symmetric(
              vertical: width * 0.05,
              horizontal: width * 0.06,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'EXALTED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: width * 0.16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: width * 0.02,
                  height: 1,
                ),
              ),
            ),
          ),
          SizedBox(height: width * 0.03),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'CODING & PACKING SOLUTIONS',
              style: TextStyle(
                color: Brand.gray,
                fontSize: width * 0.05,
                fontWeight: FontWeight.w700,
                letterSpacing: width * 0.007,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
