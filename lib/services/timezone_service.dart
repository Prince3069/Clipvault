// services/timezone_service.dart
// Syncs the device's IANA timezone name to the server, so daily and
// monthly free-tier limits reset at the user's local midnight rather than
// at UTC midnight. Without this, a user in Lagos gets "tomorrow's" free
// downloads at 1 AM, and a user in Auckland gets them at 12 PM. See
// functions/index.js's periodKeyFor() for the server side.

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TimezoneService {
  static const String _baseUrl =
      'https://us-central1-social-downloader-2d02b.cloudfunctions.net/apiV1';

  /// Called on app launch. Cheap: reads the device timezone, compares to
  /// what was last synced from this device, and only hits the server when
  /// they differ. Users who travel won't spam updates; users who never
  /// change zones never see a network call after the first successful sync.
  static Future<void> syncIfChanged() async {
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      final current = tz.identifier;
      if (current.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final lastSynced = prefs.getString('last_synced_timezone');
      if (lastSynced == current) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      if (token == null) return;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/updateTimezone'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'timezone': current}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await prefs.setString('last_synced_timezone', current);
        debugPrint('Timezone synced: $current');
      } else {
        debugPrint(
            'Timezone sync rejected (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      // Non-fatal — the server falls back to UTC if no timezone was ever
      // saved, which is exactly what the app did before this existed.
      debugPrint('Timezone sync failed: $e');
    }
  }
}
