import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/models/purchase_draft.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/purchase_service.dart';
import '../../domain/services/supplier_service.dart';
import '../../features/app/app_alert_cubit.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/quantity_sheet.dart';
import '../../shared/widgets/searchable_select.dart';

abstract final class SupplierCycleSheets {
  static Future<Purchase?> pickOpenPurchase(
    BuildContext context,
    String supplierId, {
    required String title,
  }) async {
    final purchases = await sl<SupplierService>().purchases(supplierId);
    if (!context.mounted) return null;
    final open = [
      for (final purchase in purchases)
        if (purchase.status != 'cancelled' &&
            purchase.status != 'returned' &&
            Money.parse(purchase.remainingAmount).isPositive)
          purchase,
    ];
    if (open.isEmpty) {
      sl<AppAlertCubit>().warning(
        'لا توجد فواتير مفتوحة. أنشئ فاتورة أو تأكد أن المتبقي أكبر من صفر.',
      );
      return null;
    }
    Purchase? selected = open.first;
    return showDialog<Purchase>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(title),
          content: DropdownButtonFormField<Purchase>(
            initialValue: selected,
            items: [
              for (final purchase in open)
                DropdownMenuItem(
                  value: purchase,
                  child: Text(
                    '${purchase.purchaseNumber} • متبقي ${Money.parse(purchase.remainingAmount).toDisplay()}',
                  ),
                ),
            ],
            onChanged: (value) => setS(() => selected = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(S.back),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(ctx, selected),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> settleInvoice(
    BuildContext context,
    Supplier supplier,
  ) async {
    final purchase = await pickOpenPurchase(
      context,
      supplier.id,
      title: 'تسوية فاتورة',
    );
    if (purchase == null || !context.mounted) return;
    final remaining = Money.parse(purchase.remainingAmount);
    final amount = TextEditingController(text: remaining.toDisplay());
    final notes = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var saving = false;
        String? error;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تسوية ${purchase.purchaseNumber}'),
                Text('المتبقي: ${remaining.toDisplay()} ${Money.currencySymbol}'),
                AmountField(controller: amount, label: S.paidAmount),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: S.notes),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setS(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await sl<AppBusyCubit>().guard(() async {
                              await sl<PurchaseService>().settle(
                                session: context.read<AuthCubit>().state.session!,
                                purchaseId: purchase.id,
                                amount: Money.parse(amount.text),
                                notes: notes.text,
                              );
                              await sl<SyncEngine>().maybeSyncAfterLocalWrite();
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            sl<AppAlertCubit>().success('تم تسجيل التسوية.');
                          } catch (e) {
                            if (ctx.mounted) {
                              setS(() {
                                saving = false;
                                error = e.toString();
                              });
                            }
                          }
                        },
                  child: const Text('تسوية'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> editInvoice(
    BuildContext context,
    Supplier supplier,
  ) async {
    final purchases = await sl<SupplierService>().purchases(supplier.id);
    if (!context.mounted) return;
    final editable = [
      for (final purchase in purchases)
        if (purchase.status != 'cancelled' && purchase.status != 'returned')
          purchase,
    ];
    if (editable.isEmpty) {
      sl<AppAlertCubit>().warning(
        'لا توجد فاتورة قابلة للتعديل. الفواتير الملغاة أو المرتجعة تُصحح بقيد في الكشف.',
      );
      return;
    }
    Purchase selected = editable.first;
    final picked = await showDialog<Purchase>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل فاتورة'),
        content: DropdownButtonFormField<Purchase>(
          initialValue: selected,
          items: [
            for (final purchase in editable)
              DropdownMenuItem(
                value: purchase,
                child: Text(purchase.purchaseNumber),
              ),
          ],
          onChanged: (value) {
            if (value != null) selected = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(S.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected),
            child: const Text('تعديل البنود'),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final details = await sl<PurchaseService>().loadDetails(picked.id);
    if (details == null || !context.mounted) return;
    final lines = [
      for (final item in details.items)
        if (Quantity.parse(item.quantity).isPositive)
          PurchaseLineDraft(
            itemId: item.id,
            productId: item.productId,
            quantity: Quantity.parse(item.quantity),
            unit: item.unit,
            unitPrice: Money.parse(item.unitPrice),
          ),
    ];
    final products = <String, Product>{};
    for (final product in await sl<CatalogService>().searchProducts('')) {
      products[product.id] = product;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Money total() =>
              lines.fold(Money.zero(), (sum, line) => sum + line.lineTotal);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تعديل ${picked.purchaseNumber}',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const Text(
                    'التعديل يضيف قيود تعويض للمخزون والحساب دون تغيير أرقام الحركات القديمة.',
                  ),
                  StreamBuilder<List<Product>>(
                    stream: sl<CatalogService>().watchProducts(''),
                    builder: (context, snapshot) {
                      final items = snapshot.data ?? products.values.toList();
                      return SearchableSelectField<String>(
                        label: S.selectProduct,
                        value: null,
                        options: [
                          for (final product in items)
                            SearchableOption(
                              value: product.id,
                              label: product.name,
                            ),
                        ],
                        onChanged: (id) async {
                          Product? pickedProduct;
                          for (final product in items) {
                            if (product.id == id) pickedProduct = product;
                          }
                          if (pickedProduct == null) return;
                          final quantity = await showQuantitySheet(
                            context: context,
                            title: pickedProduct.name,
                          );
                          if (quantity == null) return;
                          setS(() {
                            products[pickedProduct!.id] = pickedProduct;
                            lines.add(
                              PurchaseLineDraft(
                                productId: pickedProduct.id,
                                quantity: quantity,
                                unit: pickedProduct.unit,
                                unitPrice: Money.parse(
                                  pickedProduct.purchasePrice,
                                ),
                              ),
                            );
                          });
                        },
                      );
                    },
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: lines.length,
                      itemBuilder: (_, index) {
                        final line = lines[index];
                        return ListTile(
                          title: Text(products[line.productId]?.name ?? 'منتج'),
                          subtitle: Text(
                            '${line.quantity.toDisplay()} × ${line.unitPrice.toDisplay()}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setS(() => lines.removeAt(index)),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الإجمالي الجديد'),
                      Text(total().toDisplay()),
                    ],
                  ),
                  FilledButton(
                    onPressed: lines.isEmpty
                        ? null
                        : () async {
                            try {
                              await sl<AppBusyCubit>().guard(() async {
                                await sl<PurchaseService>().adjustLines(
                                  session: context
                                      .read<AuthCubit>()
                                      .state
                                      .session!,
                                  purchaseId: picked.id,
                                  lines: List.of(lines),
                                );
                                await sl<SyncEngine>().maybeSyncAfterLocalWrite();
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              sl<AppAlertCubit>().success(
                                'تم تعديل الفاتورة وتحديث الرصيد.',
                              );
                            } catch (e) {
                              sl<AppAlertCubit>().error(e.toString());
                            }
                          },
                    child: const Text('حفظ التعديل'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> addCorrection(
    BuildContext context,
    Supplier supplier,
  ) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    var debit = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var saving = false;
        String? error;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('قيد تصحيح في كشف الحساب'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('مدين علينا')),
                    ButtonSegment(value: false, label: Text('دائن للمورد')),
                  ],
                  selected: {debit},
                  onSelectionChanged: (value) => setS(() => debit = value.first),
                ),
                AmountField(controller: amount, label: S.paidAmount),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'سبب التصحيح (إلزامي)',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setS(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await sl<AppBusyCubit>().guard(() async {
                              await sl<SupplierService>().postCorrection(
                                session: context
                                    .read<AuthCubit>()
                                    .state
                                    .session!,
                                supplierId: supplier.id,
                                debit: debit,
                                amount: Money.parse(amount.text),
                                reason: reason.text,
                              );
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            sl<AppAlertCubit>().success('تم حفظ قيد التصحيح.');
                          } catch (e) {
                            if (ctx.mounted) {
                              setS(() {
                                saving = false;
                                error = e.toString();
                              });
                            }
                          }
                        },
                  child: const Text(S.save),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
