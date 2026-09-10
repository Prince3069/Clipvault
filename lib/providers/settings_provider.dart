// providers/settings_provider.dart
// ADDED: autoSyncToCloud for Cloud Vault

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _showNotifications = true;
  bool _autoDetectLinks = true;
  bool _showFloatingButton = true;
  bool _isDarkMode = true;
  bool _autoSyncToCloud = false; // NEW
  String _downloadPath = '/storage/emulated/0/Download/ClipVaults';

  bool get showNotifications => _showNotifications;
  bool get autoDetectLinks => _autoDetectLinks;
  bool get showFloatingButton => _showFloatingButton;
  bool get isDarkMode => _isDarkMode;
  bool get autoSyncToCloud => _autoSyncToCloud; // NEW
  String get downloadPath => _downloadPath;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _showNotifications = prefs.getBool('showNotifications') ?? true;
    _autoDetectLinks = prefs.getBool('autoDetectLinks') ?? true;
    _showFloatingButton = prefs.getBool('showFloatingButton') ?? true;
    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    _autoSyncToCloud = prefs.getBool('autoSyncToCloud') ?? false; // NEW
    _downloadPath = prefs.getString('downloadPath') ??
        '/storage/emulated/0/Download/ClipVaults';
    notifyListeners();
  }

  Future<void> setShowNotifications(bool value) async {
    _showNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showNotifications', value);
  }

  Future<void> setAutoDetectLinks(bool value) async {
    _autoDetectLinks = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoDetectLinks', value);
  }

  Future<void> setShowFloatingButton(bool value) async {
    _showFloatingButton = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showFloatingButton', value);
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  // NEW
  Future<void> setAutoSyncToCloud(bool value) async {
    _autoSyncToCloud = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSyncToCloud', value);
  }

  Future<void> setDownloadPath(String path) async {
    _downloadPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('downloadPath', path);
  }
}
