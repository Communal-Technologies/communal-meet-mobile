import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class Session {
  const Session({
    required this.token,
    required this.refreshToken,
    required this.caller,
  });

  final String token;
  final String refreshToken;
  final Caller? caller;
}

class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kToken = 'meet.token';
  static const _kRefresh = 'meet.refresh_token';
  static const _kCaller = 'meet.caller';

  String? _token;
  String? _refresh;
  Caller? _caller;

  String? get token => _token;
  String? get refreshToken => _refresh;
  Caller? get caller => _caller;
  bool get hasSession => (_token ?? '').isNotEmpty;

  Future<void> load() async {
    _token = await _storage.read(key: _kToken);
    _refresh = await _storage.read(key: _kRefresh);
    final raw = await _storage.read(key: _kCaller);
    if (raw != null && raw.isNotEmpty) {
      try {
        _caller = Caller.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _caller = null;
      }
    }
  }

  Future<void> saveTokens({
    required String token,
    required String refreshToken,
  }) async {
    _token = token;
    _refresh = refreshToken;
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  Future<void> saveCaller(Caller caller) async {
    _caller = caller;
    await _storage.write(key: _kCaller, value: jsonEncode(caller.toJson()));
  }

  Future<void> clear() async {
    _token = null;
    _refresh = null;
    _caller = null;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kCaller);
  }
}
