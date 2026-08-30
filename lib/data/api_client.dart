import 'dart:async';

import 'package:dio/dio.dart';

import '../core/config.dart';
import '../core/reachability.dart';
import 'session_store.dart';

/// Why a request came back with nothing useful, in the three shapes a member can do
/// something about.
///
/// The distinction the app used to be missing is the middle one. A request that gets no
/// response says only that it did not arrive, and that happens both when the phone has
/// no network and when the network it has does not carry us — so "you are offline" was
/// being shown to people with four bars of signal, sending them to fix a phone that was
/// not broken. The second case is ours, and the copy has to say so.
enum Trouble {
  /// It reached us and we answered badly, or not usefully.
  failed,

  /// The phone has a network and it did not reach Communal.
  unreachable,

  /// The phone reports no wifi and no mobile data. The only case in which "you are
  /// offline" is a true sentence.
  offline,
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.hasTransport = true});

  final int? statusCode;
  final String message;

  /// What the phone reported about its own network at the moment this failed. Only
  /// meaningful when [isOffline] — a 500 arrived, so plainly there was a network.
  final bool hasTransport;

  bool get isOffline => statusCode == null;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  Trouble get trouble => !isOffline
      ? Trouble.failed
      : hasTransport
      ? Trouble.unreachable
      : Trouble.offline;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required this.session,
    required this.onSessionLost,
    required this.reach,
  }) {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.requireBaseUrl(),
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json'},
        validateStatus: (code) => code != null && code < 500,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = session.token;
          if (token != null && token.isNotEmpty && options.extra['skipAuth'] != true) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.statusCode != 401 ||
              response.requestOptions.extra['retried'] == true ||
              response.requestOptions.extra['skipAuth'] == true) {
            handler.next(response);
            return;
          }
          final refreshed = await _refresh();
          if (!refreshed) {
            await onSessionLost();
            handler.next(response);
            return;
          }
          final options = response.requestOptions;
          options.extra = {...options.extra, 'retried': true};
          try {
            handler.resolve(await dio.fetch(options));
          } catch (_) {
            handler.next(response);
          }
        },
      ),
    );
  }

  late final Dio dio;
  final SessionStore session;
  final Future<void> Function() onSessionLost;
  final Reachability reach;

  Future<bool>? _inFlightRefresh;

  Future<bool> _refresh() {
    return _inFlightRefresh ??= _doRefresh().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refresh = session.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await dio.post(
        ApiPaths.refreshToken,
        data: {'refresh_token': refresh},
        options: Options(extra: {'skipAuth': true, 'retried': true}),
      );
      final body = _asMap(res.data);
      final token = body['token']?.toString() ?? '';
      if (res.statusCode != 200 || token.isEmpty) return false;
      await session.saveTokens(
        token: token,
        refreshToken: body['refresh_token']?.toString() ?? refresh,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return _send(() => dio.get(path, queryParameters: query));
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool skipAuth = false,
  }) async {
    return _send(
      () => dio.post(
        path,
        data: body ?? const {},
        options: Options(extra: {'skipAuth': skipAuth}),
      ),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      final res = await call();
      final body = _asMap(res.data);
      final code = res.statusCode ?? 0;
      if (code >= 200 && code < 300) return body;
      throw ApiException(code, _messageFor(code, body));
    } on DioException catch (e) {
      if (e.response != null) {
        final body = _asMap(e.response!.data);
        final code = e.response!.statusCode ?? 0;
        throw ApiException(code, _messageFor(code, body));
      }
      // Nothing came back at all. Which of the two that was is a question only the
      // phone can answer, so ask it here, while the failure is still in hand.
      final hasTransport = reach.hasTransport;
      throw ApiException(
        null,
        hasTransport
            ? 'You are connected to something, but it is not reaching Communal.'
            : 'Turn on mobile data or wifi.',
        hasTransport: hasTransport,
      );
    }
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    return const {};
  }

  static String _messageFor(int code, Map<String, dynamic> body) {
    final message = body['message']?.toString();
    if (message != null && message.isNotEmpty) return message;
    if (code >= 500) return 'Something went wrong on our side.';
    return 'Request failed ($code).';
  }
}
