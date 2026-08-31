import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';
import 'session_store.dart';

class SocketFrame {
  const SocketFrame(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  String str(String key) => data[key]?.toString() ?? '';
}

enum SocketStatus { idle, connecting, live, waiting }

class MeetSocket {
  MeetSocket({required this.session});

  final SessionStore session;

  final _frames = StreamController<SocketFrame>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  final _random = Random();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _heartbeat;
  int _attempt = 0;
  bool _wanted = false;
  SocketStatus _current = SocketStatus.idle;

  Stream<SocketFrame> get frames => _frames.stream;
  Stream<SocketStatus> get status => _status.stream;
  SocketStatus get currentStatus => _current;

  void start() {
    _wanted = true;
    if (_channel == null) _open();
  }

  void stop() {
    _wanted = false;
    _retry?.cancel();
    _teardown();
    _emit(SocketStatus.idle);
  }

  void retryNow() {
    if (!_wanted) return;
    _retry?.cancel();
    _attempt = 0;
    if (_channel == null) _open();
  }

  void sendTyping(String conversationId, bool typing) => _send('typing', {
    'conversation_id': conversationId,
    'typing': typing,
  });

  void sendRead(String conversationId, int seq) => _send('read', {
    'conversation_id': conversationId,
    'seq': seq,
  });

  Future<void> dispose() async {
    stop();
    await _frames.close();
    await _status.close();
  }

  void _emit(SocketStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  void _send(String type, Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': type, 'data': data}));
    } catch (_) {}
  }

  void _open() {
    final token = session.token;
    if (token == null || token.isEmpty) return;
    _emit(SocketStatus.connecting);
    try {
      final channel = WebSocketChannel.connect(
        ApiPaths.socket(AppConfig.requireBaseUrl(), token),
      );
      _channel = channel;
      // `ready` carries the same failure the stream does, and nobody awaits it — so a
      // refused connection is an unhandled exception per attempt, forever, at the retry
      // interval. It is answered by [_onClosed] below; this only stops it being reported
      // twice, the second time as a crash. A dead meetsvc filled a log with these.
      unawaited(channel.ready.catchError((Object _) {}));
      _sub = channel.stream.listen(
        _onData,
        onError: (_) => _onClosed(),
        onDone: _onClosed,
        cancelOnError: true,
      );
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(
        const Duration(seconds: 25),
        (_) => _send('ping', const {}),
      );
    } catch (_) {
      _onClosed();
    }
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return;
      decoded = parsed.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final type = decoded['type']?.toString() ?? '';
    if (type.isEmpty) return;
    if (type == 'ready') {
      _attempt = 0;
      _emit(SocketStatus.live);
      return;
    }
    if (type == 'pong') return;
    final data = (decoded['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (!_frames.isClosed) _frames.add(SocketFrame(type, data));
  }

  void _onClosed() {
    _teardown();
    if (!_wanted) {
      _emit(SocketStatus.idle);
      return;
    }
    _emit(SocketStatus.waiting);
    _attempt = min(_attempt + 1, 6);
    final base = 1000 * (1 << (_attempt - 1));
    final delay = min(base, 30000) + _random.nextInt(700);
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: delay), () {
      if (_wanted && _channel == null) _open();
    });
  }

  void _teardown() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _sub?.cancel();
    _sub = null;
    final channel = _channel;
    _channel = null;
    try {
      channel?.sink.close();
    } catch (_) {}
  }
}
