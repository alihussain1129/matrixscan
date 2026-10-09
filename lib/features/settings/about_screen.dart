import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/brand.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/exalted_card.dart';

// Company details. Change the spelling here if needed; it is used everywhere.
const String _companyName = 'Exalted Coding and Packging Solutions';
const String _companyEmail = 'Info@exalted.com.pk';
const String _companyAddress =
    '949-B Maulana Shaukat Ali Rd, Faisal Town, Lahore, Pakistan';

const String _developerName = 'Ali Hussain';
const String _developerRole = 'Core Developer';
const String _developerEmail = 'alihussainkhushimuhammad@gmail.com';
const String _developerDiscord = 'alihussain0503_03580';

/// About EXALTED: company information and core developer.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<ExaltedColors>()!;
    final text = theme.textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About EXALTED')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'Built with precision. Designed for reliable scanning.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('COMPANY INFORMATION', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            ExaltedCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _IconTile(icon: Icons.business_rounded, size: 48),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(_companyName, style: text.titleMedium),
                      ),
                    ],
                  ),
                  Divider(color: colors.outline, height: AppSpacing.xl),
                  _ContactRow(
                    icon: Icons.mail_outline_rounded,
                    label: 'Company email',
                    value: _companyEmail,
                    onTap: () => _openMail(context, _companyEmail),
                    onCopy: () => _copy(context, _companyEmail, 'Email'),
                    copyTooltip: 'Copy email',
                  ),
                  Divider(color: colors.outline, height: AppSpacing.lg),
                  _ContactRow(
                    icon: Icons.location_on_outlined,
                    label: 'Company address',
                    value: _companyAddress,
                    onTap: () => _openMap(context),
                    onCopy: () => _copy(context, _companyAddress, 'Address'),
                    copyTooltip: 'Copy address',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('CORE DEVELOPER', style: text.labelSmall),
            const SizedBox(height: AppSpacing.md),
            ExaltedCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Brand.red,
                        child: Text(
                          'AH',
                          style: text.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_developerName, style: text.titleLarge),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _developerRole,
                              style: text.bodyMedium?.copyWith(
                                color: Brand.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Divider(color: colors.outline, height: AppSpacing.xl),
                  _ContactRow(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    value: _developerEmail,
                    onTap: () => _openMail(context, _developerEmail),
                    onCopy: () => _copy(context, _developerEmail, 'Email'),
                    copyTooltip: 'Copy email',
                  ),
                  Divider(color: colors.outline, height: AppSpacing.lg),
                  _ContactRow(
                    icon: Icons.forum_outlined,
                    label: 'Discord',
                    value: _developerDiscord,
                    onTap: () => _copy(context, _developerDiscord, 'Discord'),
                    onCopy: () => _copy(context, _developerDiscord, 'Discord'),
                    copyTooltip: 'Copy Discord username',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _launch(
  BuildContext context,
  List<Uri> candidates,
  String failMessage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Try the next option.
    }
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failMessage)));
}

Future<void> _openMail(BuildContext context, String address) {
  return _launch(context, [
    Uri(scheme: 'mailto', path: address),
  ], 'No email app found. Long-press or use the copy button instead.');
}

Future<void> _openMap(BuildContext context) {
  final query = Uri.encodeComponent(_companyAddress);
  return _launch(context, [
    Uri.parse('geo:0,0?q=$query'),
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
  ], 'No maps app found. Use the copy button instead.');
}

Future<void> _copy(BuildContext context, String value, String label) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: value));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$label copied')));
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.size = 36});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Icon(icon, color: Brand.red, size: size * 0.55),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.onCopy,
    required this.copyTooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final String copyTooltip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            _IconTile(icon: icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: text.bodySmall),
                    const SizedBox(height: 2),
                    Text(value, style: text.bodyLarge),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: copyTooltip,
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}
