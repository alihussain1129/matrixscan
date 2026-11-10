import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/config_controller.dart';
import '../../core/config/platform_secret_store.dart';
import '../../core/theme/app_spacing.dart';

/// KEYENCE FTP receiver settings. The password is write-only: it goes to the
/// system keyring and never to config.json, logs or the screen.
class FtpSettingsCard extends ConsumerStatefulWidget {
  const FtpSettingsCard({super.key});

  @override
  ConsumerState<FtpSettingsCard> createState() => _FtpSettingsCardState();
}

class _FtpSettingsCardState extends ConsumerState<FtpSettingsCard> {
  late final TextEditingController _user;
  final TextEditingController _pass = TextEditingController();
  bool _enabled = false;
  bool? _hasPassword; // null = secure storage unavailable or not read yet
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final sc = ref.read(configControllerProvider).scanner;
    _user = TextEditingController(text: sc.ftpUsername ?? '');
    _enabled = sc.ftpReceiverEnabled;
    _loadHasPassword();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _loadHasPassword() async {
    try {
      final v = await ref
          .read(secretStoreProvider)
          .read(ScannerConfig.ftpPasswordSecretKey);
      if (!mounted) return;
      setState(() => _hasPassword = v != null && v.isNotEmpty);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasPassword = null;
        _message = 'Secure storage is unavailable, so FTP cannot be enabled.';
        _isError = true;
      });
    }
  }

  void _say(String message, {required bool error}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = error;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final user = _user.text.trim();
      final newPass = _pass.text;
      if (_enabled) {
        if (user.isEmpty) {
          _say('Enter a username to enable FTP.', error: true);
          return;
        }
        if (newPass.isEmpty && _hasPassword != true) {
          _say('Enter a password to enable FTP.', error: true);
          return;
        }
      }
      if (newPass.isNotEmpty) {
        await ref
            .read(secretStoreProvider)
            .write(ScannerConfig.ftpPasswordSecretKey, newPass);
      }
      final result = await ref.read(configControllerProvider.notifier).patch({
        'scanner': {
          'ftpUsername': user.isEmpty ? null : user,
          'ftpReceiverEnabled': _enabled,
        },
      });
      if (!result.applied) {
        _say(result.issues.map((i) => '$i').join('\n'), error: true);
      } else if (result.saveError != null) {
        _say('Applied, but could not be saved: ${result.saveError}',
            error: true);
      } else {
        _pass.clear();
        _say('Saved. Restart the app for the receiver to pick this up.',
            error: false);
      }
      await _loadHasPassword();
    } catch (e) {
      _say('Could not save (${e.runtimeType}).', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePassword() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(secretStoreProvider)
          .delete(ScannerConfig.ftpPasswordSecretKey);
      await ref
          .read(configControllerProvider.notifier)
          .patch({'scanner': {'ftpReceiverEnabled': false}});
      if (!mounted) return;
      setState(() => _enabled = false);
      await _loadHasPassword();
      _say('Password removed and FTP disabled.', error: false);
    } catch (e) {
      _say('Could not remove the password (${e.runtimeType}).', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('ftp-enable'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable FTP receiver'),
          subtitle: const Text(
            'Receives images from the reader. Off by default. '
            'Needs a username and a password.',
          ),
          value: _enabled,
          onChanged: _busy ? null : (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('ftp-user'),
          controller: _user,
          enabled: !_busy,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('ftp-pass'),
          controller: _pass,
          enabled: !_busy,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: _hasPassword == true
                ? 'A password is stored in the system keyring. '
                      'Leave blank to keep it.'
                : 'Stored in the system keyring, never in config.json.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            FilledButton(
              key: const Key('ftp-save'),
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
            const SizedBox(width: AppSpacing.md),
            if (_hasPassword == true)
              TextButton(
                key: const Key('ftp-remove'),
                onPressed: _busy ? null : _removePassword,
                child: const Text('Remove password'),
              ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _message!,
            style: text.bodySmall?.copyWith(
              color: _isError ? scheme.error : scheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}
