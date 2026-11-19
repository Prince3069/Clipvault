// services/account_service.dart
// COMPLETE - Account linking for anonymous → Google / Email accounts
//
// Firebase's linkWithCredential() upgrades an anonymous user IN PLACE —
// the UID stays the same. That's the entire reason this is safe: every
// piece of data keyed by UID (premiumExpiry, cloudFiles, videoAnalysis,
// coachChallenges, downloadLog, events, aiCredits, aiBudget) stays
// attached. Sign out + sign in fresh would create a new UID and lose all
// of it.
//
// Two flows live here, each handling the same edge cases:
//   • Google: user taps one button, Google sheet appears, done.
//   • Email/password: user types email + password; if that email is
//     already registered, we surface a confirmation dialog rather than
//     silently doing the wrong thing.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum LinkResult {
  /// Success — the anonymous user is now linked to the new credential.
  success,

  /// The user cancelled the Google sheet or closed the email form.
  canceled,

  /// Email already registered to another Firebase account.
  emailAlreadyInUse,

  /// This exact Google account already belongs to another Firebase
  /// account. UI should offer to sign in instead of link.
  googleAlreadyInUse,

  /// Email/password sign-in was attempted and the password was wrong.
  wrongPassword,

  /// Firebase rejected the password for being too short or too simple.
  weakPassword,

  /// Firebase rejected the email format.
  invalidEmail,

  /// Network or unknown failure.
  failed,
}

class LinkOutcome {
  final LinkResult result;
  final String? message;
  final String? signedInEmail;

  const LinkOutcome(this.result, {this.message, this.signedInEmail});

  bool get isSuccess => result == LinkResult.success;
}

class AccountService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _google = GoogleSignIn.instance;
  Future<void>? _googleInitialization;

  Future<void> _initializeGoogle() =>
      _googleInitialization ??= _google.initialize();

  User? get currentUser => _auth.currentUser;

  /// True when the current user is anonymous (has no email, no provider).
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  /// True when the current user is linked to at least one real provider.
  bool get isLinked {
    final user = _auth.currentUser;
    if (user == null) return false;
    return !user.isAnonymous;
  }

  /// Display label for the current account, e.g. "Not signed in",
  /// "Anonymous", "you@example.com".
  String get accountLabel {
    final user = _auth.currentUser;
    if (user == null) return 'Not signed in';
    if (user.isAnonymous) return 'Anonymous account';
    return user.email ?? 'Linked account';
  }

  /// Which provider the linked account uses, for display. Empty when
  /// anonymous.
  String get providerLabel {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return '';
    final providers = user.providerData.map((p) => p.providerId).toList();
    if (providers.contains('google.com')) return 'Google';
    if (providers.contains('password')) return 'Email & password';
    return providers.join(', ');
  }

  // ─── Google ─────────────────────────────────────────────────────────

  /// Attempts to link the current anonymous user to a Google account.
  /// On success the UID is unchanged.
  Future<LinkOutcome> linkWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const LinkOutcome(LinkResult.failed, message: 'Not signed in');
    }

    GoogleSignInAccount? googleUser;
    try {
      await _initializeGoogle();
      googleUser = await _google.authenticate();
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      return const LinkOutcome(LinkResult.failed,
          message: 'Google sign-in is unavailable right now.');
    }

    if (googleUser == null) {
      return const LinkOutcome(LinkResult.canceled);
    }

    try {
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await user.linkWithCredential(credential);
      return LinkOutcome(LinkResult.success, signedInEmail: googleUser.email);
    } on FirebaseAuthException catch (e) {
      debugPrint('Google link error: ${e.code} ${e.message}');
      switch (e.code) {
        case 'credential-already-in-use':
          return LinkOutcome(LinkResult.googleAlreadyInUse,
              signedInEmail: googleUser.email);
        case 'email-already-in-use':
          return LinkOutcome(LinkResult.emailAlreadyInUse,
              signedInEmail: googleUser.email);
        case 'network-request-failed':
          return const LinkOutcome(LinkResult.failed,
              message: 'Check your internet connection and try again.');
        default:
          return LinkOutcome(LinkResult.failed,
              message: e.message ?? 'Could not link Google account.');
      }
    } catch (e) {
      debugPrint('Google link unknown error: $e');
      return const LinkOutcome(LinkResult.failed,
          message: 'Something went wrong. Try again.');
    }
  }

  /// Signs IN to an existing Google-linked account, replacing the current
  /// anonymous session. Only call this after the user has confirmed they
  /// understand their current anonymous library will not carry over.
  Future<LinkOutcome> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    try {
      await _initializeGoogle();
      googleUser = await _google.authenticate();
    } catch (e) {
      return const LinkOutcome(LinkResult.failed,
          message: 'Google sign-in is unavailable right now.');
    }

    if (googleUser == null) return const LinkOutcome(LinkResult.canceled);

    try {
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      return LinkOutcome(LinkResult.success, signedInEmail: googleUser.email);
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign-in error: ${e.code} ${e.message}');
      return LinkOutcome(LinkResult.failed,
          message: e.message ?? 'Could not sign in with Google.');
    }
  }

  // ─── Email / Password ───────────────────────────────────────────────

  /// First attempts to LINK the current anonymous user to a NEW
  /// email/password credential. If that email is already registered,
  /// returns [LinkResult.emailAlreadyInUse] and the caller should offer
  /// to sign in instead.
  Future<LinkOutcome> linkWithEmail({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const LinkOutcome(LinkResult.failed, message: 'Not signed in');
    }

    try {
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      await user.linkWithCredential(credential);
      // Google confirms an address automatically; email/password does
      // not. A verified address is what the server and security rules
      // check before granting owner / tester Pro, so ask for it now.
      await sendVerificationEmail();
      return LinkOutcome(LinkResult.success, signedInEmail: email);
    } on FirebaseAuthException catch (e) {
      debugPrint('Email link error: ${e.code} ${e.message}');
      switch (e.code) {
        case 'email-already-in-use':
        case 'credential-already-in-use':
        case 'account-exists-with-different-credential':
          return const LinkOutcome(LinkResult.emailAlreadyInUse);
        case 'provider-already-linked':
          return const LinkOutcome(LinkResult.failed,
              message: 'This account already has an email and password.');
        case 'weak-password':
          return const LinkOutcome(LinkResult.weakPassword,
              message: 'Password needs at least 8 characters.');
        case 'invalid-email':
          return const LinkOutcome(LinkResult.invalidEmail,
              message: 'That email address doesn\'t look right.');
        case 'network-request-failed':
          return const LinkOutcome(LinkResult.failed,
              message: 'Check your internet connection and try again.');
        default:
          return LinkOutcome(LinkResult.failed,
              message: e.message ?? 'Could not link email.');
      }
    } catch (e) {
      return const LinkOutcome(LinkResult.failed,
          message: 'Something went wrong. Try again.');
    }
  }

  /// Signs IN to an existing email/password account, replacing the
  /// current anonymous session.
  Future<LinkOutcome> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      final result = await _auth.signInWithCredential(credential);
      // Older email accounts were never sent a confirmation email.
      final signedIn = result.user;
      if (signedIn != null && !signedIn.emailVerified) {
        await sendVerificationEmail();
      }
      return LinkOutcome(LinkResult.success, signedInEmail: email);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return const LinkOutcome(LinkResult.wrongPassword,
              message: 'That password doesn\'t match this email.');
        case 'user-disabled':
          return const LinkOutcome(LinkResult.failed,
              message: 'This account has been disabled.');
        case 'too-many-requests':
          return const LinkOutcome(LinkResult.failed,
              message: 'Too many attempts. Wait a few minutes and try again.');
        case 'user-not-found':
          return const LinkOutcome(LinkResult.invalidEmail,
              message: 'No account uses this email.');
        case 'invalid-email':
          return const LinkOutcome(LinkResult.invalidEmail,
              message: 'That email address doesn\'t look right.');
        case 'network-request-failed':
          return const LinkOutcome(LinkResult.failed,
              message: 'Check your internet connection and try again.');
        default:
          return LinkOutcome(LinkResult.failed,
              message: e.message ?? 'Could not sign in.');
      }
    }
  }

  // ─── Email verification ─────────────────────────────────────────────

  /// True for an email/password account whose address isn't confirmed
  /// yet. Google accounts are always confirmed.
  bool get needsEmailVerification {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    final hasPassword =
        user.providerData.any((p) => p.providerId == 'password');
    final hasGoogle =
        user.providerData.any((p) => p.providerId == 'google.com');
    return hasPassword && !hasGoogle && !user.emailVerified;
  }

  /// Sends (or re-sends) the confirmation email. Returns null on success,
  /// or a message to show.
  Future<String?> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || user.emailVerified) return null;
    try {
      await user.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('sendEmailVerification error: ${e.code}');
      if (e.code == 'too-many-requests') {
        return 'An email was sent recently. Check your inbox (and spam), '
            'or try again in a few minutes.';
      }
      return e.message ?? 'Could not send the confirmation email.';
    } catch (e) {
      return 'Could not send the confirmation email.';
    }
  }

  /// Call after the person taps the link in the email. Reloads the
  /// account and fetches a NEW sign-in token, because the server reads
  /// "email verified" from the token and the old one still says false.
  /// Returns true when the address is now confirmed.
  Future<bool> refreshEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      final fresh = _auth.currentUser;
      if (fresh == null || !fresh.emailVerified) return false;
      await fresh.getIdToken(true);
      return true;
    } catch (e) {
      debugPrint('refreshEmailVerification error: $e');
      return false;
    }
  }

  // ─── Sign out ───────────────────────────────────────────────────────

  /// Signs out of the linked account and starts a fresh anonymous session,
  /// which is how the app runs when nobody is signed in. Everything stays
  /// saved under the account and comes back on the next sign-in.
  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;
      final usedGoogle =
          user?.providerData.any((p) => p.providerId == 'google.com') ??
              false;
      if (usedGoogle) {
        // Otherwise Google silently re-picks the same account next time.
        await _initializeGoogle();
        await _google.signOut();
      }
    } catch (e) {
      debugPrint('Google sign-out skipped: $e');
    }
    await _auth.signOut();
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      debugPrint('Anonymous sign-in after sign-out failed: $e');
    }
  }
}
