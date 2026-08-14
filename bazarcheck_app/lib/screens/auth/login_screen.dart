import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers.dart';
import 'signup_screen.dart';

/// Sign in.
///
/// Presented as a *pushed route* on top of the app, never as the app's root.
/// On success it pops itself, returning the user to whatever they were doing.
///
/// This is the fix for the original trap: sign-up used
/// `pushReplacementNamed('/login')`, which unmounted the `AuthGate` that was
/// listening for the auth state. Signing in then succeeded silently with
/// nothing left to navigate, stranding the user on the login form until they
/// force-restarted the app.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final t = AppStrings.of(context);

    try {
      await ref.read(authServiceProvider).signInWithEmail(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
          );
      if (!mounted) return;
      // Explicitly return control to the caller. Never leave the user on a
      // form that has already succeeded.
      if (navigator.canPop()) {
        navigator.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyAuthError(e, t))),
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
      appBar: AppBar(title: Text(t.signIn)),
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
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      t.appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.signInToSaveHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
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
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _login(),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? t.passwordTooShort : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(t.signIn),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      // push, NOT pushReplacement — this screen must stay on
                      // the stack so signup can pop back to it.
                      onPressed: _loading
                          ? null
                          : () async {
                              final created = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => const SignupScreen(),
                                ),
                              );
                              if (created == true && mounted) {
                                _emailCtrl.text = _emailCtrl.text.trim();
                              }
                            },
                      child: Text(t.noAccountYet),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: Text(t.continueAsGuest),
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
  final s = v.trim();
  // Deliberately permissive: one @, something either side, a dot in the domain.
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
}

/// Turns Supabase auth errors into something a person can act on.
String _friendlyAuthError(Object e, AppStrings t) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('invalid login credentials')) {
    return t.isBangla
        ? 'ইমেইল বা পাসওয়ার্ড সঠিক নয়'
        : 'Wrong email or password';
  }
  if (msg.contains('email not confirmed')) {
    return t.isBangla
        ? 'ইমেইল নিশ্চিত করা হয়নি — ইনবক্স দেখুন'
        : 'Email not confirmed — check your inbox';
  }
  if (msg.contains('socket') || msg.contains('network')) {
    return t.connectionHint;
  }
  return t.somethingWentWrong;
}
