// services/coach_insights_service.dart
// Client-side wrapper for the coach-insights endpoint. The server does
// the real work (aggregating the user's recent activity and generating a
// personalized challenge); this just calls it and returns the result.

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CoachInsightsService {
  static const String _baseUrl =
      'https://us-central1-social-downloader-2d02b.cloudfunctions.net/apiV1';

  /// Returns a personalized challenge for today, informed by the user's
  /// recent activity (recent downloads, recent repurpose actions, niche,
  /// streak). Cached server-side per calendar day, same as before.
  Future<Map<String, dynamic>?> getInsightfulDailyChallenge() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final token = await user.getIdToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$_baseUrl/getDailyChallenge'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('getDailyChallenge failed: ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('getInsightfulDailyChallenge error: $e');
      return null;
    }
  }
}
