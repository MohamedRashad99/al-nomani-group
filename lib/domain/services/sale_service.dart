import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../models/sale_draft.dart';
import '../session.dart';
import 'account_service.dart';
import 'audit_service.dart';
import 'inventory_service.dart';

class SaleResult {
  final String saleId;
  final String saleNumber;
  final Money subtotal;
  final Money paid;
  final Money remaining;

  const SaleResult({
    required this.saleId,
    required this.saleNumber,
    required this.subtotal,
    required this.paid,
    required this.remaining,
  });
}

class SaleService {
  SaleService({
    required AppDatabase db,
    required MetadataStore metadata,
    required SyncQueueRepository queue,
    required AuditService audit,
    required InventoryService inventory,
    required AccountService accounts,
  }) : _db = db,
       _metadata = metadata,
       _queue = queue,
       _audit = audit,
       _inventory = inventory,
       _accounts = accounts;

  final AppDatabase _db;
  final MetadataStore _metadata;
  final SyncQueueRepository _queue;
  final AuditService _audit;
  final InventoryService _inventory;
  final AccountService _accounts;

  Future<SaleResult> create(AppSession session, SaleDraft draft) async {
    if (!session.can(AppPermission.salesCreate)) {
      throw const PermissionException();
    }
    if (draft.lines.isEmpty) {
      throw const ValidationException('أضف منتجاً واحداً على الأقل.');
    }
    if (draft.paidAmount.isNegative) {
      throw const ValidationException('المبلغ المدفوع غير صالح.');
    }
    if (draft.paidAmount > draft.subtotal) {
      throw const ValidationException('المبلغ المدفوع أكبر من الإجمالي.');
    }

    return _db.transaction(() async {
      final now = DateTime.now().toUtc();
      final deviceId = await _metadata.deviceId();
      final saleId = newId();
      final saleNumber = await _nextSaleNumber();
      final remaining = draft.remaining;

      await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              customerId: draft.customerId,
              saleNumber: saleNumber,
              subtotal: draft.subtotal.toStorage(),
              paidAmount: draft.paidAmount.toStorage(),
              remainingAmount: remaining.toStorage(),
              notes: Value(draft.notes),
              soldAt: now,
              createdBy: session.userId,
              deviceId: Value(deviceId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final itemPayloads = <Map<String, dynamic>>[];
      for (final line in draft.lines) {
        if (!line.quantity.isPositive) {
          throw const ValidationException('الكمية غير صالحة.');
        }
        final itemId = newId();
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                id: itemId,
                saleId: saleId,
                productId: line.productId,
                quantity: line.quantity.toStorage(),
                unit: line.unit,
                unitPrice: line.unitPrice.toStorage(),
                lineTotal: line.lineTotal.toStorage(),
                deviceId: Value(deviceId),
                createdAt: now,
              ),
            );
        itemPayloads.add({
          'id': itemId,
          'sale_id': saleId,
          'product_id': line.productId,
          'quantity': line.quantity.toStorage(),
          'unit': line.unit,
          'unit_price': line.unitPrice.toStorage(),
          'line_total': line.lineTotal.toStorage(),
        });
        await _inventory.applyInsideTransaction(
          session: session,
          productId: line.productId,
          quantity: line.quantity,
          type: 'sale',
          referenceType: 'sale',
          referenceId: saleId,
          enqueue: true,
        );
      }

      if (!draft.subtotal.isZero) {
        await _accounts.post(
          customerId: draft.customerId,
          type: 'sale',
          amount: draft.subtotal,
          createdBy: session.userId,
          deviceId: deviceId,
          referenceType: 'sale',
          referenceId: saleId,
        );
      }
      if (draft.paidAmount.isPositive) {
        await _accounts.post(
          customerId: draft.customerId,
          type: 'payment',
          amount: draft.paidAmount,
          createdBy: session.userId,
          deviceId: deviceId,
          referenceType: 'sale_payment',
          referenceId: saleId,
        );
      }

      final payload = {
        'id': saleId,
        'customer_id': draft.customerId,
        'sale_number': saleNumber,
        'subtotal': draft.subtotal.toStorage(),
        'paid_amount': draft.paidAmount.toStorage(),
        'remaining_amount': remaining.toStorage(),
        'notes': draft.notes,
        'sold_at': now.toIso8601String(),
        'created_by': session.userId,
        'device_id': deviceId,
        'items': itemPayloads,
        'version': 1,
      };

      await _audit.write(
        userId: session.userId,
        deviceId: deviceId,
        action: 'sale.create',
        entityType: 'sale',
        entityId: saleId,
        newValue: payload,
      );
      await _queue.enqueue(
        entityType: SyncEntityType.sale,
        entityId: saleId,
        operation: SyncOperationType.create,
        payload: payload,
        operationId: saleId,
      );

      return SaleResult(
        saleId: saleId,
        saleNumber: saleNumber,
        subtotal: draft.subtotal,
        paid: draft.paidAmount,
        remaining: remaining,
      );
    });
  }

  Future<void> cancel(AppSession session, String saleId, String reason) async {
    if (!session.can(AppPermission.salesCancel)) {
      throw const PermissionException();
    }
    await _db.transaction(() async {
      final sale = await (_db.select(
        _db.sales,
      )..where((t) => t.id.equals(saleId))).getSingleOrNull();
      if (sale == null || sale.isDeleted) {
        throw const ValidationException('الفاتورة غير موجودة.');
      }
      if (sale.status == 'cancelled') {
        throw const ValidationException('الفاتورة ملغاة مسبقاً.');
      }
      final now = DateTime.now().toUtc();
      final deviceId = await _metadata.deviceId();
      await (_db.update(_db.sales)..where((t) => t.id.equals(saleId))).write(
        SalesCompanion(
          status: const Value('cancelled'),
          cancelledAt: Value(now),
          cancelledBy: Value(session.userId),
          cancelReason: Value(reason),
          version: Value(sale.version + 1),
          updatedAt: Value(now),
          deviceId: Value(deviceId),
        ),
      );
      final items = await (_db.select(
        _db.saleItems,
      )..where((t) => t.saleId.equals(saleId))).get();
      for (final item in items) {
        await _inventory.applyInsideTransaction(
          session: session,
          productId: item.productId,
          quantity: Quantity.parse(item.quantity),
          type: 'sale_cancel',
          referenceType: 'sale_cancel',
          referenceId: saleId,
        );
      }
      await _accounts.post(
        customerId: sale.customerId,
        type: 'sale_cancel',
        amount: Money.parse(sale.subtotal),
        createdBy: session.userId,
        deviceId: deviceId,
        referenceType: 'sale_cancel',
        referenceId: saleId,
      );
      if (Money.parse(sale.paidAmount).isPositive) {
        await _accounts.post(
          customerId: sale.customerId,
          type: 'payment_cancel',
          amount: Money.parse(sale.paidAmount),
          createdBy: session.userId,
          deviceId: deviceId,
          referenceType: 'sale_cancel',
          referenceId: saleId,
        );
      }
      await _audit.write(
        userId: session.userId,
        deviceId: deviceId,
        action: 'sale.cancel',
        entityType: 'sale',
        entityId: saleId,
        oldValue: {'status': sale.status},
        newValue: {'status': 'cancelled', 'reason': reason},
      );
      await _queue.enqueue(
        entityType: SyncEntityType.sale,
        entityId: saleId,
        operation: SyncOperationType.cancel,
        payload: {
          'id': saleId,
          'status': 'cancelled',
          'reason': reason,
          'version': sale.version + 1,
        },
        operationId: newId(),
      );
    });
  }

  Future<String> _nextSaleNumber() async {
    final count = await _db.select(_db.sales).get();
    return 'S-${(count.length + 1).toString().padLeft(6, '0')}';
  }
}
