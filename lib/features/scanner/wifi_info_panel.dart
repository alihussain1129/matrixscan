import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_spacing.dart';
import 'wifi_utils.dart';

/// Network details for a scanned Wi-Fi code. The password stays hidden until
/// the user reveals it.
class WifiInfoPanel extends StatefulWidget {
  const WifiInfoPanel({super.key, required this.wifi});

  final WifiNetworkInfo wifi;

  @override
  State<WifiInfoPanel> createState() => _WifiInfoPanelState();
}

class _WifiInfoPanelState extends State<WifiInfoPanel> {
  bool _reveal = false;

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: widget.wifi.password));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Password copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String? _note(WifiNetworkInfo wifi) {
    if (wifi.canConnect) return null;
    if (wifi.security == WifiSecurity.unsupported) {
      return "This security type can't be joined automatically.";
    }
    return "This code has no password, so it can't be joined automatically.";
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final wifi = widget.wifi;
    final hasPassword = wifi.password.isNotEmpty;
    final note = _note(wifi);

    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 80, child: Text(label, style: text.bodySmall)),
          Expanded(child: value),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Network', SelectableText(wifi.ssid, style: text.bodyLarge)),
            row('Security', Text(wifi.securityLabel, style: text.bodyMedium)),
            if (wifi.hidden) row('Hidden', Text('Yes', style: text.bodyMedium)),
            if (hasPassword)
              row(
                'Password',
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _reveal ? wifi.password : '\u2022' * 8,
                        style: text.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: _reveal ? 'Hide password' : 'Show password',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _reveal ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _reveal = !_reveal),
                    ),
                  ],
                ),
              ),
            if (hasPassword)
              TextButton.icon(
                onPressed: _copyPassword,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy password'),
              ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(note, style: text.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
