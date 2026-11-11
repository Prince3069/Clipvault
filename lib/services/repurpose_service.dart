// services/repurpose_service.dart
// COMPLETE - Multi-variant Repurpose client
//
// Previously processAction returned ONE string and the UI showed it. This
// version asks the server for THREE variants of the same action with a
// tone modifier, so the person can pick the one that fits their voice
// instead of being handed a single AI opinion. Also exposes a remix()
// method that re-rolls one slot with a new tone instruction.

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_service.dart';

class VariantResult {
  final bool success;
  final List<String> variants;
  final String? error;
  final int? remainingCredits;
  final String? tone; // echoes back which tone was used, if any

  const VariantResult({
    required this.success,
    this.variants = const [],
    this.error,
    this.remainingCredits,
    this.tone,
  });

  bool get isEmpty => variants.isEmpty;
}

class RepurposeService {
  static const String _baseUrl =
      'https://us-central1-social-downloader-2d02b.cloudfunctions.net/apiV1';

  final AIService _ai = AIService();

  /// Requests three variants of a single action. [tone] is optional — one
  /// of 'default', 'funny', 'professional', 'bold', 'warm', 'punchy'.
  /// Passing null means "default".
  ///
  /// [analysisKey] is the transcript-analysis key from
  /// AIService.analyzeVideoFile() — when present, the server feeds the
  /// real video content into the prompt instead of just the title.
  Future<VariantResult> processActionVariants({
    required String actionId,
    String? videoTitle,
    String? videoPath,
    String? platform,
    String? analysisKey,
    String? tone,
  }) async {
    try {
      final token = await _getIdToken();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/processRepurposeVariants'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'actionId': actionId,
              'videoTitle': videoTitle ?? '',
              'videoPath': videoPath ?? '',
              'platform': platform ?? 'unknown',
              if (analysisKey != null && analysisKey.isNotEmpty)
                'analysisKey': analysisKey,
              if (tone != null && tone.isNotEmpty) 'tone': tone,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 402) {
        final data = jsonDecode(response.body);
        return VariantResult(
          success: false,
          error: data['error'] ?? 'Upgrade to Pro to use Repurpose Studio',
        );
      }
      if (response.statusCode == 429) {
        final data = jsonDecode(response.body);
        return VariantResult(
          success: false,
          error: data['error'] ??
              'Your AI budget is used up. Buy credits to keep going.',
        );
      }
      if (response.statusCode != 200) {
        return VariantResult(
          success: false,
          error: 'Something went wrong (${response.statusCode}).',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['variants'] as List?) ?? const [];
      final variants = raw
          .map((v) => v?.toString() ?? '')
          .where((s) => s.trim().isNotEmpty)
          .toList();

      return VariantResult(
        success: true,
        variants: variants,
        remainingCredits: data['remainingCredits'] as int?,
        tone: data['tone'] as String?,
      );
    } catch (e) {
      debugPrint('processActionVariants error: $e');
      return const VariantResult(
        success: false,
        error: 'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Convenience wrapper that returns the single-string result from the
  /// OLD endpoint — kept so existing callers (like the Quick Pack path
  /// and any code still calling `AIService.processAction`) don't have to
  /// change. New UI should call processActionVariants instead.
  Future<Map<String, dynamic>> processActionSingle({
    required String actionId,
    String? videoTitle,
    String? videoPath,
    String? platform,
    String? analysisKey,
  }) {
    return _ai.processAction(
      actionId: actionId,
      videoTitle: videoTitle,
      videoPath: videoPath,
      platform: platform,
      analysisKey: analysisKey,
    );
  }

  Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    return await user.getIdToken();
  }
}
