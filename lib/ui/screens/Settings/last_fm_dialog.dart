import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/last_fm_service.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// Connects Riff to Last.fm, as Spotify's Settings › Apps › Last.fm does:
/// your Last.fm username and password (sent once to Last.fm, not kept), and
/// your own API key and secret when this build has none. Connected, it says
/// whom Riff scrobbles to, and stops it.
class LastFmDialog extends StatefulWidget {
  const LastFmDialog({super.key});

  @override
  State<LastFmDialog> createState() => _LastFmDialogState();
}

class _LastFmDialogState extends State<LastFmDialog> {
  final _user = TextEditingController(text: LastFmService.lastUser);
  final _password = TextEditingController();
  final _apiKey = TextEditingController(
      text: LastFmService.hasBuiltInKey ? '' : LastFmService.apiKey);
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;

  static final _apiAccount =
      Uri.parse('https://www.last.fm/api/account/create');

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _apiKey.dispose();
    _secret.dispose();
    super.dispose();
  }

  bool get _filled =>
      _user.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      (LastFmService.hasBuiltInKey ||
          (_apiKey.text.trim().isNotEmpty &&
              (_secret.text.trim().isNotEmpty || LastFmService.hasOwnSecret)));

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await LastFmService.connect(_user.text, _password.text,
          apiKey: _apiKey.text, secret: _secret.text);
    } on LastFmError catch (e) {
      error = e.badLogin
          ? 'lastFmBadLogin'.tr
          : e.badKey
              ? 'lastFmBadKey'.tr
              : e.message.isNotEmpty
                  ? e.message
                  : 'lastFmNoReach'.tr;
    } catch (_) {
      error = 'lastFmNoReach'.tr;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _disconnect() async {
    await LastFmService.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final user = LastFmService.user;
    if (user.isNotEmpty) {
      return AlertDialog(
        title: Text('lastFm'.tr),
        content: Text('lastFmConnectedAs'.trParams({'user': user})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('close'.tr),
          ),
          TextButton(
            onPressed: _disconnect,
            style:
                TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            child: Text('disconnect'.tr),
          ),
        ],
      );
    }
    void changed(String _) => setState(() {});
    return AlertDialog(
      title: Text('lastFm'.tr),
      content: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('lastFmDes'.tr, style: muted),
              const SizedBox(height: RiffSpacing.md),
              TextField(
                controller: _user,
                decoration: InputDecoration(labelText: 'username'.tr),
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                onChanged: changed,
              ),
              const SizedBox(height: RiffSpacing.sm),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: 'password'.tr),
                autofillHints: const [AutofillHints.password],
                onChanged: changed,
              ),
              const SizedBox(height: RiffSpacing.xs),
              Text('lastFmPasswordNote'.tr, style: muted),
              if (!LastFmService.hasBuiltInKey) ...[
                const SizedBox(height: RiffSpacing.md),
                Text('lastFmKeyHint'.tr, style: muted),
                TextButton(
                  onPressed: () => launchUrl(_apiAccount,
                      mode: LaunchMode.externalApplication),
                  child: Text('lastFmCreateApiAccount'.tr),
                ),
                TextField(
                  controller: _apiKey,
                  decoration: InputDecoration(labelText: 'lastFmApiKey'.tr),
                  onChanged: changed,
                ),
                const SizedBox(height: RiffSpacing.sm),
                TextField(
                  controller: _secret,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'lastFmSecret'.tr,
                    hintText: LastFmService.hasOwnSecret
                        ? 'lastFmSecretKept'.tr
                        : null,
                  ),
                  onChanged: changed,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: RiffSpacing.md),
                Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: _busy || !_filled ? null : _connect,
          child: _busy
              ? const SizedBox.square(
                  dimension: RiffComponentSizes.spinner,
                  child: CircularProgressIndicator(
                      strokeWidth: RiffComponentSizes.spinnerStroke))
              : Text('lastFmConnect'.tr),
        ),
      ],
    );
  }
}
