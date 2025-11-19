import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GatewayPin {
  static const _kKey = 'gateway_pin_hash_v1';
  static const _storage = FlutterSecureStorage();

  static const _pinFromDefine = String.fromEnvironment('GATEWAY_PIN');

  static Future<void> ensureInitialized() async {
    final existing = await _storage.read(key: _kKey);
    if (existing == null && _pinFromDefine.isNotEmpty) {
      await _storage.write(key: _kKey, value: _hash(_pinFromDefine));
    }
  }

  static Future<bool> verify(String pinAttempt) async {
    final savedHash = await _storage.read(key: _kKey);
    if (savedHash == null) return false;
    return savedHash == _hash(pinAttempt);
  }

  static String _hash(String v) => sha256.convert(utf8.encode('ga1::$v')).toString();

  static Future<void> setPin(String newPin) async {
    await _storage.write(key: _kKey, value: _hash(newPin));
  }
}