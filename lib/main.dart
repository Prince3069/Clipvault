// main.dart — Production ready with Universal Share Target & Splash Screen
// ignore_for_file: avoid_print

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/media_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/download_provider.dart';
import 'providers/premium_provider.dart';
import 'providers/cloud_vault_provider.dart';
import 'providers/notification_provider.dart';
import 'services/share_target_service.dart';
import 'services/notification_service.dart';
import 'services/timezone_service.dart';
import 'app.dart';

// ─── Web Entry Point ──────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF101326),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Firebase init: $e');
    if (kIsWeb) {
      try {
        await Firebase.initializeApp();
      } catch (webError) {
        print('Firebase web init fallback: $webError');
      }
    }
  }

  // Local notification channel for download-completion alerts.
  if (!kIsWeb) {
    try {
      await NotificationService.init();
      print('✅ Notification Service initialized');
    } catch (e) {
      print('⚠️ Notification Service init skipped: $e');
    }
  }

  // Anonymous authentication
  await _signInAnonymously();

  // Sync timezone (background, not awaited). Only hits the network when
  // the device's IANA zone differs from the last synced value.
  if (!kIsWeb) {
    TimezoneService.syncIfChanged();
  }

  // Share Target Service (Android only)
  if (!kIsWeb) {
    try {
      await ShareTargetService.instance.initialize();
      print('✅ Share Target Service initialized');
    } catch (e) {
      print('⚠️ Share Target Service init skipped: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MediaProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ChangeNotifierProvider(create: (_) => PremiumProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => CloudVaultProvider()),
        // NotificationProvider registers the FCM token on construction.
        // If permission is denied, it simply doesn't register — everything
        // else in the app keeps working.
        ChangeNotifierProvider(
          create: (_) => NotificationProvider()..initialize(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> _signInAnonymously() async {
  try {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      final cred = await auth.signInAnonymously();
      print('✅ New anonymous UID: ${cred.user?.uid}');
    } else {
      print('✅ Existing anonymous UID: ${auth.currentUser?.uid}');
    }
  } catch (e) {
    print('⚠️ Anonymous auth skipped (non-critical): $e');
  }
}