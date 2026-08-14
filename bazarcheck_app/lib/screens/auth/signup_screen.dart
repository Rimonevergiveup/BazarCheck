import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers.dart';

/// Create an account.
///
/// Pops with `true` on success so the login screen underneath stays intact —
/// the original version called `pushReplacementNamed('/login')`, destroying the
/// widget that was listening for auth changes and leaving new users stuck.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final t = AppStrings.of(context);

    try {
      final response = await ref.read(authServiceProvider).signUpWithEmail(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
          );
      if (!mounted) return;

      // When email confirmation is off, Supabase returns a live session and
      // the user is already signed in — just close both auth screens.
      final signedInImmediately = response.session != null;

      messenger.showSnackBar(SnackBar(
        content: Text(signedInImmediately ? t.savedToFavorites : t.accountCreated),
      ));

      if (navigator.canPop()) navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlySignupError(e, t))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.createAccount)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.storefront,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      t.createAccount,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: InputDecoration(
                        labelText: t.email,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: (v) => _isValidEmail(v) ? null : t.invalidEmail,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      decoration: InputDecoration(
                        labelText: t.password,
                        prefixIcon: const Icon(Icons.lock_outline),
                        helperText: t.passwordTooShort,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      // 8 characters, not the original 6 — 6 is below every
                      // current baseline including Supabase's own default.
                      validator: (v) =>
                          (v == null || v.length < 8) ? t.passwordTooShort : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmCtrl,
                      decoration: InputDecoration(
                        labelText: t.confirmPassword,
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _signup(),
                      validator: (v) =>
                          v != _passwordCtrl.text ? t.passwordsDontMatch : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _signup,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(t.signUp),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed:
                          _loading ? null : () => Navigator.of(context).maybePop(),
                      child: Text(t.haveAccount),
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

bool _isValidEmail(String? v) {
  if (v == null) return false;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
}

String _friendlySignupError(Object e, AppStrings t) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('already registered') || msg.contains('already been registered')) {
    return t.isBangla
        ? 'এই ইমেইল দিয়ে অ্যাকাউন্ট আছে — সাইন ইন করুন'
        : 'That email already has an account — sign in instead';
  }
  if (msg.contains('password')) {
    return t.passwordTooShort;
  }
  if (msg.contains('socket') || msg.contains('network')) {
    return t.connectionHint;
  }
  return t.somethingWentWrong;
}
