import '../session.dart';

class ConflictResolutionService {
  Future<List<Object>> openConflicts() async => const [];
  Stream<List<Object>> watchOpenConflicts() => Stream.value(const []);
  Future<void> acceptServer(AppSession session, String conflictId) async {}
  Future<void> keepLocal(AppSession session, String conflictId) async {}
}
