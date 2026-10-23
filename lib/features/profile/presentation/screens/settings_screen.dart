import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/config/app_config.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/validators.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';

/// Settings: password change, download preference, and build information.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _wifiOnly = true;

  @override
  void initState() {
    super.initState();
    _wifiOnly = ref.read(preferencesProvider).downloadWifiOnly;
  }

  @override
  Widget build(BuildContext context) {
    final AppConfig config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('Playback and data'),
          SwitchListTile.adaptive(
            value: _wifiOnly,
            onChanged: (bool value) async {
              setState(() => _wifiOnly = value);
              await ref.read(preferencesProvider).setDownloadWifiOnly(value);
            },
            title: const Text('Download over Wi-Fi only'),
            subtitle: const Text(
              'Prevents mobile data charges when saving music',
            ),
          ),
          const Divider(height: 24),
          const _SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => _showChangePasswordSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete account'),
            subtitle: const Text(
              'Permanently removes your account and library',
            ),
            onTap: () => _confirmDeleteAccount(context),
          ),
          const Divider(height: 24),
          const _SectionHeader('About'),

          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('TuneFlow 1.0.0'),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => const _ChangePasswordSheet(),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This removes your account, likes and playlists. It cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        await ref.read(apiClientProvider).delete('/users/me');
        await ref.read(authControllerProvider.notifier).logout();
      } on AppException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondaryDark,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// The sheet owns its text controllers and disposes them in [State.dispose].
///
/// The previous implementation disposed them as soon as `showModalBottomSheet`'s future completed,
/// i.e. while the sheet was still animating out with a focused field in the tree - the framework
/// then delivered focus/IME callbacks into disposed controllers ("A TextEditingController was used
/// after being disposed") and red-screened the app. `State.dispose` only runs once the element is
/// fully deactivated, which is the guarantee the controllers need.
class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (mounted) {
        // Capture the messenger before the pop: the snackbar outlives the sheet.
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Password updated')),
        );
      }
    } on AppException catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.message;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Change password',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              ErrorBanner(message: _error!),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (String? value) =>
                  Validators.required(value, field: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: Validators.password,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
              validator: (String? value) =>
                  Validators.confirmPassword(value, _next.text),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update password'),
            ),
          ],
        ),
      ),
    );
  }
}
