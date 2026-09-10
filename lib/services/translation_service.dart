// services/translation_service.dart
// COMPLETE - Translation with Free Trial

import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';

class TranslationService {
  static const String _kFreeTranslationsUsed = 'free_translations_used';
  static const int _kMaxFreeTranslations = 1;

  final AIService _ai = AIService();

  Future<int> getRemainingFreeTranslations() async {
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_kFreeTranslationsUsed) ?? 0;
    return _kMaxFreeTranslations - used;
  }

  Future<bool> hasFreeTranslation() async {
    return (await getRemainingFreeTranslations()) > 0;
  }

  Future<void> useFreeTranslation() async {
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_kFreeTranslationsUsed) ?? 0;
    await prefs.setInt(_kFreeTranslationsUsed, used + 1);
  }

  Future<bool> canTranslate() async {
    final premium = await _ai.verifyPremium();
    if (premium['isPremium'] == true) return true;

    final credits = await _ai.getAICredits();
    if ((credits['credits'] ?? 0) >= 2) return true;

    return await hasFreeTranslation();
  }

  Future<Map<String, dynamic>> getRemainingTranslations() async {
    final premium = await _ai.verifyPremium();
    final credits = await _ai.getAICredits();
    final freeRemaining = await getRemainingFreeTranslations();

    return {
      'isPremium': premium['isPremium'] ?? false,
      'aiCredits': credits['credits'] ?? 0,
      'freeTranslationsRemaining': freeRemaining,
      'canTranslate': await canTranslate(),
    };
  }

  Future<Map<String, dynamic>> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final canTranslate = await this.canTranslate();
    if (!canTranslate) {
      return {
        'success': false,
        'error': 'No translations remaining. Please upgrade to Pro.',
        'needsUpgrade': true,
      };
    }

    try {
      bool usedFree = false;
      final hasFree = await hasFreeTranslation();

      if (hasFree) {
        await useFreeTranslation();
        usedFree = true;
      }

      final result = await _ai.translateText(
        text: text,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
      );

      return {
        'success': true,
        'translation': result,
        'usedFree': usedFree,
        'remainingFree': await getRemainingFreeTranslations(),
        'message': usedFree
            ? '✅ Free translation used! ${await getRemainingFreeTranslations()} left'
            : '✅ Translation complete!',
      };
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final used = prefs.getInt(_kFreeTranslationsUsed) ?? 0;
      if (used > 0) {
        await prefs.setInt(_kFreeTranslationsUsed, used - 1);
      }

      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  Future<void> resetFreeTranslations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFreeTranslationsUsed);
  }

  Future<bool> isOutOfTranslations() async {
    final canTranslate = await this.canTranslate();
    return !canTranslate;
  }
}
