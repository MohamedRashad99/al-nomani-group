import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/firebase/firebase_bootstrap.dart';
import '../local/app_database.dart';
import 'firebase_actor.dart';

class FirebaseSyncService {
  static const companyId = 'al_nomani';

  static const sectionByEntity = <String, String>{
    'sale': 'sales',
    'saleItem': 'sale_items',
    'inventoryMovement': 'inventory',
    'customer': 'customers',
    'product': 'products',
    'category': 'categories',
    'customerAccount': 'accounts',
    'customerAccountTransaction': 'account_transactions',
    'collection': 'collections',
    'user': 'users',
    'role': 'roles',
    'auditLog': 'audit_logs',
    'setting': 'settings',
  };

  DocumentReference<Map<String, dynamic>> get _company =>
      FirebaseFirestore.instance.collection('companies').doc(companyId);

  CollectionReference<Map<String, dynamic>> _section(String entityType) {
    final name = sectionByEntity[entityType] ?? 'other';
    return _company.collection(name);
  }

  Future<bool> ensureReady() => FirebaseBootstrap.ensure();

  Future<List<Map<String, dynamic>>> pushItems(
    List<SyncQueueData> items,
    String deviceId, {
    FirebaseActor actor = FirebaseActor.empty,
  }) async {
    if (!await ensureReady()) {
      throw StateError(
        FirebaseBootstrap.lastError ?? 'Firebase غير جاهز للمزامنة.',
      );
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _company.set({
      'name': 'مجموعة النعماني',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final results = <Map<String, dynamic>>[];
    const chunkSize = 200;
    for (var offset = 0; offset < items.length; offset += chunkSize) {
      final chunk = items.sublist(
        offset,
        offset + chunkSize > items.length ? items.length : offset + chunkSize,
      );
      final batch = FirebaseFirestore.instance.batch();
      for (final item in chunk) {
        final payload = jsonDecode(item.payload) as Map<String, dynamic>;
        final version = (payload['version'] as num?)?.toInt() ?? 1;
        final section = sectionByEntity[item.entityType] ?? 'other';
        final data = <String, dynamic>{
          ..._sanitizeMap(payload),
          ...actor.toFields(),
          'entityType': item.entityType,
          'entityId': item.entityId,
          'operationId': item.operationId,
          'operation': item.operation,
          'section': section,
          'version': version < 1 ? 1 : version,
          'deviceId': deviceId,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        };
        batch.set(_section(item.entityType).doc(item.entityId), data);
        batch.set(_company.collection('transactions').doc(item.operationId), {
          ...data,
          'section': section,
        });
      }
      await batch.commit();
      for (final item in chunk) {
        results.add({'operation_id': item.operationId, 'status': 'accepted'});
      }
    }
    if (actor.isKnown) {
      await _writeUserProfile(actor, deviceId, uid);
    }
    return results;
  }

  Future<void> recordAuthenticatedSession({
    required FirebaseActor actor,
    required String deviceId,
    required String sessionId,
  }) async {
    if (!await ensureReady() || !actor.isKnown) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _writeUserProfile(actor, deviceId, uid);
    await _company.collection('sessions').doc(sessionId).set({
      ...actor.toFields(),
      'operationId': sessionId,
      'operation': 'create',
      'version': 1,
      'deviceId': deviceId,
      'entityType': 'session',
      'entityId': sessionId,
      'section': 'sessions',
      'loggedInAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }

  Future<void> _writeUserProfile(
    FirebaseActor actor,
    String deviceId,
    String uid,
  ) async {
    await _company.collection('users').doc(actor.userId).set({
      ...actor.toFields(),
      'id': actor.userId,
      'username': actor.username,
      'display_name': actor.displayName,
      'role_id': actor.roleId,
      'operationId': 'user-profile-${actor.userId}',
      'operation': 'update',
      'version': 1,
      'deviceId': deviceId,
      'entityType': 'user',
      'entityId': actor.userId,
      'section': 'users',
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    }, SetOptions(merge: true));
  }

  Future<({int records, bool ok, String? error})> health() async {
    if (!await ensureReady()) {
      return (records: 0, ok: false, error: FirebaseBootstrap.lastError);
    }
    try {
      var total = 0;
      for (final name in {...sectionByEntity.values, 'transactions', 'other'}) {
        final count = await _company.collection(name).count().get();
        total += count.count ?? 0;
      }
      return (records: total, ok: true, error: null);
    } catch (error) {
      return (records: 0, ok: false, error: error.toString());
    }
  }

  Future<String> uploadBytes({
    required String name,
    required List<int> bytes,
    required String contentType,
    FirebaseActor actor = FirebaseActor.empty,
  }) async {
    if (!await ensureReady()) {
      throw StateError(FirebaseBootstrap.lastError ?? 'Firebase غير جاهز.');
    }
    final path = 'companies/$companyId/uploads/$name';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: contentType),
    );
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _company.collection('files').doc(name.replaceAll('/', '_')).set({
      ...actor.toFields(),
      'name': name,
      'contentType': contentType,
      'size': bytes.length,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
    return ref.getDownloadURL();
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> source) {
    return {
      for (final entry in source.entries)
        if (entry.value != null &&
            entry.key != 'password' &&
            entry.key != 'password_hash' &&
            entry.key != 'passwordHash')
          entry.key: _sanitizeValue(entry.value),
    };
  }

  Object? _sanitizeValue(Object? value) {
    if (value == null || value is bool || value is String) return value;
    if (value is num) {
      if (value.isNaN || value.isInfinite) return 0;
      return value;
    }
    if (value is Map) {
      return _sanitizeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return [
        for (final item in value)
          if (item is List)
            {'items': _sanitizeValue(item)}
          else
            _sanitizeValue(item),
      ];
    }
    return value.toString();
  }
}
