import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';

/// Create an account.
class SignupScreen extends ConsumerStatefulWidget {
  final bool isRoot;

  const SignupScreen({super.key, this.isRoot = false});

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

      final signedInImmediately = response.session != null;

      messenger.showSnackBar(SnackBar(
        content: Text(
            signedInImmediately ? t.savedToFavorites : t.accountCreated),
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
    final isLight = theme.brightness == Brightness.light;
    final bangla = ref.watch(isBanglaProvider);

    final primaryAccent =
        isLight ? AppTheme.primary : const Color(0xFF90CAF9);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.createAccount),
        actions: [
          TextButton.icon(
            onPressed: () =>
                ref.read(settingsProvider.notifier).toggleLanguage(),
            icon: Icon(Icons.language, size: 16, color: primaryAccent),
            label: Text(
              bangla ? 'English' : 'বাংলা',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: primaryAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: primaryAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.storefront_rounded,
                            size: 40,
                            color: primaryAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t.createAccount,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bangla
                            ? 'বাজারের সেরা দাম ট্র্যাক করতে অ্যাকাউন্ট তৈরি করুন'
                            : 'Create an account to track the best prices and deals',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isLight
                              ? const Color(0xFF5A6578)
                              : const Color(0xFFBAC3D6),
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
                        validator: (v) =>
                            _isValidEmail(v) ? null : t.invalidEmail,
                      ),
                      const SizedBox(height: 16),
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
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.length < 8)
                            ? t.passwordTooShort
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmCtrl,
                        decoration: InputDecoration(
                          labelText: t.confirmPassword,
                          prefixIcon: const Icon(Icons.lock_reset_outlined),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _loading ? null : _signup(),
                        validator: (v) => v != _passwordCtrl.text
                            ? t.passwordsDontMatch
                            : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _loading ? null : _signup,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  t.signUp,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            bangla
                                ? 'ইতিমধ্যে অ্যাকাউন্ট আছে? '
                                : 'Already have an account? ',
                            style: TextStyle(
                              color: isLight
                                  ? const Color(0xFF555F71)
                                  : const Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: _loading
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            child: Text(
                              bangla ? 'সাইন ইন করুন' : 'Sign in',
                              style: TextStyle(
                                color: primaryAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
  if (msg.contains('already registered') ||
      msg.contains('already been registered')) {
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
