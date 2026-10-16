// services/ai_service.dart
// COMPLETE - All AI features for ClipVault
// Handles: AI Tagging, Captions, Hashtags, Subtitles, Translation, Summarization

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final String _baseUrl =
      'https://us-central1-social-downloader-2d02b.cloudfunctions.net/apiV1';

  // ──────────────────────────────────────────────────────────────────────────
  // FEATURE 1: SMART AUTO-ORGANIZATION
  // ──────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> analyzeVideo({
    required String title,
    String? description,
    String? platform,
    String? duration,
    String? thumbnailUrl,
  }) async {
    try {
      final token = await _getIdToken();

      final response = await http.post(
        Uri.parse('$_baseUrl/analyzeVideo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'description': description ?? '',
          'platform': platform ?? 'unknown',
          'duration': duration ?? '',
          'thumbnailUrl': thumbnailUrl ?? '',
        }),
      );

      if (response.statusCode == 402) {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'error': data['error'] ?? 'Insufficient AI credits',
          'tags': data['fallbackTags'] ?? _getFallbackTags(),
          'remainingCredits': 0,
        };
      }

      if (response.statusCode != 200) {
        throw Exception('AI analysis failed: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return {
        'success': true,
        'tags': data['tags'] ?? _getFallbackTags(),
        'remainingCredits': data['remainingCredits'] ?? 0,
      };
    } catch (e) {
      debugPrint('Analyze video error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'tags': _getFallbackTags(),
        'remainingCredits': 0,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getAnalyzedVideos({int limit = 50}) async {
    try {
      final token = await _getIdToken();

      final response = await http.get(
        Uri.parse('$_baseUrl/getAnalyzedVideos?limit=$limit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get analyzed videos: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['videos'] ?? []);
    } catch (e) {
      debugPrint('Get analyzed videos error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> checkBrandingAllowance() async {
    final token = await _getIdToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/checkBrandingAllowance'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Could not check branding allowance: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> consumeBrandingUse() async {
    final token = await _getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/consumeBrandingUse'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(
          body['error']?.toString() ?? 'Could not record branding use');
    }
    return body;
  }

  Future<Map<String, dynamic>?> getDailyChallenge() async {
    try {
      final token = await _getIdToken();
      final response = await http.get(
        Uri.parse('$_baseUrl/getDailyChallenge'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        debugPrint('getDailyChallenge failed: ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('getDailyChallenge error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> completeDailyChallenge() async {
    try {
      final token = await _getIdToken();
      final response = await http.post(
        Uri.parse('$_baseUrl/completeDailyChallenge'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': data['error'] ?? 'Could not complete challenge'
        };
      }
      return data;
    } catch (e) {
      debugPrint('completeDailyChallenge error: $e');
      return {'success': false, 'error': 'Network error — try again'};
    }
  }

  Future<Map<String, dynamic>> getCoachProfile() async {
    try {
      final token = await _getIdToken();
      final response = await http.get(
        Uri.parse('$_baseUrl/getCoachProfile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        debugPrint('getCoachProfile failed: ${response.body}');
        return {
          'streak': 0,
          'points': 0,
          'niche': null,
          'goal': null,
          'name': null
        };
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('getCoachProfile error: $e');
      return {
        'streak': 0,
        'points': 0,
        'niche': null,
        'goal': null,
        'name': null
      };
    }
  }

  Future<bool> saveCoachProfile({
    required String niche,
    required String goal,
    required String name,
  }) async {
    try {
      final token = await _getIdToken();
      final response = await http.post(
        Uri.parse('$_baseUrl/saveCoachProfile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'niche': niche, 'goal': goal, 'name': name}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('saveCoachProfile error: $e');
      return false;
    }
  }

  /// Largest video the backend will analyze — keep in step with
  /// MAX_VIDEO_BYTES in functions/lib/videoAnalysis.js (24MB).
  static const int _maxAnalysisBytes = 24 * 1024 * 1024;

  /// Uploads a video the app already has on the phone to a private temp
  /// path, asks the server to transcribe and summarize it, and returns
  /// the analysisKey. Null means "analysis isn't possible" (file missing,
  /// too large, offline, not Pro, budget used) — never an error the
  /// caller has to handle; just a signal to fall back to title-only.
  ///
  /// Existing callers that only care about the key should keep using this
  /// method. Callers that need the transcript or summary should use
  /// [analyzeVideoFileFull] below.
  Future<String?> analyzeVideoFile(String localPath) async {
    final result = await analyzeVideoFileFull(localPath);
    return result?['analysisKey'] as String?;
  }

  /// Same as [analyzeVideoFile], but returns the full analysis payload:
  /// {analysisKey, summary, keyPhrases, transcript, durationMinutes}.
  /// Used by Smart Translator's Video tab, which needs the raw transcript
  /// for translation — a summary would lose the exact words.
  Future<Map<String, dynamic>?> analyzeVideoFileFull(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('analyzeVideoFileFull: file not found at $localPath');
        return null;
      }
      final size = await file.length();
      if (size == 0 || size > _maxAnalysisBytes) {
        debugPrint(
            'analyzeVideoFileFull: size $size outside bounds (max $_maxAnalysisBytes)');
        return null;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('analyzeVideoFileFull: no signed-in user');
        return null;
      }

      final storagePath =
          'users/$uid/analysis_temp/${DateTime.now().millisecondsSinceEpoch}.mp4';
      await FirebaseStorage.instance
          .ref(storagePath)
          .putFile(file, SettableMetadata(contentType: 'video/mp4'));

      final token = await _getIdToken();
      final response = await http.post(
        Uri.parse('$_baseUrl/analyzeVideo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'storagePath': storagePath}),
      );
      if (response.statusCode != 200) {
        debugPrint(
            'analyzeVideoFileFull failed (${response.statusCode}): ${response.body}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('analyzeVideoFileFull: success, key=${data['analysisKey']}, '
          'transcriptLength=${(data['transcript'] as String?)?.length ?? 0}');
      return data;
    } catch (e) {
      debugPrint('analyzeVideoFileFull error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> getLibraryStats() async {
    try {
      final token = await _getIdToken();

      final response = await http.get(
        Uri.parse('$_baseUrl/getLibraryStats'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get library stats: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return data['stats'] ?? {};
    } catch (e) {
      debugPrint('Library stats error: $e');
      return {
        'total': 0,
        'categories': {},
        'moods': {},
        'platforms': {},
        'topKeywords': {},
      };
    }
  }

  Future<List<Map<String, dynamic>>> getCollectionSuggestions() async {
    try {
      final token = await _getIdToken();

      final response = await http.post(
        Uri.parse('$_baseUrl/suggestCollections'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get suggestions: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['suggestions'] ?? []);
    } catch (e) {
      debugPrint('Collection suggestions error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FEATURE 2: REPURPOSE STUDIO
  // ──────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> processAction({
    required String actionId,
    String? videoId,
    String? videoTitle,
    String? videoPath,
    String? platform,
    String? analysisKey,
  }) async {
    try {
      final token = await _getIdToken();

      final response = await http.post(
        Uri.parse('$_baseUrl/processRepurposeAction'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'actionId': actionId,
          'videoId': videoId ?? '',
          'videoTitle': videoTitle ?? '',
          'videoPath': videoPath ?? '',
          'platform': platform ?? 'unknown',
          if (analysisKey != null && analysisKey.isNotEmpty)
            'analysisKey': analysisKey,
        }),
      );

      if (response.statusCode == 402) {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'error': data['error'] ?? 'Insufficient AI credits',
          'result': null,
          'remainingCredits': 0,
        };
      }

      if (response.statusCode != 200) {
        throw Exception('Action failed: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return {
        'success': true,
        'result': data['result'],
        'remainingCredits': data['remainingCredits'] ?? 0,
        'creditsUsed': data['creditsUsed'] ?? 0,
      };
    } catch (e) {
      debugPrint('Process action error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'result': null,
        'remainingCredits': 0,
      };
    }
  }

  Future<Map<String, dynamic>> generateCaptions({
    required String title,
    String? platform,
  }) async {
    return processAction(
      actionId: 'caption',
      videoTitle: title,
      platform: platform,
    );
  }

  Future<Map<String, dynamic>> generateHashtags({
    required String title,
    String? platform,
  }) async {
    return processAction(
      actionId: 'hashtags',
      videoTitle: title,
      platform: platform,
    );
  }

  Future<Map<String, dynamic>> generateSubtitles({
    required String videoPath,
    String? videoTitle,
  }) async {
    return processAction(
      actionId: 'subtitle',
      videoPath: videoPath,
      videoTitle: videoTitle,
    );
  }

  Future<Map<String, dynamic>> translateContent({
    required String videoTitle,
  }) async {
    return processAction(
      actionId: 'translate',
      videoTitle: videoTitle,
    );
  }

  Future<Map<String, dynamic>> summarizeContent({
    required String videoTitle,
  }) async {
    return processAction(
      actionId: 'summarize',
      videoTitle: videoTitle,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PREMIUM & CREDITS
  // ──────────────────────────────────────────────────────────────────────────

  /// The error fallback deliberately returns remainingCredits: null — NOT 0.
  /// The old fallback returned {'credits': 0, 'isPremium': false}, which no
  /// caller ever actually read (there is no 'credits' key in the real
  /// /getAICredits response shape), and every caller that did
  /// `credits['remainingCredits'] as int? ?? 0` silently turned a failed
  /// request into "0 credits" — which the Repurpose Studio UI then
  /// displayed as if the person genuinely had none, even when they were
  /// Pro. null means "unknown", and the UI can hide the badge instead.
  Future<Map<String, dynamic>> getAICredits() async {
    try {
      final token = await _getIdToken();

      final response = await http.get(
        Uri.parse('$_baseUrl/getAICredits'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get credits: ${response.body}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('Get AI credits error: $e');
      return {'isPremium': false, 'remainingCredits': null};
    }
  }

  Future<Map<String, dynamic>> verifyPremium() async {
    try {
      final token = await _getIdToken();

      final response = await http.get(
        Uri.parse('$_baseUrl/verifyPremium'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to verify premium: ${response.body}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('Verify premium error: $e');
      return {'isPremium': false, 'plan': 'none', 'aiCredits': 0};
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TRANSLATION
  // ──────────────────────────────────────────────────────────────────────────

  Future<String> translateText({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    try {
      final token = await _getIdToken();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/translateText'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'text': text,
              'targetLanguage': targetLanguage,
              'sourceLanguage': sourceLanguage ?? '',
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              'The translation service took too long to respond — please try again.',
            ),
          );

      if (response.statusCode != 200) {
        String message = 'Translation failed';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map && errBody['error'] is String) {
            message = errBody['error'] as String;
          }
        } catch (_) {
          // Body wasn't JSON — fall back to the generic message above.
        }
        throw Exception(message);
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final nested = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : const <String, dynamic>{};
      final value = data['translation'] ??
          data['translatedText'] ??
          data['translated_text'] ??
          nested['translation'] ??
          nested['translatedText'] ??
          nested['text'];
      if (value is! String || value.trim().isEmpty) {
        throw Exception('Translation API returned no translated text');
      }
      return value.trim();
    } catch (e) {
      debugPrint('Translation error: $e');
      rethrow;
    }
  }

  Future<String> detectLanguage(String text) async {
    try {
      final token = await _getIdToken();

      final response = await http.post(
        Uri.parse('$_baseUrl/detectLanguage'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode != 200) {
        throw Exception('Language detection failed: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return data['language'] ?? 'en';
    } catch (e) {
      debugPrint('Language detection error: $e');
      return 'en';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DOWNLOADS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> logDownload({
    required String platform,
    String? url,
    String? fileName,
    int? fileSize,
    String? quality,
  }) async {
    try {
      final token = await _getIdToken();

      await http.post(
        Uri.parse('$_baseUrl/logDownload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'platform': platform,
          'url': url ?? '',
          'fileName': fileName ?? '',
          'fileSize': fileSize ?? 0,
          'quality': quality ?? 'auto',
        }),
      );
    } catch (e) {
      debugPrint('Log download error: $e');
    }
  }

  Future<Map<String, dynamic>> getDownloadStats() async {
    try {
      final token = await _getIdToken();

      final response = await http.get(
        Uri.parse('$_baseUrl/getDownloadStats'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get stats: ${response.body}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('Get download stats error: $e');
      return {'totalDownloads': 0, 'dailyDownloads': 0, 'downloads': []};
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CLOUD VAULT
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCloudVaultFiles() async {
    try {
      final token = await _getIdToken();

      final response = await http.get(
        Uri.parse('$_baseUrl/getCloudVaultFiles'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get cloud files: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Get cloud vault files error: $e');
      return [];
    }
  }

  Future<bool> deleteCloudFile(String fileId) async {
    try {
      final token = await _getIdToken();

      final response = await http.post(
        Uri.parse('$_baseUrl/deleteCloudFile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'fileId': fileId}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete file: ${response.body}');
      }

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      debugPrint('Delete cloud file error: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ANALYTICS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> trackEvent(String event,
      {Map<String, dynamic>? properties}) async {
    try {
      final token = await _getIdToken();

      await http.post(
        Uri.parse('$_baseUrl/trackEvent'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': event,
          'properties': properties ?? {},
        }),
      );
    } catch (e) {
      debugPrint('Track event error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Future<String?> _getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated. Please sign in.');
    }
    return await user.getIdToken();
  }

  Map<String, dynamic> _getFallbackTags() {
    return {
      'category': 'Uncategorized',
      'mood': 'Neutral',
      'keywords': ['video', 'download', 'content'],
      'suggestedCollection': 'My Downloads',
      'topics': ['General'],
      'language': 'English',
      'sentiment': 'Neutral',
    };
  }

  Future<Map<String, dynamic>> healthCheck() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      );

      if (response.statusCode != 200) {
        return {'status': 'unhealthy', 'error': response.body};
      }

      return jsonDecode(response.body);
    } catch (e) {
      return {'status': 'unhealthy', 'error': e.toString()};
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
// REPURPOSE ACTION CONSTANTS
// ──────────────────────────────────────────────────────────────────────────

class RepurposeAction {
  static const String caption = 'caption';
  static const String hashtags = 'hashtags';
  static const String subtitle = 'subtitle';
  static const String translate = 'translate';
  static const String summarize = 'summarize';
  static const String compress = 'compress';
  static const String extractAudio = 'extract_audio';
  static const String ocr = 'ocr';

  static const List<String> all = [
    caption,
    hashtags,
    subtitle,
    translate,
    summarize,
    compress,
    extractAudio,
    ocr,
  ];

  static const Map<String, int> creditCost = {
    caption: 2,
    hashtags: 2,
    subtitle: 5,
    translate: 5,
    summarize: 5,
    compress: 1,
    extractAudio: 1,
    ocr: 2,
  };

  static const Map<String, String> displayNames = {
    caption: 'Generate Caption',
    hashtags: 'Generate Hashtags',
    subtitle: 'Create Subtitles',
    translate: 'Translate',
    summarize: 'Summarize',
    compress: 'Compress Video',
    extractAudio: 'Extract Audio',
    ocr: 'Extract Text',
  };

  static const Map<String, IconData> icons = {
    caption: Icons.text_fields_rounded,
    hashtags: Icons.tag_rounded,
    subtitle: Icons.closed_caption_rounded,
    translate: Icons.translate_rounded,
    summarize: Icons.auto_awesome_rounded,
    compress: Icons.compress_rounded,
    extractAudio: Icons.audiotrack_rounded,
    ocr: Icons.document_scanner_rounded,
  };

  static String getDisplayName(String actionId) {
    return displayNames[actionId] ?? actionId;
  }

  static int getCreditCost(String actionId) {
    return creditCost[actionId] ?? 1;
  }

  static IconData getIcon(String actionId) {
    return icons[actionId] ?? Icons.auto_awesome_rounded;
  }

  static bool isFreeAction(String actionId) {
    return getCreditCost(actionId) <= 1;
  }
}
