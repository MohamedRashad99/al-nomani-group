import '../session.dart';

/// Firestore documents use last-write-wins via merge. This stub does not
/// introduce a second conflict store.
class ConflictResolutionService {
  Future<List<Object>> openConflicts() async => const [];
  Stream<List<Object>> watchOpenConflicts() => Stream.value(const []);
  Future<void> acceptServer(AppSession session, String conflictId) async {}
  Future<void> keepLocal(AppSession session, String conflictId) async {}
}
