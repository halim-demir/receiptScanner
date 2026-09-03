import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [FlutterSecureStorage] for all *sensitive* values in the app, with
/// an added application-level AES-256-GCM encryption layer for the API key.
///
/// Two layers protect the key at rest:
///  1. **App-level (this class):** the key is encrypted with AES-256-GCM
///     using a random per-value IV before it's ever written to disk. The
///     plaintext key only ever exists in memory for the duration of a
///     single read/write call.
///  2. **OS-level (flutter_secure_storage):** the ciphertext + the AES
///     master key are both stored via Android's Keystore-backed
///     EncryptedSharedPreferences / iOS Keychain — themselves backed by
///     hardware-isolated keys (StrongBox/Secure Enclave where available)
///     that never leave the device and aren't extractable even with root
///     access on a properly configured device.
///
/// Honesty note: because the AES master key lives in the same secure store
/// as the ciphertext, this layer's main value is (a) guaranteeing the
/// plaintext key is never written to disk in any form, even transiently,
/// and (b) isolating the crypto so it isn't silently weakened by a future
/// storage-backend change — it is not a substitute for OS-level protection,
/// it supplements it.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _keyEncryptedApiKey = 'gemini_api_key_enc_v1';
  static const _keyMasterKey = 'aes_master_key_v1';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<enc.Key> _getOrCreateMasterKey() async {
    final existing = await _storage.read(key: _keyMasterKey);
    if (existing != null) {
      return enc.Key.fromBase64(existing);
    }
    final generated = enc.Key.fromSecureRandom(32); // 256-bit
    await _storage.write(key: _keyMasterKey, value: generated.base64);
    return generated;
  }

  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('API key must not be empty');
    }

    final key = await _getOrCreateMasterKey();
    final iv = enc.IV.fromSecureRandom(12); // 96-bit nonce, standard for GCM
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(trimmed, iv: iv);

    // Store as base64(iv) + '.' + base64(ciphertext+tag) so decryption
    // doesn't depend on a fixed IV length assumption.
    final payload = '${base64Encode(iv.bytes)}.${base64Encode(encrypted.bytes)}';
    await _storage.write(key: _keyEncryptedApiKey, value: payload);
  }

  Future<String?> getApiKey() async {
    final payload = await _storage.read(key: _keyEncryptedApiKey);
    if (payload == null) return null;

    final parts = payload.split('.');
    if (parts.length != 2) {
      // Corrupt/unrecognized payload — fail closed rather than guessing.
      return null;
    }

    try {
      final key = await _getOrCreateMasterKey();
      final iv = enc.IV(Uint8List.fromList(base64Decode(parts[0])));
      final cipherBytes = base64Decode(parts[1]);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      return encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<void> clearApiKey() => _storage.delete(key: _keyEncryptedApiKey);

  /// Full reset — also rotates the AES master key. Use with care: any
  /// previously-encrypted value becomes unreadable once the master key
  /// rotates, so this always clears the stored API key too.
  Future<void> rotateMasterKeyAndClear() async {
    await _storage.delete(key: _keyEncryptedApiKey);
    await _storage.delete(key: _keyMasterKey);
  }
}
