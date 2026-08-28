import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
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

class SaleListEntry {
  const SaleListEntry({
    required this.sale,
    required this.customerName,
    required this.itemCount,
  });

  final Sale sale;
  final String customerName;
  final int itemCount;

  String get paymentType {
    final total = Money.parse(sale.subtotal);
    final paid = Money.parse(sale.paidAmount);
    if (paid.isZero) return 'credit';
    if (paid >= total) return 'cash';
    return 'partial';
  }
}

class SaleDetails {
  const SaleDetails({
    required this.sale,
    this.customer,
    required this.items,
    required this.productNames,
  });

  final Sale sale;
  final Customer? customer;
  final List<SaleItem> items;
  final Map<String, String> productNames;
}

class SaleService {
  SaleService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
    required InventoryService inventory,
    required AccountService accounts,
  }) : _store = store,
       _devices = devices,
       _audit = audit,
       _inventory = inventory,
       _accounts = accounts;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AuditService _audit;
  final InventoryService _inventory;
  final AccountService _accounts;

  Stream<List<SaleListEntry>> watchEntries() async* {
    yield await listEntries();
    await for (final _ in _store.watchChanges()) {
      yield await listEntries();
    }
  }

  Future<List<SaleListEntry>> listEntries() async {
    final salesFuture = _store.listSales();
    final customersFuture = _store.listCustomers();
    final itemsFuture = _store.listSaleItems();
    final sales = await salesFuture;
    final customers = {
      for (final customer in await customersFuture) customer.id: customer.name,
    };
    final items = await itemsFuture;
    final counts = <String, int>{};
    for (final item in items) {
      counts.update(item.saleId, (value) => value + 1, ifAbsent: () => 1);
    }
    return [
      for (final sale in sales)
        if (!sale.isDeleted)
          SaleListEntry(
            sale: sale,
            customerName: customers[sale.customerId] ?? 'عميل غير متاح',
            itemCount: counts[sale.id] ?? 0,
          ),
    ];
  }

  Future<SaleDetails?> loadDetails(String saleId) async {
    final sale = await _store.getSale(saleId);
    if (sale == null) return null;
    final customerFuture = _store.getCustomer(sale.customerId);
    final itemsFuture = _store.listSaleItems(saleId: saleId);
    final productsFuture = _store.listProducts();
    final customer = await customerFuture;
    final items = await itemsFuture;
    final products = await productsFuture;
    return SaleDetails(
      sale: sale,
      customer: customer,
      items: items,
      productNames: {for (final product in products) product.id: product.name},
    );
  }

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

    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final saleId = newId();
    final saleNumber = await _nextSaleNumber();
    final remaining = draft.remaining;
    await _store.putSale(
      Sale(
        id: saleId,
        customerId: draft.customerId,
        saleNumber: saleNumber,
        subtotal: draft.subtotal.toStorage(),
        paidAmount: draft.paidAmount.toStorage(),
        remainingAmount: remaining.toStorage(),
        notes: draft.notes,
        soldAt: now,
        createdBy: session.userId,
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (final line in draft.lines) {
      if (!line.quantity.isPositive) {
        throw const ValidationException('الكمية غير صالحة.');
      }
      final itemId = newId();
      await _store.putSaleItem(
        SaleItem(
          id: itemId,
          saleId: saleId,
          productId: line.productId,
          quantity: line.quantity.toStorage(),
          unit: line.unit,
          unitPrice: line.unitPrice.toStorage(),
          lineTotal: line.lineTotal.toStorage(),
          deviceId: deviceId,
          createdAt: now,
        ),
      );
      await _inventory.apply(
        session: session,
        productId: line.productId,
        quantity: line.quantity,
        type: 'sale',
        referenceType: 'sale',
        referenceId: saleId,
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
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'sale.create',
      entityType: 'sale',
      entityId: saleId,
      newValue: {'id': saleId, 'sale_number': saleNumber},
    );
    return SaleResult(
      saleId: saleId,
      saleNumber: saleNumber,
      subtotal: draft.subtotal,
      paid: draft.paidAmount,
      remaining: remaining,
    );
  }

  Future<void> cancel(AppSession session, String saleId, String reason) async {
    if (!session.can(AppPermission.salesCancel)) {
      throw const PermissionException();
    }
    final sale = await _store.getSale(saleId);
    if (sale == null || sale.isDeleted) {
      throw const ValidationException('الفاتورة غير موجودة.');
    }
    if (sale.status == 'cancelled') {
      throw const ValidationException('الفاتورة ملغاة مسبقاً.');
    }
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final items = await _store.listSaleItems(saleId: saleId);
    for (final item in items) {
      await _inventory.apply(
        session: session,
        productId: item.productId,
        quantity: Quantity.parse(item.quantity),
        type: 'sale_cancel',
        referenceType: 'sale_cancel',
        referenceId: saleId,
      );
    }

    final remaining = Money.parse(sale.remainingAmount);
    final paid = Money.parse(sale.paidAmount);
    final subtotal = Money.parse(sale.subtotal);
    final account = await _accounts.requireAccount(sale.customerId);
    final current = Money.parse(account.cachedBalance);
    final netReverse = remaining.isNegative ? Money.zero() : remaining;
    if (current + (Money.zero() - netReverse) >= Money.zero()) {
      if (paid.isPositive) {
        await _accounts.post(
          customerId: sale.customerId,
          type: 'payment_cancel',
          amount: paid,
          createdBy: session.userId,
          deviceId: deviceId,
          referenceType: 'sale_cancel',
          referenceId: saleId,
        );
      }
      if (!subtotal.isZero) {
        await _accounts.post(
          customerId: sale.customerId,
          type: 'sale_cancel',
          amount: subtotal,
          createdBy: session.userId,
          deviceId: deviceId,
          referenceType: 'sale_cancel',
          referenceId: saleId,
        );
      }
    } else if (current.isPositive) {
      await _accounts.post(
        customerId: sale.customerId,
        type: 'sale_cancel',
        amount: current,
        createdBy: session.userId,
        deviceId: deviceId,
        referenceType: 'sale_cancel',
        referenceId: saleId,
      );
    }

    await _store.putSale(
      Sale(
        id: sale.id,
        customerId: sale.customerId,
        saleNumber: sale.saleNumber,
        status: 'cancelled',
        subtotal: sale.subtotal,
        paidAmount: sale.paidAmount,
        remainingAmount: Money.zero().toStorage(),
        notes: sale.notes,
        soldAt: sale.soldAt,
        createdBy: sale.createdBy,
        cancelledAt: now,
        cancelledBy: session.userId,
        cancelReason: reason,
        version: sale.version + 1,
        deviceId: deviceId,
        createdAt: sale.createdAt,
        updatedAt: now,
      ),
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'sale.cancel',
      entityType: 'sale',
      entityId: saleId,
      oldValue: {'status': sale.status},
      newValue: {'status': 'cancelled', 'reason': reason},
    );
  }

  Future<String> _nextSaleNumber() async {
    final count = (await _store.listSales()).length;
    return 'S-${(count + 1).toString().padLeft(6, '0')}';
  }
}
