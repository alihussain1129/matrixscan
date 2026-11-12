import 'package:flutter/material.dart';

/// Centers page content and caps its width. Padding grows with the screen:
/// 16 on phones, 24 on tablets, 32 on desktop.
class ExaltedPageFrame extends StatelessWidget {
  const ExaltedPageFrame({super.key, required this.child, this.maxWidth = 980});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final pad = w < 600 ? 16.0 : (w < 1000 ? 24.0 : 32.0);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
