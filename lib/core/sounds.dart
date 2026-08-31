import 'package:audioplayers/audioplayers.dart';

/// The three sounds the app makes, and nothing else.
///
/// Each has its own player because two can overlap — a knock while somebody is
/// joining — and one player restarted mid-clip would cut the first off. They are
/// loaded on first use and kept, since a sound that arrives after the event it
/// describes is worse than no sound.
///
/// Nothing here throws. A phone with its media volume down, a route lost to a
/// disconnecting headset, an asset that failed to decode: none of that is worth a
/// visible error in the middle of a meeting.
class Sounds {
  Sounds._();

  static const _join = 'sounds/join.wav';
  static const _knock = 'sounds/knock.wav';
  static const _ringback = 'sounds/ringback.wav';

  static final Map<String, AudioPlayer> _players = {};

  /// Someone entered the meeting. Two ascending notes: arrival, resolved.
  static Future<void> join() => _play(_join);

  /// Someone is waiting to be let in. One note struck twice, unresolved, because
  /// a person is still standing there.
  static Future<void> knock() => _play(_knock);

  /// Your outgoing 1:1 call is ringing. Loops until it is answered or given up
  /// on — [stopRingback] ends it.
  static Future<void> ringback() =>
      _play(_ringback, mode: ReleaseMode.loop);

  static Future<void> stopRingback() async {
    try {
      await _players[_ringback]?.stop();
    } catch (_) {}
  }

  static Future<void> _play(
    String asset, {
    ReleaseMode mode = ReleaseMode.stop,
  }) async {
    try {
      final player = _players[asset] ??= AudioPlayer();
      await player.setReleaseMode(mode);
      await player.play(AssetSource(asset), volume: 0.7);
    } catch (_) {
      // A sound is a courtesy. Failing to make one is not an error to report.
    }
  }
}
