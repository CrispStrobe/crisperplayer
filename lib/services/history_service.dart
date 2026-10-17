import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'db/app_database.dart';

class HistoryService {
  final AppDatabase db;
  HistoryService(this.db);

  Future<String> startSession({required String bookId, required Duration startPos, double speed = 1.0}) async {
    final id = const Uuid().v4();
    await db.insertHistory(ListeningHistoryCompanion.insert(
      id: id, bookId: bookId, startedAtMs: DateTime.now().millisecondsSinceEpoch,
      startMs: Value(startPos.inMilliseconds), speed: Value(speed),
    ));
    return id;
  }

  Future<void> endSession(String id, Duration endPos, Duration listened) async {
    await db.updateHistoryEnd(id, DateTime.now().millisecondsSinceEpoch, endPos.inMilliseconds, listened.inMilliseconds);
  }

  Stream<List<ListeningHistoryData>> watchAll() => db.watchHistory();
  Future<List<ListeningHistoryData>> recent({int limit = 200}) => db.recentHistory(limit: limit);
  Future<List<ListeningHistoryData>> forBook(String bookId) => db.historyFor(bookId);
}
