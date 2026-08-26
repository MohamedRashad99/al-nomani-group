import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/models/purchase_draft.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/purchase_service.dart';
import '../../domain/services/supplier_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/quantity_sheet.dart';
import '../../shared/widgets/searchable_select.dart';

enum _PayMode { cash, credit }

class NewPurchasePage extends StatefulWidget {
  const NewPurchasePage({super.key, this.supplierId});

  final String? supplierId;

  @override
  State<NewPurchasePage> createState() => _NewPurchasePageState();
}

class _NewPurchasePageState extends State<NewPurchasePage> {
  Supplier? _supplier;
  final _paid = TextEditingController();
  final _lines = <PurchaseLineDraft>[];
  final _products = <String, Product>{};
  bool _saving = false;
  _PayMode _payMode = _PayMode.credit;
  bool _loadedInitial = false;

  Money get _total =>
      _lines.fold(Money.zero(), (sum, line) => sum + line.lineTotal);

  Money get _paidAmount {
    try {
      return Money.parse(_paid.text.isEmpty ? '0' : _paid.text);
    } catch (_) {
      return Money.zero();
    }
  }

  Money get _remaining {
    if (_payMode == _PayMode.cash) return Money.zero();
    final result = _total - _paidAmount;
    return result.isNegative ? Money.zero() : result;
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  Future<void> _ensureSupplier(List<Supplier> suppliers) async {
    if (_loadedInitial) return;
    final id = widget.supplierId;
    if (id == null) {
      _loadedInitial = true;
      return;
    }
    Supplier? selected;
    for (final supplier in suppliers) {
      if (supplier.id == id) selected = supplier;
    }
    if (selected == null) return;
    _loadedInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _supplier = selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.newPurchase)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: StreamBuilder<List<Supplier>>(
                  stream: sl<SupplierService>().watch(''),
                  builder: (context, snapshot) {
                    final suppliers = snapshot.data ?? const <Supplier>[];
                    _ensureSupplier(suppliers);
                    return SearchableSelectField<String>(
                      label: S.selectSupplier,
                      required: true,
                      value: _supplier?.id,
                      options: [
                        for (final supplier in suppliers)
                          SearchableOption(
                            value: supplier.id,
                            label: supplier.name,
                            subtitle: supplier.phone,
                          ),
                      ],
                      onChanged: (id) {
                        Supplier? selected;
                        for (final supplier in suppliers) {
                          if (supplier.id == id) selected = supplier;
                        }
                        setState(() => _supplier = selected);
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StreamBuilder<List<Product>>(
                      stream: sl<CatalogService>().watchProducts(''),
                      builder: (context, snapshot) {
                        final products = snapshot.data ?? const <Product>[];
                        return SearchableSelectField<String>(
                          label: S.selectProduct,
                          value: null,
                          options: [
                            for (final product in products)
                              SearchableOption(
                                value: product.id,
                                label: product.name,
                                subtitle:
                                    '${product.sku} • ${product.purchasePrice}',
                              ),
                          ],
                          onChanged: (id) async {
                            Product? selected;
                            for (final product in products) {
                              if (product.id == id) selected = product;
                            }
                            final picked = selected;
                            if (picked == null) return;
                            final quantity = await showQuantitySheet(
                              context: context,
                              title: picked.name,
                            );
                            if (quantity == null) return;
                            setState(() {
                              _products[picked.id] = picked;
                              _lines.add(
                                PurchaseLineDraft(
                                  productId: picked.id,
                                  quantity: quantity,
                                  unit: picked.unit,
                                  unitPrice: Money.parse(picked.purchasePrice),
                                ),
                              );
                              if (_payMode == _PayMode.cash) {
                                _paid.text = _total.toStorage();
                              }
                            });
                          },
                        );
                      },
                    ),
                    if (_lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('لم تتم إضافة أصناف بعد')),
                      )
                    else
                      for (var index = 0; index < _lines.length; index++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _products[_lines[index].productId]?.name ?? 'منتج',
                          ),
                          subtitle: Text(
                            '${_lines[index].quantity.toStorage()} × ${_lines[index].unitPrice.toDisplay()}',
                          ),
                          trailing: IconButton(
                            onPressed: () => setState(() {
                              _lines.removeAt(index);
                              if (_payMode == _PayMode.cash) {
                                _paid.text = _total.toStorage();
                              }
                            }),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            selected: _payMode == _PayMode.cash,
                            label: const Text('نقدي بالكامل'),
                            onSelected: (_) => setState(() {
                              _payMode = _PayMode.cash;
                              _paid.text = _total.toStorage();
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            selected: _payMode == _PayMode.credit,
                            label: const Text('آجل'),
                            onSelected: (_) => setState(() {
                              _payMode = _PayMode.credit;
                              _paid.clear();
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (_payMode == _PayMode.credit) ...[
                      const SizedBox(height: 10),
                      AmountField(
                        controller: _paid,
                        label: S.paidAmount,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _AmountRow(label: S.total, amount: _total),
                    _AmountRow(label: S.paidAmount, amount: _paidAmount),
                    if (_payMode == _PayMode.credit)
                      _AmountRow(
                        label: S.remaining,
                        amount: _remaining,
                        emphasized: true,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: _saving ? null : _confirm,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text(S.confirmPurchase),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    if (_supplier == null || _lines.isEmpty) {
      _message(S.requiredField);
      return;
    }
    if (_payMode == _PayMode.cash) {
      _paid.text = _total.toStorage();
    }
    setState(() => _saving = true);
    try {
      await sl<AppBusyCubit>().guard(() async {
        await sl<PurchaseService>().create(
          context.read<AuthCubit>().state.session!,
          PurchaseDraft(
            supplierId: _supplier!.id,
            lines: List.of(_lines),
            paidAmount: _paidAmount,
          ),
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      });
      if (mounted) {
        _message(S.purchaseSuccess);
        context.pop();
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class PurchaseDetailPage extends StatefulWidget {
  const PurchaseDetailPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  State<PurchaseDetailPage> createState() => _PurchaseDetailPageState();
}

class _PurchaseDetailPageState extends State<PurchaseDetailPage> {
  late Future<PurchaseDetails?> _future = sl<PurchaseService>().loadDetails(
    widget.purchaseId,
  );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الشراء')),
      body: FutureBuilder<PurchaseDetails?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const BrandedLoading();
          }
          final details = snapshot.data;
          if (details == null) {
            return const BrandedEmptyState(title: 'الفاتورة غير موجودة');
          }
          final purchase = details.purchase;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                title: Text(purchase.purchaseNumber),
                subtitle: Text(details.supplier?.name ?? 'مورد غير متاح'),
                trailing: Text(ArabicFormat.status(purchase.status)),
              ),
              for (final item in details.items)
                ListTile(
                  title: Text(
                    details.productNames[item.productId] ?? 'منتج غير متاح',
                  ),
                  subtitle: Text(
                    '${item.quantity} × ${item.unitPrice} ${Money.currencySymbol}',
                  ),
                  trailing: MoneyText(Money.parse(item.lineTotal)),
                ),
              _AmountRow(
                label: S.total,
                amount: Money.parse(purchase.subtotal),
              ),
              _AmountRow(
                label: S.paidAmount,
                amount: Money.parse(purchase.paidAmount),
              ),
              _AmountRow(
                label: S.remaining,
                amount: Money.parse(purchase.remainingAmount),
                emphasized: true,
              ),
              if (purchase.status != 'cancelled' &&
                  session?.can(AppPermission.purchasesCancel) == true) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('إلغاء الشراء وعكس الحركات'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إلغاء الشراء'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'سيُخرج المخزون ويُعكس حساب المورد إن كان الرصيد كافياً.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('إلغاء الشراء'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || text.isEmpty || !mounted) return;
    try {
      await sl<PurchaseService>().cancel(
        context.read<AuthCubit>().state.session!,
        widget.purchaseId,
        text,
      );
      await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء الشراء وعكس حركاته.')),
        );
        setState(
          () => _future = sl<PurchaseService>().loadDetails(widget.purchaseId),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final Money amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          MoneyText(amount, style: style),
        ],
      ),
    );
  }
}
