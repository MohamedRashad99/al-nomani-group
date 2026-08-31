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
import '../../domain/models/sale_draft.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/inventory_measure.dart';
import '../../domain/services/sale_service.dart';
import '../../features/app/app_alert_cubit.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/quantity_sheet.dart';
import '../../shared/widgets/searchable_select.dart';

enum _SalePeriod { all, today, week, month }

enum _PaymentFilter { all, cash, credit, partial }

enum _PayMode { cash, credit }

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _search = TextEditingController();
  late final Stream<List<SaleListEntry>> _stream =
      sl<SaleService>().watchEntries();
  _SalePeriod _period = _SalePeriod.all;
  _PaymentFilter _payment = _PaymentFilter.all;
  bool _showCancelled = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SaleListEntry> _filtered(List<SaleListEntry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (_period) {
      _SalePeriod.all => null,
      _SalePeriod.today => today,
      _SalePeriod.week => today.subtract(const Duration(days: 7)),
      _SalePeriod.month => DateTime(now.year, now.month, 1),
    };
    final query = _search.text.trim().toLowerCase();
    return entries.where((entry) {
      if (!_showCancelled && entry.sale.status == 'cancelled') return false;
      if (from != null && entry.sale.soldAt.toLocal().isBefore(from)) {
        return false;
      }
      if (_payment != _PaymentFilter.all &&
          entry.paymentType != _payment.name) {
        return false;
      }
      return query.isEmpty ||
          entry.sale.saleNumber.toLowerCase().contains(query) ||
          entry.customerName.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        context.watch<AuthCubit>().state.session?.can(
          AppPermission.salesCreate,
        ) ==
        true;
    return AppScaffold(
      title: S.sales,
      fab: canCreate
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/sales/new');
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text(S.newSale),
            )
          : null,
      child: StreamBuilder<List<SaleListEntry>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const BrandedLoading(message: 'نحمّل سجل المبيعات');
          }
          final entries = _filtered(snapshot.data ?? const []);
          return Column(
            children: [
              _SalesFilters(
                search: _search,
                period: _period,
                payment: _payment,
                showCancelled: _showCancelled,
                onChanged: () => setState(() {}),
                onPeriodChanged: (value) => setState(() => _period = value),
                onPaymentChanged: (value) => setState(() => _payment = value),
                onCancelledChanged: (value) =>
                    setState(() => _showCancelled = value),
              ),
              Expanded(
                child: entries.isEmpty
                    ? BrandedEmptyState(
                        title: 'لا توجد مبيعات مطابقة',
                        message: 'غيّر عوامل التصفية أو سجّل عملية بيع جديدة.',
                        action: canCreate
                            ? FilledButton.icon(
                                onPressed: () async {
                                  await context.push('/sales/new');
                                },
                                icon: const Icon(Icons.add),
                                label: const Text(S.newSale),
                              )
                            : null,
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth >= 900) {
                            return _SalesTable(entries: entries);
                          }
                          return _SalesCards(entries: entries);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SalesFilters extends StatelessWidget {
  const _SalesFilters({
    required this.search,
    required this.period,
    required this.payment,
    required this.showCancelled,
    required this.onChanged,
    required this.onPeriodChanged,
    required this.onPaymentChanged,
    required this.onCancelledChanged,
  });

  final TextEditingController search;
  final _SalePeriod period;
  final _PaymentFilter payment;
  final bool showCancelled;
  final VoidCallback onChanged;
  final ValueChanged<_SalePeriod> onPeriodChanged;
  final ValueChanged<_PaymentFilter> onPaymentChanged;
  final ValueChanged<bool> onCancelledChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          children: [
            TextField(
              controller: search,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                hintText: 'ابحث برقم الفاتورة أو اسم العميل',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterMenu<_SalePeriod>(
                    value: period,
                    icon: Icons.calendar_today_outlined,
                    labels: const {
                      _SalePeriod.all: 'كل التواريخ',
                      _SalePeriod.today: 'اليوم',
                      _SalePeriod.week: 'آخر ٧ أيام',
                      _SalePeriod.month: 'هذا الشهر',
                    },
                    onSelected: onPeriodChanged,
                  ),
                  const SizedBox(width: 8),
                  _FilterMenu<_PaymentFilter>(
                    value: payment,
                    icon: Icons.payments_outlined,
                    labels: const {
                      _PaymentFilter.all: 'كل طرق الدفع',
                      _PaymentFilter.cash: 'نقدي',
                      _PaymentFilter.credit: 'آجل',
                      _PaymentFilter.partial: 'دفعة جزئية',
                    },
                    onSelected: onPaymentChanged,
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: showCancelled,
                    label: const Text('إظهار الملغاة'),
                    onSelected: onCancelledChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.value,
    required this.icon,
    required this.labels,
    required this.onSelected,
  });

  final T value;
  final IconData icon;
  final Map<T, String> labels;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final entry in labels.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: InputChip(
        avatar: Icon(icon, size: 18),
        label: Text(labels[value] ?? ''),
      ),
    );
  }
}

class _SalesCards extends StatelessWidget {
  const _SalesCards({required this.entries});

  final List<SaleListEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push('/sales/${entry.sale.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.customerName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _SaleStatusChip(entry: entry),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${entry.sale.saleNumber} • ${ArabicFormat.dateTime(entry.sale.soldAt)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                  const Divider(height: 22),
                  Row(
                    children: [
                      Text('${ArabicFormat.number(entry.itemCount)} أصناف'),
                      const Spacer(),
                      MoneyText(
                        Money.parse(entry.sale.subtotal),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_left_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SalesTable extends StatelessWidget {
  const _SalesTable({required this.entries});

  final List<SaleListEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('رقم الفاتورة')),
                DataColumn(label: Text('العميل')),
                DataColumn(label: Text('التاريخ')),
                DataColumn(label: Text('الأصناف')),
                DataColumn(label: Text('الدفع')),
                DataColumn(label: Text('الإجمالي'), numeric: true),
              ],
              rows: [
                for (final entry in entries)
                  DataRow(
                    onSelectChanged: (_) =>
                        context.push('/sales/${entry.sale.id}'),
                    cells: [
                      DataCell(Text(entry.sale.saleNumber)),
                      DataCell(Text(entry.customerName)),
                      DataCell(Text(ArabicFormat.dateTime(entry.sale.soldAt))),
                      DataCell(Text(ArabicFormat.number(entry.itemCount))),
                      DataCell(_SaleStatusChip(entry: entry)),
                      DataCell(MoneyText(Money.parse(entry.sale.subtotal))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleStatusChip extends StatelessWidget {
  const _SaleStatusChip({required this.entry});

  final SaleListEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.sale.status == 'cancelled') {
      return const Chip(
        avatar: Icon(Icons.cancel_outlined, size: 16),
        label: Text('ملغاة'),
        backgroundColor: Color(0xFFFFEBEE),
      );
    }
    final (label, color) = switch (entry.paymentType) {
      'cash' => ('نقدي', AppColors.green),
      'credit' => ('آجل', AppColors.danger),
      _ => ('دفعة جزئية', AppColors.orange),
    };
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      backgroundColor: color.withValues(alpha: .09),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class NewSalePage extends StatefulWidget {
  const NewSalePage({super.key});

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  Customer? _customer;
  String? _customCustomerName;
  final _paid = TextEditingController();
  final _lines = <SaleLineDraft>[];
  final _products = <String, Product>{};
  bool _saving = false;
  _PayMode _payMode = _PayMode.credit;

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

  void _setPayMode(_PayMode mode) {
    setState(() {
      _payMode = mode;
      if (mode == _PayMode.cash) {
        _paid.text = _total.toStorage();
      } else {
        _paid.clear();
      }
    });
  }

  void _syncPaidWithMode() {
    if (_payMode == _PayMode.cash) {
      _paid.text = _total.toStorage();
    }
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(S.newSale),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 12),
            child: BrandMark(size: 34, showText: false),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              children: [
                _Section(
                  title: 'العميل',
                  child: StreamBuilder<List<Customer>>(
                    stream: sl<CatalogService>().watchCustomers(''),
                    builder: (context, snapshot) {
                      final customers = snapshot.data ?? const <Customer>[];
                      return SearchableSelectField<String>(
                        label: S.selectCustomer,
                        required: true,
                        allowCustom: true,
                        value: _customer?.id,
                        options: [
                          for (final customer in customers)
                            SearchableOption(
                              value: customer.id,
                              label: customer.name,
                              subtitle: customer.phone,
                              searchText:
                                  '${customer.phone ?? ''} ${customer.area ?? ''}',
                            ),
                        ],
                        onChanged: (id) {
                          Customer? selected;
                          for (final customer in customers) {
                            if (customer.id == id) selected = customer;
                          }
                          setState(() {
                            _customer = selected;
                            if (selected != null) _customCustomerName = null;
                          });
                        },
                        onCustomText: (name) {
                          setState(() {
                            _customCustomerName = name;
                            if (name.isNotEmpty) _customer = null;
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'أصناف الفاتورة',
                  action: StreamBuilder<List<Product>>(
                    stream: sl<CatalogService>().watchProducts(''),
                    builder: (context, snapshot) {
                      final products = snapshot.data ?? const <Product>[];
                      return SizedBox(
                        width: 220,
                        child: SearchableSelectField<String>(
                          label: S.selectProduct,
                          value: null,
                          options: [
                            for (final product in products)
                              SearchableOption(
                                value: product.id,
                                label: product.name,
                                subtitle:
                                    '${product.sku} • ${InventoryMeasure.fromProduct(product).packagesLabel} • ${InventoryMeasure.fromProduct(product).actualLabel}',
                                searchText:
                                    '${product.sku} ${product.brand ?? ''}',
                              ),
                          ],
                          onChanged: (id) async {
                            Product? selected;
                            for (final product in products) {
                              if (product.id == id) selected = product;
                            }
                            final picked = selected;
                            if (picked == null) return;
                            final reserved = _lines
                                .where((line) => line.productId == picked.id)
                                .fold(
                                  Quantity.zero(),
                                  (sum, line) => sum + line.quantity,
                                );
                            final quantity = await _askQuantity(
                              picked,
                              reserved: reserved,
                            );
                            if (quantity == null) return;
                            _addProduct(picked, quantity);
                          },
                        ),
                      );
                    },
                  ),
                  child: _lines.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('لم تتم إضافة أصناف بعد')),
                        )
                      : Column(
                          children: [
                            for (var index = 0; index < _lines.length; index++)
                              _SaleLineTile(
                                line: _lines[index],
                                product: _products[_lines[index].productId],
                                onRemove: () => setState(() {
                                  _lines.removeAt(index);
                                  _syncPaidWithMode();
                                }),
                                onEdit: () => _editLine(index),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'الدفع',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              selected: _payMode == _PayMode.cash,
                              label: const Text('نقدي بالكامل'),
                              onSelected: (_) => _setPayMode(_PayMode.cash),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              selected: _payMode == _PayMode.credit,
                              label: const Text('آجل'),
                              onSelected: (_) => _setPayMode(_PayMode.credit),
                            ),
                          ),
                        ],
                      ),
                      if (_payMode == _PayMode.credit) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'يمكنك إدخال دفعة نقدية الآن. المتبقي يُحسب تلقائياً ويُسجَّل آجلاً.',
                        ),
                        const SizedBox(height: 10),
                        AmountField(
                          controller: _paid,
                          label: S.paidAmount,
                          prefixIcon: const Icon(Icons.payments_outlined),
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
              ],
            );
            if (constraints.maxWidth < 900) return content;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: content,
              ),
            );
          },
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
          label: Text(
            _total.isZero
                ? S.confirmSale
                : '${S.confirmSale} • ${_total.toDisplay()} ${Money.currencySymbol}',
          ),
        ),
      ),
    );
  }

  void _addProduct(Product product, Quantity quantity) {
    final existingQuantity = _lines
        .where((line) => line.productId == product.id)
        .fold(Quantity.zero(), (sum, line) => sum + line.quantity);
    if (existingQuantity + quantity > Quantity.parse(product.currentStock)) {
      _message(S.insufficientStock);
      return;
    }
    setState(() {
      _products[product.id] = product;
      _lines.add(
        SaleLineDraft(
          productId: product.id,
          quantity: quantity,
          unit: product.unit,
          unitPrice: Money.parse(product.sellingPrice),
        ),
      );
      _syncPaidWithMode();
    });
  }

  Future<void> _editLine(int index) async {
    final product = _products[_lines[index].productId];
    if (product == null) return;
    final reserved = _lines
        .asMap()
        .entries
        .where(
          (entry) =>
              entry.key != index && entry.value.productId == product.id,
        )
        .fold(Quantity.zero(), (sum, entry) => sum + entry.value.quantity);
    final quantity = await _askQuantity(product, reserved: reserved);
    if (quantity == null) return;
    if (reserved + quantity > Quantity.parse(product.currentStock)) {
      _message(S.insufficientStock);
      return;
    }
    setState(() {
      _lines[index] = SaleLineDraft(
        productId: product.id,
        quantity: quantity,
        unit: product.unit,
        unitPrice: _lines[index].unitPrice,
      );
      _syncPaidWithMode();
    });
  }

  Future<Quantity?> _askQuantity(
    Product product, {
    required Quantity reserved,
  }) async {
    final stock = Quantity.parse(product.currentStock);
    final available = stock - reserved;
    return showQuantitySheet(
      context: context,
      title: product.name,
      helperText:
          'المتوفر ${InventoryMeasure.fromProduct(product).packagesLabel} • ${InventoryMeasure.fromProduct(product).actualLabel}',
      max: available.isPositive ? available : Quantity.zero(),
    );
  }

  Future<void> _confirm() async {
    if ((_customer == null &&
            (_customCustomerName == null || _customCustomerName!.isEmpty)) ||
        _lines.isEmpty) {
      _message(S.requiredField);
      return;
    }
    if (_payMode == _PayMode.cash) {
      _paid.text = _total.toStorage();
    }
    if (_paidAmount > _total) {
      _message('المبلغ المدفوع لا يمكن أن يتجاوز إجمالي البيع.');
      return;
    }
    setState(() => _saving = true);
    try {
      await sl<AppBusyCubit>().guard(() async {
        final session = context.read<AuthCubit>().state.session!;
        final customerId = await sl<CatalogService>().findOrCreateCustomer(
          session: session,
          id: _customer?.id,
          name: _customCustomerName,
        );
        await sl<SaleService>().create(
          session,
          SaleDraft(
            customerId: customerId,
            lines: List.of(_lines),
            paidAmount: _paidAmount,
          ),
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      });
      if (mounted) {
        _message(S.saleSuccess);
        context.pop();
      }
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    if (error) {
      sl<AppAlertCubit>().error(text);
    } else {
      sl<AppAlertCubit>().success(text);
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SaleLineTile extends StatelessWidget {
  const _SaleLineTile({
    required this.line,
    required this.product,
    required this.onRemove,
    required this.onEdit,
  });

  final SaleLineDraft line;
  final Product? product;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(product?.name ?? 'منتج'),
      subtitle: Text(
        '${line.quantity.toStorage()} × ${line.unitPrice.toDisplay()} ${Money.currencySymbol}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoneyText(line.lineTotal),
          IconButton(
            tooltip: S.edit,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'حذف الصنف',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
          ),
        ],
      ),
    );
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

class SaleDetailPage extends StatefulWidget {
  const SaleDetailPage({super.key, required this.saleId});

  final String saleId;

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  late Future<SaleDetails?> _future;

  @override
  void initState() {
    super.initState();
    _future = sl<SaleService>().loadDetails(widget.saleId);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل البيع')),
      body: FutureBuilder<SaleDetails?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const BrandedLoading();
          }
          final details = snapshot.data;
          if (details == null) {
            return const BrandedEmptyState(title: 'الفاتورة غير موجودة');
          }
          final sale = details.sale;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                title: sale.saleNumber,
                action: _SaleStatusChip(
                  entry: SaleListEntry(
                    sale: sale,
                    customerName: details.customer?.name ?? '',
                    itemCount: details.items.length,
                  ),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: S.customerName,
                      value: details.customer?.name ?? 'عميل غير متاح',
                    ),
                    _DetailRow(
                      label: 'التاريخ',
                      value: ArabicFormat.dateTime(sale.soldAt),
                    ),
                    _DetailRow(
                      label: 'الحالة',
                      value: ArabicFormat.status(sale.status),
                    ),
                    if (sale.cancelReason != null)
                      _DetailRow(
                        label: 'سبب الإلغاء',
                        value: sale.cancelReason!,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'الأصناف',
                child: Column(
                  children: [
                    for (final item in details.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          details.productNames[item.productId] ??
                              'منتج غير متاح',
                        ),
                        subtitle: Text(
                          '${item.quantity} × ${item.unitPrice} ${Money.currencySymbol}',
                        ),
                        trailing: MoneyText(Money.parse(item.lineTotal)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'ملخص المبالغ',
                child: Column(
                  children: [
                    _AmountRow(
                      label: S.total,
                      amount: Money.parse(sale.subtotal),
                    ),
                    _AmountRow(
                      label: S.paidAmount,
                      amount: Money.parse(sale.paidAmount),
                    ),
                    _AmountRow(
                      label: S.remaining,
                      amount: Money.parse(sale.remainingAmount),
                      emphasized: true,
                    ),
                  ],
                ),
              ),
              if (sale.status != 'cancelled' &&
                  session?.can(AppPermission.salesCancel) == true) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('إلغاء البيع وعكس الحركات'),
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
        title: const Text('تأكيد إلغاء البيع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'سيُعاد المخزون. إن وُجدت تحصيلات لاحقة فلن تُرد، ويُعكس المتبقي غير المسدد فقط.',
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
            child: const Text('إلغاء البيع'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || text.isEmpty || !mounted) return;
    try {
      await sl<SaleService>().cancel(
        context.read<AuthCubit>().state.session!,
        widget.saleId,
        text,
      );
      await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      if (mounted) {
        sl<AppAlertCubit>().success('تم إلغاء البيع وعكس حركاته.');
        setState(() => _future = sl<SaleService>().loadDetails(widget.saleId));
      }
    } catch (error) {
      if (mounted) sl<AppAlertCubit>().error(error.toString());
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

