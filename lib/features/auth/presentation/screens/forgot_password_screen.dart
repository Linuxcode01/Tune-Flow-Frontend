import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/validators.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';

/// Two-step password reset: request a token, then set a new password.
///
/// In the development profile the API returns the token in the response (there is no SMTP server), so
/// the second step is reachable end-to-end without email. In production the token arrives by mail and
/// this screen starts at the same place, it just cannot pre-fill.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _tokenRequested = false;
  bool _submitting = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _requestToken() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final String? devToken =
          await ref.read(authRepositoryProvider).requestPasswordReset(_email.text.trim());
      setState(() {
        _tokenRequested = true;
        _token.text = devToken ?? '';
        _notice = devToken != null
            ? 'Reset token issued (shown here because this build talks to a development server).'
            : 'If that email has an account, a reset link is on its way.';
      });
    } on AppException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submitReset() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).resetPassword(
            token: _token.text.trim(),
            newPassword: _password.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated. You can sign in now.')),
        );
        context.pop();
      }
    } on AppException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('Reset your password',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      _tokenRequested
                          ? 'Enter the token you received and choose a new password.'
                          : 'We will send a reset token to your email.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondaryDark,
                          ),
                    ),
                    const SizedBox(height: 28),
                    if (_error != null) ...<Widget>[
                      ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                      const SizedBox(height: 16),
                    ],
                    if (_notice != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_notice!, style: Theme.of(context).textTheme.bodySmall),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      enabled: !_tokenRequested,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: Validators.email,
                    ),
                    if (_tokenRequested) ...<Widget>[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _token,
                        decoration: const InputDecoration(
                          labelText: 'Reset token',
                          prefixIcon: Icon(Icons.vpn_key_outlined),
                        ),
                        validator: (String? value) => Validators.required(value, field: 'Token'),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                          helperText: 'At least 8 characters, with a letter and a digit',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: Validators.password,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting
                          ? null
                          : (_tokenRequested ? _submitReset : _requestToken),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Text(_tokenRequested ? 'Set new password' : 'Send reset token'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
