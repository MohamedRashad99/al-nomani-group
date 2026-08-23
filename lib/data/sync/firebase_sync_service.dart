import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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

  Future<int> hydrateLocal(AppDatabase db) async {
    if (!await ensureReady()) return 0;
    var written = 0;
    Future<int> section(String name, Future<int> Function() run) async {
      try {
        return await run();
      } catch (error) {
        debugPrint('Firebase hydrate $name failed: $error');
        return 0;
      }
    }

    written += await section('customers', () => _hydrateCustomers(db));
    written += await section('categories', () => _hydrateCategories(db));
    written += await section('products', () => _hydrateProducts(db));
    written += await section('sales', () => _hydrateSales(db));
    written += await section('sale_items', () => _hydrateSaleItems(db));
    written += await section('collections', () => _hydrateCollections(db));
    written += await section('accounts', () => _hydrateAccounts(db));
    written += await section('account_tx', () => _hydrateAccountTx(db));
    written += await section('inventory', () => _hydrateInventory(db));
    written += await section('users', () => _hydrateUsers(db));
    return written;
  }

  Future<List<Map<String, dynamic>>> _sectionDocs(String section) async {
    final snap = await _company.collection(section).get();
    return [
      for (final doc in snap.docs)
        if (doc.data()['operation'] != 'delete')
          {'id': doc.id, ...doc.data()},
    ];
  }

  String _text(Map<String, dynamic> data, List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = '$value';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return fallback;
  }

  DateTime _date(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) return value.toDate().toUtc();
      if (value is DateTime) return value.toUtc();
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toUtc();
      }
    }
    return DateTime.now().toUtc();
  }

  int _versionOf(Map<String, dynamic> data) {
    final value = data['version'];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 1;
  }

  Future<int> _hydrateCustomers(AppDatabase db) async {
    final docs = await _sectionDocs('customers');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      final now = DateTime.now().toUtc();
      await db
          .into(db.customers)
          .insertOnConflictUpdate(
            CustomersCompanion(
              id: Value(id),
              name: Value(_text(data, const ['name'], 'عميل')),
              phone: Value(_text(data, const ['phone'])),
              address: Value(_text(data, const ['address'])),
              area: Value(_text(data, const ['area'])),
              notes: Value(_text(data, const ['notes'])),
              isActive: Value(data['is_active'] != false && data['isActive'] != false),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
              updatedAt: Value(now),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateCategories(AppDatabase db) async {
    final docs = await _sectionDocs('categories');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      final now = DateTime.now().toUtc();
      await db
          .into(db.productCategories)
          .insertOnConflictUpdate(
            ProductCategoriesCompanion(
              id: Value(id),
              name: Value(_text(data, const ['name'], 'تصنيف')),
              description: Value(_text(data, const ['description'])),
              isActive: Value(data['is_active'] != false && data['isActive'] != false),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
              updatedAt: Value(now),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateProducts(AppDatabase db) async {
    final docs = await _sectionDocs('products');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      final sku = _text(data, const ['sku'], id);
      await _removeUniqueClash(
        findId: () async =>
            (await (db.select(db.products)
                  ..where((t) => t.sku.equals(sku)))
                .getSingleOrNull())
                ?.id,
        keepId: id,
        remove: (oldId) async {
          await (db.delete(db.products)..where((t) => t.id.equals(oldId))).go();
        },
      );
      final now = DateTime.now().toUtc();
      await db
          .into(db.products)
          .insertOnConflictUpdate(
            ProductsCompanion(
              id: Value(id),
              name: Value(_text(data, const ['name'], 'منتج')),
              sku: Value(sku),
              categoryId: Value(_text(data, const ['category_id', 'categoryId'])),
              brand: Value(_text(data, const ['brand'])),
              description: Value(_text(data, const ['description'])),
              purchasePrice: Value(_text(data, const ['purchase_price', 'purchasePrice'], '0')),
              sellingPrice: Value(_text(data, const ['selling_price', 'sellingPrice'], '0')),
              currentStock: Value(_text(data, const ['current_stock', 'currentStock'], '0')),
              minimumStock: Value(_text(data, const ['minimum_stock', 'minimumStock'], '0')),
              unit: Value(_text(data, const ['unit'], 'pcs')),
              customUnitLabel: Value(_text(data, const ['custom_unit_label', 'customUnitLabel'])),
              isActive: Value(data['is_active'] != false && data['isActive'] != false),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
              updatedAt: Value(now),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateSales(AppDatabase db) async {
    final docs = await _sectionDocs('sales');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      final saleNumber = _text(data, const ['sale_number', 'saleNumber'], id);
      await _removeUniqueClash(
        findId: () async =>
            (await (db.select(db.sales)
                  ..where((t) => t.saleNumber.equals(saleNumber)))
                .getSingleOrNull())
                ?.id,
        keepId: id,
        remove: (oldId) async {
          await (db.delete(
            db.saleItems,
          )..where((t) => t.saleId.equals(oldId))).go();
          await (db.delete(db.sales)..where((t) => t.id.equals(oldId))).go();
        },
      );
      final now = DateTime.now().toUtc();
      await db
          .into(db.sales)
          .insertOnConflictUpdate(
            SalesCompanion(
              id: Value(id),
              customerId: Value(_text(data, const ['customer_id', 'customerId'])),
              saleNumber: Value(saleNumber),
              status: Value(_text(data, const ['status'], 'completed')),
              subtotal: Value(_text(data, const ['subtotal'], '0')),
              paidAmount: Value(_text(data, const ['paid_amount', 'paidAmount'], '0')),
              remainingAmount: Value(
                _text(data, const ['remaining_amount', 'remainingAmount'], '0'),
              ),
              notes: Value(_text(data, const ['notes'])),
              soldAt: Value(_date(data, const ['sold_at', 'soldAt'])),
              createdBy: Value(_text(data, const ['created_by', 'createdBy'])),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
              updatedAt: Value(now),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateSaleItems(AppDatabase db) async {
    final docs = await _sectionDocs('sale_items');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      await db
          .into(db.saleItems)
          .insertOnConflictUpdate(
            SaleItemsCompanion(
              id: Value(id),
              saleId: Value(_text(data, const ['sale_id', 'saleId'])),
              productId: Value(_text(data, const ['product_id', 'productId'])),
              quantity: Value(_text(data, const ['quantity'], '0')),
              unit: Value(_text(data, const ['unit'], 'pcs')),
              unitPrice: Value(_text(data, const ['unit_price', 'unitPrice'], '0')),
              lineTotal: Value(_text(data, const ['line_total', 'lineTotal'], '0')),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateCollections(AppDatabase db) async {
    final docs = await _sectionDocs('collections');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      final now = DateTime.now().toUtc();
      await db
          .into(db.collections)
          .insertOnConflictUpdate(
            CollectionsCompanion(
              id: Value(id),
              customerId: Value(_text(data, const ['customer_id', 'customerId'])),
              amount: Value(_text(data, const ['amount'], '0')),
              paymentMethod: Value(
                _text(data, const ['payment_method', 'paymentMethod'], 'cash'),
              ),
              collectedAt: Value(_date(data, const ['collected_at', 'collectedAt'])),
              notes: Value(_text(data, const ['notes'])),
              createdBy: Value(_text(data, const ['created_by', 'createdBy'])),
              status: Value(_text(data, const ['status'], 'completed')),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
              updatedAt: Value(now),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateAccounts(AppDatabase db) async {
    final docs = await _sectionDocs('accounts');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      final customerId = _text(data, const ['customer_id', 'customerId']);
      if (customerId.isNotEmpty) {
        await _removeUniqueClash(
          findId: () async =>
              (await (db.select(db.customerAccounts)
                    ..where((t) => t.customerId.equals(customerId)))
                  .getSingleOrNull())
                  ?.id,
          keepId: id,
          remove: (oldId) async {
            await (db.delete(
              db.customerAccounts,
            )..where((t) => t.id.equals(oldId))).go();
          },
        );
      }
      final now = DateTime.now().toUtc();
      await db
          .into(db.customerAccounts)
          .insertOnConflictUpdate(
            CustomerAccountsCompanion(
              id: Value(id),
              customerId: Value(customerId),
              cachedBalance: Value(
                _text(data, const ['cached_balance', 'cachedBalance'], '0'),
              ),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
              updatedAt: Value(now),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateAccountTx(AppDatabase db) async {
    final docs = await _sectionDocs('account_transactions');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      await db
          .into(db.customerAccountTransactions)
          .insertOnConflictUpdate(
            CustomerAccountTransactionsCompanion(
              id: Value(id),
              accountId: Value(_text(data, const ['account_id', 'accountId'])),
              customerId: Value(_text(data, const ['customer_id', 'customerId'])),
              type: Value(_text(data, const ['type'], 'sale')),
              amount: Value(_text(data, const ['amount'], '0')),
              runningBalance: Value(
                _text(data, const ['running_balance', 'runningBalance'], '0'),
              ),
              referenceType: Value(
                _text(data, const ['reference_type', 'referenceType']),
              ),
              referenceId: Value(_text(data, const ['reference_id', 'referenceId'])),
              notes: Value(_text(data, const ['notes'])),
              createdBy: Value(_text(data, const ['created_by', 'createdBy'])),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateInventory(AppDatabase db) async {
    final docs = await _sectionDocs('inventory');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId']);
      if (id.isEmpty) continue;
      await db
          .into(db.inventoryMovements)
          .insertOnConflictUpdate(
            InventoryMovementsCompanion(
              id: Value(id),
              productId: Value(_text(data, const ['product_id', 'productId'])),
              type: Value(_text(data, const ['type'], 'adjustment')),
              quantity: Value(_text(data, const ['quantity'], '0')),
              unit: Value(_text(data, const ['unit'], 'pcs')),
              previousStock: Value(
                _text(data, const ['previous_stock', 'previousStock'], '0'),
              ),
              newStock: Value(_text(data, const ['new_stock', 'newStock'], '0')),
              referenceType: Value(_text(data, const ['reference_type', 'referenceType'])),
              referenceId: Value(_text(data, const ['reference_id', 'referenceId'])),
              notes: Value(_text(data, const ['notes'])),
              createdBy: Value(_text(data, const ['created_by', 'createdBy'])),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(_date(data, const ['created_at', 'createdAt'])),
            ),
          );
    }
    return docs.length;
  }

  Future<int> _hydrateUsers(AppDatabase db) async {
    final docs = await _sectionDocs('users');
    for (final data in docs) {
      final id = _text(data, const ['id', 'entityId', 'erpUserId']);
      if (id.isEmpty) continue;
      final username = _text(data, const ['username'], id);
      var existing = await (db.select(
        db.users,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      existing ??= await (db.select(
        db.users,
      )..where((t) => t.username.equals(username))).getSingleOrNull();
      final now = DateTime.now().toUtc();
      await db
          .into(db.users)
          .insertOnConflictUpdate(
            UsersCompanion(
              id: Value(existing?.id ?? id),
              username: Value(username),
              displayName: Value(
                _text(data, const [
                  'display_name',
                  'displayName',
                  'erpDisplayName',
                ], existing?.displayName ?? 'مستخدم'),
              ),
              passwordHash: Value(
                existing?.passwordHash ??
                    _text(data, const ['password_hash', 'passwordHash'], ''),
              ),
              roleId: Value(
                _text(data, const ['role_id', 'roleId', 'erpRole'], 'cashier'),
              ),
              isActive: Value(data['is_active'] != false && data['isActive'] != false),
              version: Value(_versionOf(data)),
              deviceId: Value(_text(data, const ['deviceId', 'device_id'])),
              createdAt: Value(
                existing?.createdAt ?? _date(data, const ['created_at', 'createdAt']),
              ),
              updatedAt: Value(now),
            ),
          );
    }
    return docs.length;
  }

  Future<void> _removeUniqueClash({
    required Future<String?> Function() findId,
    required String keepId,
    required Future<void> Function(String oldId) remove,
  }) async {
    final found = await findId();
    if (found == null || found == keepId) return;
    await remove(found);
  }
}
