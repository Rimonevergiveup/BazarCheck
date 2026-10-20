import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import 'signup_screen.dart';

/// Sign in.
///
/// Can serve as either the initial root welcome screen or a pushed modal screen.
class LoginScreen extends ConsumerStatefulWidget {
  final bool isRoot;

  const LoginScreen({super.key, this.isRoot = false});

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
      if (!widget.isRoot && navigator.canPop()) {
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
    final isLight = theme.brightness == Brightness.light;
    final bangla = ref.watch(isBanglaProvider);

    final primaryAccent =
        isLight ? AppTheme.primary : const Color(0xFF90CAF9);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isRoot,
        title: Text(t.signIn),
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
                        t.appName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.signInToSaveHint,
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
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _loading ? null : _login(),
                        validator: (v) => (v == null || v.isEmpty)
                            ? t.passwordTooShort
                            : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
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
                                  t.signIn,
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
                            bangla ? 'অ্যাকাউন্ট নেই? ' : "Don't have an account? ",
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
                                : () async {
                                    final created =
                                        await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => SignupScreen(
                                            isRoot: widget.isRoot),
                                      ),
                                    );
                                    if (created == true && mounted) {
                                      _emailCtrl.text = _emailCtrl.text.trim();
                                    }
                                  },
                            child: Text(
                              bangla ? 'সাইন আপ করুন' : 'Sign up',
                              style: TextStyle(
                                color: primaryAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: isLight
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFF2D3748),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              bangla ? 'অথবা' : 'OR',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isLight
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: isLight
                                  ? const Color(0xFFE2E8F0)
                                  : const Color(0xFF2D3748),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () {
                                  if (widget.isRoot) {
                                    ref
                                        .read(guestModeProvider.notifier)
                                        .state = true;
                                  } else if (Navigator.of(context).canPop()) {
                                    Navigator.of(context).pop(false);
                                  }
                                },
                          icon: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: primaryAccent,
                          ),
                          label: Text(
                            t.continueAsGuest,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: primaryAccent,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: primaryAccent.withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
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
  final s = v.trim();
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
