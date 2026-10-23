import 'package:communal_meet/core/format.dart';
import 'package:communal_meet/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('callDuration', () {
    test('pads the seconds so the clock does not jump width', () {
      expect(callDuration(0), '0:00');
      expect(callDuration(9), '0:09');
      expect(callDuration(70), '1:10');
    });

    test('grows an hours field only once there is one', () {
      expect(callDuration(3599), '59:59');
      expect(callDuration(3600), '1:00:00');
      expect(callDuration(3661), '1:01:01');
    });
  });

  group('CallRecord', () {
    final json = <String, dynamic>{
      'id': 'call-1',
      'caller_profile_id': 'p-caller',
      'caller_name': 'Daniel Michael',
      'callee_profile_id': 'p-callee',
      'callee_name': 'Ada Obi',
      'cooperative_id': 'Tco-8934',
      'video': true,
      'status': 'accepted',
      'started_at': '2026-10-23T10:00:00Z',
      'answered_at': '2026-10-23T10:00:04Z',
      'ended_at': '2026-10-23T10:03:04Z',
    };

    test('reads the other party from whichever end is asking', () {
      final call = CallRecord.fromJson(json);
      expect(call.otherName('p-caller'), 'Ada Obi');
      expect(call.otherName('p-callee'), 'Daniel Michael');
      expect(call.otherProfileId('p-caller'), 'p-callee');
      expect(call.placedBy('p-caller'), isTrue);
      expect(call.placedBy('p-callee'), isFalse);
    });

    test('an unanswered call is distinguishable from a short one', () {
      expect(CallRecord.fromJson(json).wasAnswered, isTrue);
      final missed = CallRecord.fromJson({
        ...json,
        'status': 'missed',
        'answered_at': null,
      });
      expect(missed.wasAnswered, isFalse);
      expect(missed.isLive, isFalse);
    });

    test('a ringing call is live, a finished one is not', () {
      for (final status in ['ringing', 'accepted']) {
        expect(
          CallRecord.fromJson({...json, 'status': status}).isLive,
          isTrue,
          reason: status,
        );
      }
      for (final status in ['declined', 'missed', 'ended']) {
        expect(
          CallRecord.fromJson({...json, 'status': status}).isLive,
          isFalse,
          reason: status,
        );
      }
    });

    test('survives a payload with nothing in it', () {
      final empty = CallRecord.fromJson(const {});
      expect(empty.id, '');
      expect(empty.video, isFalse);
      expect(empty.startedAt, isNull);
    });
  });

  group('CallTicket', () {
    test('carries the room details and the ring window', () {
      final ticket = CallTicket.fromJson(<String, dynamic>{
        'call': {'id': 'call-1', 'status': 'ringing'},
        'token': 'jwt',
        'livekit_url': 'wss://sfu.example',
        'room': 'biz--call-abc',
        'identity': 'biz--p-caller',
        'ice_servers': [
          {
            'urls': ['turn:relay.example:3478'],
            'username': 'u',
            'credential': 'c',
          },
        ],
        'ring_seconds': 45,
      });
      expect(ticket.call.id, 'call-1');
      expect(ticket.token, 'jwt');
      expect(ticket.room, 'biz--call-abc');
      expect(ticket.ringSeconds, 45);
      expect(ticket.iceServers.single.urls, ['turn:relay.example:3478']);
    });

    test('an absent ice list is empty, never null', () {
      final ticket = CallTicket.fromJson(const {'token': 'jwt'});
      expect(ticket.iceServers, isEmpty);
      expect(ticket.ringSeconds, 0);
    });
  });
}
