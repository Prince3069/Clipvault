// services/translation_service.dart
// COMPLETE - Translation with Free Trial
//
// This used to track "1 free translation" in a local SharedPreferences
// counter that NEVER reset on its own — resetFreeTranslations() existed but
// nothing ever called it. So after a free user's first-ever translation,
// they'd be locked out forever, even though the server (index.js) resets
// its own free-tier counter every calendar month. The two disagreed, and
// the client's stricter, stale answer always won.
//
// It also checked `credits['credits']`, a field that never existed in the
// server's real /getAICredits response shape (which returns
// `remainingCredits` for premium users, or `used`/`limits` for free users)
// — so that check silently always evaluated to 0 and never actually did
// anything, including never recognizing purchased top-up credits.
//
// Fixed by removing the local gate entirely. The server is the only source
// of truth for whether a translation is allowed — this just calls it and
// reports back what it says, including its real error message when it says no.

import 'ai_service.dart';

class TranslationService {
  final AIService _ai = AIService();

  /// Pulls the real, current state from the server. Shape depends on
  /// whether the user is premium — see index.js's /getAICredits:
  /// premium:  {isPremium: true, planId, remainingCredits, ...}
  /// free:     {isPremium: false, used: {translateText: n}, limits: {...}}
  Future<Map<String, dynamic>> getRemainingTranslations() async {
    final credits = await _ai.getAICredits();
    final isPremium = credits['isPremium'] == true;

    if (isPremium) {
      final remainingCredits = credits['remainingCredits'] as int? ?? 0;
      return {
        'isPremium': true,
        'remainingCredits': remainingCredits,
        'canTranslate': remainingCredits > 0,
      };
    }

    final used = credits['used'] as Map<String, dynamic>? ?? {};
    final limits = credits['limits'] as Map<String, dynamic>? ?? {};
    final usedThisMonth = used['translateText'] as int? ?? 0;
    final monthlyLimit = limits['translateText'] as int? ?? 1;
    final freeRemaining = (monthlyLimit - usedThisMonth).clamp(0, monthlyLimit);

    return {
      'isPremium': false,
      'freeTranslationsRemaining': freeRemaining,
      'canTranslate': freeRemaining > 0,
    };
  }

  Future<bool> canTranslate() async {
    final state = await getRemainingTranslations();
    return state['canTranslate'] == true;
  }

  Future<bool> isOutOfTranslations() async {
    return !(await canTranslate());
  }

  /// Attempts the translation. The server is the only place that actually
  /// decides yes/no and consumes the allowance — this doesn't pre-check or
  /// track anything locally, so there's nothing here that can drift out of
  /// sync with what the server enforces.
  Future<Map<String, dynamic>> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    try {
      final result = await _ai.translateText(
        text: text,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
      );

      return {
        'success': true,
        'translation': result,
        'message': '✅ Translation complete!',
      };
    } catch (e) {
      // ai_service.dart already extracts the server's real error message
      // (e.g. "Your free translation for this month is used — upgrade to
      // Pro for unlimited, or wait until next month for another free
      // one.") — strip Dart's "Exception: " wrapper so the UI shows that
      // message cleanly instead of as a stack-trace-looking string.
      final message = e.toString().replaceFirst('Exception: ', '');
      final needsUpgrade = message.toLowerCase().contains('upgrade') ||
          message.toLowerCase().contains('budget');
      return {
        'success': false,
        'error': message,
        'needsUpgrade': needsUpgrade,
      };
    }
  }
}
