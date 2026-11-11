// ui/screens/account_link_screen.dart
// COMPLETE - Account linking UI (Google + Email/Password)
//
// The single most important account-safety surface in the app: this is
// where an anonymous user becomes a real one, keeping everything they
// already have (library, streak, Pro, cloud files) attached to the SAME
// UID. The screen exists as a full page rather than a dialog because the
// moment is worth taking seriously — users who skip this end up losing
// their data on reinstall and reviewing the app 1-star.
//
// Copy on this screen is deliberately specific about the value ("so you
// don't lose your library"), not generic ("sign up for an account").
// That framing is what actually gets people to complete the flow.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/account_service.dart';
import '../themes/app_theme.dart';

class AccountLinkScreen extends StatefulWidget {
  const AccountLinkScreen({Key? key}) : super(key: key);

  @override
  State<AccountLinkScreen> createState() => _AccountLinkScreenState();
}

class _AccountLinkScreenState extends State<AccountLinkScreen> {
  final AccountService _account = AccountService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  bool _showEmailForm = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ─── Actions ────────────────────────────────────────────────────────

  Future<void> _handleGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final outcome = await _account.linkWithGoogle();
    if (!mounted) return;

    if (outcome.isSuccess) {
      _onSuccess(outcome.signedInEmail ?? 'your Google account');
      return;
    }

    if (outcome.result == LinkResult.canceled) {
      setState(() => _busy = false);
      return;
    }

    if (outcome.result == LinkResult.googleAlreadyInUse ||
        outcome.result == LinkResult.emailAlreadyInUse) {
      setState(() => _busy = false);
      final email = outcome.signedInEmail ?? 'this account';
      await _offerSignInInstead(
        email: email,
        onConfirmGoogle: true,
      );
      return;
    }

    setState(() {
      _busy = false;
      _error = outcome.message ?? 'Could not link your Google account.';
    });
  }

  Future<void> _handleEmailLink() async {
    if (_busy) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      _emailFocus.requestFocus();
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password needs at least 8 characters.');
      _passwordFocus.requestFocus();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final outcome =
        await _account.linkWithEmail(email: email, password: password);
    if (!mounted) return;

    if (outcome.isSuccess) {
      _onSuccess(email);
      return;
    }

    if (outcome.result == LinkResult.emailAlreadyInUse) {
      setState(() => _busy = false);
      await _offerSignInInstead(email: email, onConfirmGoogle: false);
      return;
    }

    setState(() {
      _busy = false;
      _error = outcome.message ?? 'Could not link this email.';
    });
  }

  Future<void> _offerSignInInstead({
    required String email,
    required bool onConfirmGoogle,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'This account already exists',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '$email is already linked to another MediaNest account.\n\n'
          'Sign in to that account instead? Your current anonymous '
          'library, downloads, and any Pro subscription on THIS device '
          'will not carry over — they stay under the anonymous account.',
          style: const TextStyle(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign in instead'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    LinkOutcome outcome;
    if (onConfirmGoogle) {
      outcome = await _account.signInWithGoogle();
    } else {
      outcome = await _account.signInWithEmail(
        email: email,
        password: _passwordController.text,
      );
    }

    if (!mounted) return;

    if (outcome.isSuccess) {
      _onSuccess(outcome.signedInEmail ?? email);
      return;
    }

    setState(() {
      _busy = false;
      _error = outcome.message ?? 'Could not sign in.';
    });
  }

  void _onSuccess(String email) {
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You\'re all set. $email is now linked.',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(),
              const SizedBox(height: 28),
              _buildValuePoints(),
              const SizedBox(height: 28),
              _buildGoogleButton(),
              const SizedBox(height: 16),
              _buildDivider(),
              const SizedBox(height: 16),
              _buildEmailSection(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildError(),
              ],
              const SizedBox(height: 28),
              _buildFinePrint(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppShadows.primary,
          ),
          child: const Icon(
            Icons.shield_moon_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Save your account',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Right now your account only lives on this phone. Link a sign-in '
          'and your library, streak, and Pro subscription follow you '
          'anywhere — even after a reinstall.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _buildValuePoints() {
    const items = [
      (
        Icons.restore_rounded,
        'Reinstall without losing anything',
        'Your whole library comes back when you sign in.',
      ),
      (
        Icons.phone_iphone_rounded,
        'Use it on any phone',
        'One account, all your devices.',
      ),
      (
        Icons.workspace_premium_rounded,
        'Keep your Pro subscription safe',
        'Even a paid plan needs a real account to be recoverable.',
      ),
    ];

    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.$1, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$2,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.$3,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _busy ? null : _handleGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleGlyph(),
                  const SizedBox(width: 10),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: AppColors.border)),
      ],
    );
  }

  Widget _buildEmailSection() {
    if (!_showEmailForm) {
      return SizedBox(
        height: 52,
        child: OutlinedButton(
          onPressed: _busy
              ? null
              : () {
                  setState(() {
                    _showEmailForm = true;
                    _error = null;
                  });
                  Future.microtask(() => _emailFocus.requestFocus());
                },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            'Continue with email',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.alternate_email_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            enabled: !_busy,
            onSubmitted: (_) => _handleEmailLink(),
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'At least 8 characters',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _handleEmailLink,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Continue'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _showEmailForm = false;
                      _error = null;
                      _emailController.clear();
                      _passwordController.clear();
                    });
                  },
            child: const Text('Use a different method'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Already have an account with this email? Continue — we\'ll '
            'let you sign in instead of creating a new one.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinePrint() {
    return const Text(
      'Nothing is uploaded or shared. Linking only adds a sign-in method '
      'to the account you already have on this phone — your library, '
      'downloads, and settings stay exactly where they are.',
      style: TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        height: 1.55,
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ─── Google "G" glyph ────────────────────────────────────────────────────
// A hand-drawn approximation of the Google G using four colored arcs.
// Avoids bundling an asset just for one button, and stays recognizable
// without relying on Google's own assets (which have brand guidelines
// that would require a separate attribution screen).

class _GoogleGlyph extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.20;
    final rect = Offset.zero & size;
    final innerRect = Rect.fromCircle(
      center: rect.center,
      radius: (size.width - stroke) / 2,
    );

    final blue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final red = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final yellow = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final green = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(innerRect, -1.7, 1.5, false, blue);
    canvas.drawArc(innerRect, -3.4, 1.7, false, red);
    canvas.drawArc(innerRect, 1.8, 1.6, false, green);
    canvas.drawArc(innerRect, 3.5, 1.0, false, yellow);

    // The horizontal bar of the G.
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.52,
        size.height * 0.42,
        size.width * 0.42,
        stroke,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
