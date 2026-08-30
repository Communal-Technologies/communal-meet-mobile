import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

class PendingSend {
  const PendingSend({
    required this.clientMsgId,
    required this.conversationId,
    required this.body,
    required this.replyToId,
    required this.createdAt,
    required this.failed,
  });

  final String clientMsgId;
  final String conversationId;
  final String body;
  final String replyToId;
  final DateTime createdAt;
  final bool failed;

  Message asMessage(String senderProfileId, String senderName) => Message(
    id: 'local:$clientMsgId',
    conversationId: conversationId,
    seq: 0,
    senderProfileId: senderProfileId,
    senderName: senderName,
    kind: 'text',
    body: body,
    replyToId: replyToId,
    clientMsgId: clientMsgId,
    createdAt: createdAt,
    sendState: failed ? SendState.failed : SendState.queued,
  );
}

class LocalStore {
  Database? _db;

  static const int _keepPerConversation = 200;

  Future<void> open() async {
    if (_db != null) return;
    _db = await openDatabase(
      '${await getDatabasesPath()}/meet.db',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            ordering INTEGER NOT NULL DEFAULT 0,
            json TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            conversation_id TEXT NOT NULL,
            id TEXT NOT NULL,
            seq INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (conversation_id, id)
          )
        ''');
        await db.execute(
          'CREATE INDEX messages_seq ON messages (conversation_id, seq)',
        );
        await db.execute('''
          CREATE TABLE outbox (
            client_msg_id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            body TEXT NOT NULL,
            reply_to_id TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            failed INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  Database get _require {
    final db = _db;
    if (db == null) throw StateError('LocalStore.open() was not awaited');
    return db;
  }

  Future<void> putConversations(List<Conversation> list) async {
    final batch = _require.batch();
    batch.delete('conversations');
    for (var i = 0; i < list.length; i++) {
      batch.insert('conversations', {
        'id': list[i].id,
        'ordering': i,
        'json': jsonEncode(list[i].toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Conversation>> conversations() async {
    final rows = await _require.query('conversations', orderBy: 'ordering ASC');
    return rows
        .map(
          (r) => Conversation.fromJson(
            jsonDecode(r['json'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> putMessages(String conversationId, List<Message> list) async {
    if (list.isEmpty) return;
    final batch = _require.batch();
    for (final m in list) {
      batch.insert('messages', {
        'conversation_id': conversationId,
        'id': m.id,
        'seq': m.seq,
        'json': jsonEncode(m.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _require.rawDelete(
      '''DELETE FROM messages WHERE conversation_id = ? AND id NOT IN
         (SELECT id FROM messages WHERE conversation_id = ?
            ORDER BY seq DESC LIMIT ?)''',
      [conversationId, conversationId, _keepPerConversation],
    );
  }

  Future<List<Message>> messages(String conversationId) async {
    final rows = await _require.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'seq ASC',
    );
    return rows
        .map(
          (r) => Message.fromJson(
            jsonDecode(r['json'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<int> maxSeq(String conversationId) async {
    final rows = await _require.rawQuery(
      'SELECT MAX(seq) AS s FROM messages WHERE conversation_id = ?',
      [conversationId],
    );
    final value = rows.isEmpty ? null : rows.first['s'];
    return value == null ? 0 : (value as num).toInt();
  }

  Future<void> enqueue(PendingSend send) async {
    await _require.insert('outbox', {
      'client_msg_id': send.clientMsgId,
      'conversation_id': send.conversationId,
      'body': send.body,
      'reply_to_id': send.replyToId,
      'created_at': send.createdAt.toIso8601String(),
      'failed': send.failed ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markFailed(String clientMsgId, bool failed) async {
    await _require.update(
      'outbox',
      {'failed': failed ? 1 : 0},
      where: 'client_msg_id = ?',
      whereArgs: [clientMsgId],
    );
  }

  Future<void> dequeue(String clientMsgId) async {
    await _require.delete(
      'outbox',
      where: 'client_msg_id = ?',
      whereArgs: [clientMsgId],
    );
  }

  Future<List<PendingSend>> pending({String? conversationId}) async {
    final rows = await _require.query(
      'outbox',
      where: conversationId == null ? null : 'conversation_id = ?',
      whereArgs: conversationId == null ? null : [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (r) => PendingSend(
            clientMsgId: r['client_msg_id'] as String,
            conversationId: r['conversation_id'] as String,
            body: r['body'] as String,
            replyToId: (r['reply_to_id'] as String?) ?? '',
            createdAt:
                DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
            failed: (r['failed'] as int? ?? 0) == 1,
          ),
        )
        .toList();
  }

  Future<void> wipe() async {
    final batch = _require.batch();
    batch.delete('conversations');
    batch.delete('messages');
    batch.delete('outbox');
    await batch.commit(noResult: true);
  }
}
