import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../core/utils/egypt_phone.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/models/purchase_draft.dart';
import '../../domain/session.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/purchase_service.dart';
import '../../domain/services/supplier_service.dart';
import '../../features/app/app_alert_cubit.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/destructive_action_guard.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/quantity_sheet.dart';
import '../../shared/widgets/searchable_select.dart';
import 'supplier_statement_export.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key, this.openStatementFor});

  final String? openStatementFor;

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String _query = '';
  bool _openedDeepLink = false;

  @override
  void initState() {
    super.initState();
    final supplierId = widget.openStatementFor;
    if (supplierId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _openedDeepLink) return;
        _openedDeepLink = true;
        _openStatementById(supplierId);
      });
    }
  }

  Future<void> _openStatementById(String supplierId) async {
    final supplier = await sl<SupplierService>().get(supplierId);
    if (supplier == null || !mounted) return;
    await SupplierDashboardActions.showStatement(context, supplier);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.suppliers,
      child: Column(
        children: [
          FutureBuilder<SupplierPortfolioSummary>(
            future: sl<SupplierService>().portfolioSummary(),
            builder: (context, summarySnap) {
              final summary = summarySnap.data;
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: summary == null
                    ? const LinearProgressIndicator(minHeight: 2)
                    : _PortfolioKpis(summary: summary),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: S.search,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (session.can(AppPermission.suppliersCreate)) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _editSupplier(null),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة مورد'),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<SupplierListEntry>>(
              stream: sl<SupplierService>().watchEntries(_query),
              builder: (context, snap) {
                final entries = snap.data ?? const <SupplierListEntry>[];
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (entries.isEmpty) {
                  return const BrandedEmptyState(title: S.empty);
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 960) {
                      return _SupplierTable(
                        entries: entries,
                        session: session,
                        onEdit: _editSupplier,
                      );
                    }
                    return _SupplierCards(
                      entries: entries,
                      session: session,
                      onEdit: _editSupplier,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editSupplier(Supplier? supplier) async {
    final name = TextEditingController(text: supplier?.name ?? '');
    final phone = TextEditingController(text: supplier?.phone ?? '');
    final area = TextEditingController(text: supplier?.area ?? '');
    final address = TextEditingController(text: supplier?.address ?? '');
    final notes = TextEditingController(text: supplier?.notes ?? '');
    final goodsType = TextEditingController(text: supplier?.goodsType ?? '');
    String? linkedCustomerId = supplier?.linkedCustomerId;
    var isActive = supplier?.isActive ?? true;
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
            builder: (ctx, setS) => SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: S.supplierName),
                  ),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: S.phone),
                  ),
                  TextField(
                    controller: area,
                    decoration: const InputDecoration(labelText: S.area),
                  ),
                  TextField(
                    controller: address,
                    decoration: const InputDecoration(labelText: S.address),
                  ),
                  TextField(
                    controller: goodsType,
                    decoration: const InputDecoration(labelText: 'نوع البضاعة'),
                  ),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: S.notes),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('مورد نشط'),
                    value: isActive,
                    onChanged: (v) => setS(() => isActive = v),
                  ),
                  FutureBuilder<List<Customer>>(
                    future: sl<CatalogService>().searchCustomers(''),
                    builder: (context, snap) {
                      final customers = snap.data ?? const <Customer>[];
                      return SearchableSelectField<String?>(
                        label: 'ربط كعميل',
                        value: linkedCustomerId,
                        options: [
                          const SearchableOption(value: null, label: 'بدون ربط'),
                          for (final customer in customers)
                            SearchableOption(
                              value: customer.id,
                              label: customer.name,
                              subtitle: customer.phone,
                            ),
                        ],
                        onChanged: (v) => setS(() => linkedCustomerId = v),
                      );
                    },
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
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
                                await sl<SupplierService>().upsert(
                                  session: context.read<AuthCubit>().state.session!,
                                  id: supplier?.id,
                                  name: name.text,
                                  phone: phone.text,
                                  address: address.text,
                                  area: area.text,
                                  notes: notes.text,
                                  goodsType: goodsType.text,
                                  linkedCustomerId: linkedCustomerId,
                                  isActive: isActive,
                                );
                                await sl<SyncEngine>().maybeSyncAfterLocalWrite();
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (ctx.mounted) {
                                setS(() {
                                  saving = false;
                                  error = e.toString();
                                });
                              }
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(S.save),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PortfolioKpis extends StatelessWidget {
  const _PortfolioKpis({required this.summary});

  final SupplierPortfolioSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: 'المستحقات علينا',
            value: MoneyText(summary.totalOutstanding),
            color: AppColors.danger,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'المدفوعات',
            value: MoneyText(summary.totalPayments),
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'موردين نشطين',
            value: Text('${summary.activeSuppliers}'),
            color: AppColors.leaf,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final Widget value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            DefaultTextStyle(
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              child: value,
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierTable extends StatelessWidget {
  const _SupplierTable({
    required this.entries,
    required this.session,
    required this.onEdit,
  });

  final List<SupplierListEntry> entries;
  final AppSession session;
  final void Function(Supplier?) onEdit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('المورد')),
              DataColumn(label: Text('الهاتف')),
              DataColumn(label: Text('المنطقة')),
              DataColumn(label: Text('نوع البضاعة')),
              DataColumn(label: Text('الرصيد'), numeric: true),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text('إجراءات')),
            ],
            rows: [
              for (final entry in entries)
                DataRow(
                  cells: [
                    DataCell(Text(entry.supplier.name)),
                    DataCell(Text(entry.supplier.phone ?? '—')),
                    DataCell(Text(entry.supplier.area ?? '—')),
                    DataCell(Text(entry.supplier.goodsType.isEmpty ? '—' : entry.supplier.goodsType)),
                    DataCell(_BalanceText(balance: entry.totals.outstanding)),
                    DataCell(Text(entry.statusLabel)),
                    DataCell(_QuickActions(entry: entry, session: session, onEdit: onEdit)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierCards extends StatelessWidget {
  const _SupplierCards({
    required this.entries,
    required this.session,
    required this.onEdit,
  });

  final List<SupplierListEntry> entries;
  final AppSession session;
  final void Function(Supplier?) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final entry = entries[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.supplier.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('${entry.supplier.phone ?? ''} • ${entry.supplier.area ?? ''}'),
                        ],
                      ),
                    ),
                    _BalanceText(balance: entry.totals.outstanding),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${entry.statusLabel} • ${entry.supplier.goodsType.isEmpty ? '—' : entry.supplier.goodsType}'),
                const SizedBox(height: 8),
                _QuickActions(entry: entry, session: session, onEdit: onEdit),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BalanceText extends StatelessWidget {
  const _BalanceText({required this.balance});

  final Money balance;

  @override
  Widget build(BuildContext context) {
    final color = balance.isZero
        ? AppColors.green
        : balance.isNegative
        ? Colors.blue
        : AppColors.danger;
    return MoneyText(balance, style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.entry,
    required this.session,
    required this.onEdit,
  });

  final SupplierListEntry entry;
  final AppSession session;
  final void Function(Supplier?) onEdit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (session.can(AppPermission.purchasesCreate))
          TextButton.icon(
            onPressed: () => SupplierDashboardActions.showPurchase(context, entry.supplier),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('فاتورة'),
          ),
        if (session.can(AppPermission.purchasesCreate) ||
            session.can(AppPermission.suppliersUpdate))
          TextButton.icon(
            onPressed: () => SupplierDashboardActions.showPayment(context, entry.supplier),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('دفع'),
          ),
        if (session.can(AppPermission.purchasesCreate))
          TextButton.icon(
            onPressed: () => SupplierDashboardActions.showReturn(context, entry.supplier),
            icon: const Icon(Icons.undo_outlined, size: 18),
            label: const Text('مرتجع'),
          ),
        TextButton.icon(
          onPressed: () => SupplierDashboardActions.showStatement(context, entry.supplier),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: const Text('كشف حساب'),
        ),
        if (session.can(AppPermission.suppliersUpdate))
          IconButton(
            tooltip: S.edit,
            onPressed: () => onEdit(entry.supplier),
            icon: const Icon(Icons.edit_outlined),
          ),
        if (session.can(AppPermission.suppliersDelete))
          IconButton(
            tooltip: S.cancel,
            onPressed: () => SupplierDashboardActions.deleteSupplier(context, entry.supplier),
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
          ),
      ],
    );
  }
}

abstract final class SupplierDashboardActions {
  static Future<void> showStatement(BuildContext context, Supplier supplier) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => _SupplierStatementSheet(
          supplier: supplier,
          scrollController: controller,
        ),
      ),
    );
  }

  static Future<void> showPayment(BuildContext context, Supplier supplier) async {
    final amount = TextEditingController();
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
                Text('دفع للمورد: ${supplier.name}'),
                AmountField(controller: amount, label: S.paidAmount),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: S.notes),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
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
                              await sl<SupplierService>().recordPayment(
                                session: context.read<AuthCubit>().state.session!,
                                supplierId: supplier.id,
                                amount: Money.parse(amount.text),
                                notes: notes.text,
                              );
                              await sl<SyncEngine>().maybeSyncAfterLocalWrite();
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            sl<AppAlertCubit>().success('تم تسجيل الدفع.');
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

  static Future<void> showPurchase(BuildContext context, Supplier supplier) async {
    final paid = TextEditingController();
    final lines = <PurchaseLineDraft>[];
    final products = <String, Product>{};
    var payMode = _PayMode.credit;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            Money total() =>
                lines.fold(Money.zero(), (sum, line) => sum + line.lineTotal);
            Money paidAmount() {
              try {
                return Money.parse(paid.text.isEmpty ? '0' : paid.text);
              } catch (_) {
                return Money.zero();
              }
            }

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
                    Text('فاتورة شراء: ${supplier.name}',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    StreamBuilder<List<Product>>(
                      stream: sl<CatalogService>().watchProducts(''),
                      builder: (context, snapshot) {
                        final items = snapshot.data ?? const <Product>[];
                        return SearchableSelectField<String>(
                          label: S.selectProduct,
                          value: null,
                          options: [
                            for (final product in items)
                              SearchableOption(
                                value: product.id,
                                label: product.name,
                                subtitle: product.sku,
                              ),
                          ],
                          onChanged: (id) async {
                            Product? picked;
                            for (final product in items) {
                              if (product.id == id) picked = product;
                            }
                            if (picked == null) return;
                            final quantity = await showQuantitySheet(
                              context: context,
                              title: picked.name,
                            );
                            if (quantity == null) return;
                            setS(() {
                              products[picked!.id] = picked;
                              lines.add(
                                PurchaseLineDraft(
                                  productId: picked.id,
                                  quantity: quantity,
                                  unit: picked.unit,
                                  unitPrice: Money.parse(picked.purchasePrice),
                                ),
                              );
                              if (payMode == _PayMode.cash) {
                                paid.text = total().toStorage();
                              }
                            });
                          },
                        );
                      },
                    ),
                    Expanded(
                      child: lines.isEmpty
                          ? const Center(child: Text('لم تتم إضافة أصناف بعد'))
                          : ListView.builder(
                              itemCount: lines.length,
                              itemBuilder: (_, index) {
                                final line = lines[index];
                                return ListTile(
                                  title: Text(products[line.productId]?.name ?? 'منتج'),
                                  subtitle: Text(
                                    '${line.quantity.toStorage()} × ${line.unitPrice.toDisplay()}',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => setS(() {
                                      lines.removeAt(index);
                                      if (payMode == _PayMode.cash) {
                                        paid.text = total().toStorage();
                                      }
                                    }),
                                  ),
                                );
                              },
                            ),
                    ),
                    SegmentedButton<_PayMode>(
                      segments: const [
                        ButtonSegment(value: _PayMode.cash, label: Text('نقدي')),
                        ButtonSegment(value: _PayMode.credit, label: Text('آجل')),
                      ],
                      selected: {payMode},
                      onSelectionChanged: (value) => setS(() {
                        payMode = value.first;
                        if (payMode == _PayMode.cash) {
                          paid.text = total().toStorage();
                        }
                      }),
                    ),
                    if (payMode == _PayMode.credit)
                      AmountField(controller: paid, label: S.paidAmount),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الإجمالي'),
                        MoneyText(total()),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: lines.isEmpty
                          ? null
                          : () async {
                              try {
                                if (payMode == _PayMode.cash) {
                                  paid.text = total().toStorage();
                                }
                                await sl<AppBusyCubit>().guard(() async {
                                  await sl<PurchaseService>().create(
                                    context.read<AuthCubit>().state.session!,
                                    PurchaseDraft(
                                      supplierId: supplier.id,
                                      lines: List.of(lines),
                                      paidAmount: paidAmount(),
                                    ),
                                  );
                                  await sl<SyncEngine>().maybeSyncAfterLocalWrite();
                                });
                                if (ctx.mounted) Navigator.pop(ctx);
                                sl<AppAlertCubit>().success(S.purchaseSuccess);
                              } catch (e) {
                                sl<AppAlertCubit>().error(e.toString());
                              }
                            },
                      child: const Text(S.confirmPurchase),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> showReturn(BuildContext context, Supplier supplier) async {
    final purchases = await sl<SupplierService>().purchases(supplier.id);
    if (!context.mounted) return;
    final eligible = [
      for (final purchase in purchases)
        if (purchase.status != 'cancelled' && purchase.status != 'returned')
          purchase,
    ];
    if (eligible.isEmpty) {
      sl<AppAlertCubit>().warning('لا توجد فواتير قابلة للمرتجع.');
      return;
    }
    Purchase? selected = eligible.first;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('مرتجع شراء'),
          content: DropdownButtonFormField<Purchase>(
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'اختر الفاتورة'),
            items: [
              for (final purchase in eligible)
                DropdownMenuItem(
                  value: purchase,
                  child: Text('${purchase.purchaseNumber} • ${ArabicFormat.transactionDate(purchase.purchasedAt)}'),
                ),
            ],
            onChanged: (v) => setS(() => selected = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.back)),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await DestructiveActionGuard.run(
                        context: context,
                        title: 'تأكيد المرتجع',
                        message:
                            'سيتم إرجاع الكميات المتبقية وعكس المخزون مع قيد دائن للمورد.',
                        confirmLabel: 'تأكيد المرتجع',
                        successMessage: 'تم تسجيل مرتجع الشراء.',
                        action: () async {
                          await sl<PurchaseService>().returnLines(
                            context.read<AuthCubit>().state.session!,
                            selected!.id,
                          );
                          await sl<SyncEngine>().maybeSyncAfterLocalWrite();
                        },
                      );
                    },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> deleteSupplier(BuildContext context, Supplier supplier) async {
    await DestructiveActionGuard.run(
      context: context,
      title: 'حذف المورد',
      message: 'يُحذف المورد فقط إن لم تكن له مشتريات أو رصيد مستحق.',
      confirmLabel: 'حذف',
      successMessage: 'تم حذف المورد.',
      action: () async {
        await sl<SupplierService>().delete(
          session: context.read<AuthCubit>().state.session!,
          id: supplier.id,
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      },
    );
  }
}

enum _PayMode { cash, credit }

class _SupplierStatementSheet extends StatelessWidget {
  const _SupplierStatementSheet({
    required this.supplier,
    required this.scrollController,
  });

  final Supplier supplier;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'كشف حساب: ${supplier.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (supplier.phone != null)
                  IconButton(
                    tooltip: 'واتساب',
                    onPressed: () async {
                      final link = EgyptPhone.whatsAppApi(supplier.phone);
                      if (link == null) return;
                      await launchUrl(Uri.parse(link));
                    },
                    icon: const Icon(Icons.chat_outlined),
                  ),
                IconButton(
                  tooltip: 'تصدير PDF',
                  onPressed: () async {
                    try {
                      final data = await sl<SupplierService>()
                          .watchStatement(supplier.id)
                          .first;
                      await SupplierStatementExport.sharePdf(
                        session: session,
                        supplier: supplier,
                        txs: data.txs,
                        openingBalance: Money.zero(),
                      );
                    } catch (e) {
                      sl<AppAlertCubit>().error(e.toString());
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<
                ({SupplierAccount? account, List<SupplierAccountTransaction> txs})>(
              stream: sl<SupplierService>().watchStatement(supplier.id),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final txs = [...snap.data!.txs]
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                if (txs.isEmpty) {
                  return const Center(child: Text(S.empty));
                }
                var balance = Money.zero();
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('نوع العملية')),
                            DataColumn(label: Text('مدين'), numeric: true),
                            DataColumn(label: Text('دائن'), numeric: true),
                            DataColumn(label: Text('الرصيد'), numeric: true),
                          ],
                          rows: [
                            for (final tx in txs) ...[
                              () {
                                final amount = Money.parse(tx.amount);
                                final debit = amount.isPositive ? amount : Money.zero();
                                final credit = amount.isNegative ? -amount : Money.zero();
                                balance += amount;
                                return DataRow(
                                  cells: [
                                    DataCell(Text(ArabicFormat.transactionDateTime(tx.createdAt))),
                                    DataCell(Text(_txLabel(tx.type))),
                                    DataCell(Text(debit.isZero ? '—' : debit.toDisplay())),
                                    DataCell(Text(credit.isZero ? '—' : credit.toDisplay())),
                                    DataCell(Text(balance.toDisplay())),
                                  ],
                                );
                              }(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _txLabel(String type) => switch (type) {
    'purchase' => 'شراء',
    'payment' => 'سداد',
    'purchase_cancel' => 'عكس شراء ملغى',
    'payment_cancel' => 'عكس سداد',
    'purchase_return' => 'مرتجع شراء',
    'receipt' => 'إيصال / خصم',
    _ => 'حركة حساب',
  };
}

class SupplierDetailPage extends StatefulWidget {
  const SupplierDetailPage({super.key, required this.supplierId});

  final String supplierId;

  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.go('/suppliers');
      final supplier = await sl<SupplierService>().get(widget.supplierId);
      if (supplier != null && mounted) {
        await SupplierDashboardActions.showStatement(context, supplier);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class PurchasesRedirectPage extends StatelessWidget {
  const PurchasesRedirectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SuppliersPage();
  }
}
