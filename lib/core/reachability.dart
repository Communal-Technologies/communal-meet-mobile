import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether this phone has any way out at all.
///
/// It answers exactly one question, and it exists because the app could not tell two
/// very different failures apart. A request that comes back with no response says only
/// that it did not arrive — which is true both when the phone has no signal and when
/// the signal it has does not carry us. The first is the member's to fix; the second is
/// ours, and saying "you are offline" for it sends somebody to check a phone that is
/// working perfectly.
///
/// This is not a reachability test for Communal. The phone knows whether it has wifi or
/// mobile data and nothing more; whether *we* are up is answered by the request itself.
class Reachability {
  Reachability({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _changes = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Assumed true until the platform says otherwise. An unknown transport must never
  /// become "turn on your data": that is the one message a member cannot act on when it
  /// is wrong, and a plain "we could not reach Communal" is right either way.
  bool _hasTransport = true;
  bool get hasTransport => _hasTransport;

  /// Emits on each change, so a screen showing one of the two messages can switch to
  /// the other when the phone does.
  Stream<bool> get changes => _changes.stream;

  Future<void> start() async {
    try {
      _apply(await _connectivity.checkConnectivity());
      _sub = _connectivity.onConnectivityChanged.listen(
        _apply,
        onError: (_) {},
      );
    } catch (_) {
      // A platform channel that is not answering is not a phone without signal, so the
      // optimistic default stands and the copy stays on the safe sentence.
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final next = results.any((r) => r != ConnectivityResult.none);
    if (next == _hasTransport) return;
    _hasTransport = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _changes.close();
  }
}
