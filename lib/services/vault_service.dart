// services/vault_service.dart - PIN + Decoy PIN only (no biometrics)

import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class VaultService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kPinKey = 'vault_pin_hash';
  static const String _kPinSet = 'vault_pin_set';
  static const String _kFakePinKey = 'vault_fake_pin_hash';
  static const String _kFakePinSet = 'vault_fake_pin_set';
  static const String _kFakeVaultDir = '.saveit_fake_vault';

  // ─── Vault Directory ──────────────────────────────────────────────────────

  Future<Directory> get vaultDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/.saveit_vault');
    if (!await dir.exists()) await dir.create(recursive: true);
    final nomedia = File('${dir.path}/.nomedia');
    if (!await nomedia.exists()) await nomedia.writeAsString('');
    return dir;
  }

  Future<Directory> get fakeVaultDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_kFakeVaultDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    final nomedia = File('${dir.path}/.nomedia');
    if (!await nomedia.exists()) await nomedia.writeAsString('');
    return dir;
  }

  // ─── PIN Management ──────────────────────────────────────────────────────

  Future<bool> get hasPinSet async {
    final v = await _storage.read(key: _kPinSet);
    return v == 'true';
  }

  String _hashPin(String pin, {bool isFake = false}) {
    final salt = isFake ? 'saveit_fake_vault_salt' : 'saveit_vault_salt';
    final bytes = utf8.encode(pin + salt);
    return sha256.convert(bytes).toString();
  }

  Future<void> setPin(String pin) async {
    await _storage.write(key: _kPinKey, value: _hashPin(pin));
    await _storage.write(key: _kPinSet, value: 'true');
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _kPinKey);
    return stored == _hashPin(pin);
  }

  // ─── Fake PIN Management ────────────────────────────────────────────────

  Future<bool> get isFakePinEnabled async {
    final v = await _storage.read(key: _kFakePinSet);
    return v == 'true';
  }

  Future<void> setFakePin(String pin) async {
    final hash = _hashPin(pin, isFake: true);
    await _storage.write(key: _kFakePinKey, value: hash);
    await _storage.write(key: _kFakePinSet, value: 'true');
    final dir = await fakeVaultDir;
    await dir.create(recursive: true);
  }

  Future<void> disableFakePin() async {
    await _storage.delete(key: _kFakePinKey);
    await _storage.delete(key: _kFakePinSet);
    final dir = await fakeVaultDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<bool> verifyFakePin(String pin) async {
    final stored = await _storage.read(key: _kFakePinKey);
    if (stored == null) return false;
    return stored == _hashPin(pin, isFake: true);
  }

  // ─── File Operations ─────────────────────────────────────────────────────

  String _safeName(String sourcePath) {
    final raw = sourcePath.split('/').last;
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return cleaned.isEmpty
        ? 'media_${DateTime.now().millisecondsSinceEpoch}'
        : cleaned;
  }

  String _uniqueName(String sourcePath) {
    final name = _safeName(sourcePath);
    final dot = name.lastIndexOf('.');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (dot <= 0) return '${name}_$stamp';
    return '${name.substring(0, dot)}_$stamp${name.substring(dot)}';
  }

  Future<List<FileSystemEntity>> getVaultFiles() async {
    final dir = await vaultDir;
    final files = await dir.list().toList();
    return files
        .where((f) => f is File && !f.path.endsWith('.nomedia'))
        .toList()
      ..sort((a, b) => File(b.path)
          .lastModifiedSync()
          .compareTo(File(a.path).lastModifiedSync()));
  }

  Future<List<FileSystemEntity>> getFakeVaultFiles() async {
    final dir = await fakeVaultDir;
    final files = await dir.list().toList();
    return files
        .where((f) => f is File && !f.path.endsWith('.nomedia'))
        .toList()
      ..sort((a, b) => File(b.path)
          .lastModifiedSync()
          .compareTo(File(a.path).lastModifiedSync()));
  }

  /// Move file to vault - ORIGINAL IS DELETED
  Future<File> moveToVault(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists())
      throw 'The selected media is no longer available.';
    final dir = await vaultDir;
    final dest = File('${dir.path}/${_uniqueName(sourcePath)}');
    await source.copy(dest.path);
    // Delete original
    try {
      await source.delete();
    } catch (e) {
      try {
        source.deleteSync();
      } catch (_) {}
    }
    return dest;
  }

  /// Copy to vault (keeps original)
  Future<File> copyToVault(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists())
      throw 'The selected media is no longer available.';
    final dir = await vaultDir;
    final dest = File('${dir.path}/${_uniqueName(sourcePath)}');
    await source.copy(dest.path);
    return dest;
  }

  Future<void> removeFromVault(String vaultPath) async {
    final file = File(vaultPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<String> exportFromVault(String vaultPath) async {
    final source = File(vaultPath);
    if (!await source.exists()) throw 'The vault file is no longer available.';
    final name = _safeName(vaultPath);
    final ext = name.split('.').last.toLowerCase();
    final isVideo = ['mp4', 'webm', 'mov', 'mkv', '3gp', 'avi'].contains(ext);
    final folder = isVideo ? 'Videos' : 'Pictures';
    final destDir = Directory('/storage/emulated/0/$folder/ClipVaults');
    await destDir.create(recursive: true);
    final dest = File('${destDir.path}/$name');
    await source.copy(dest.path);
    return dest.path;
  }

  Future<int> getVaultSizeBytes() async {
    int total = 0;
    for (final f in await getVaultFiles()) {
      try {
        total += await (f as File).length();
      } catch (_) {}
    }
    return total;
  }

  Future<int> getFileCount() async {
    return (await getVaultFiles()).length;
  }
}