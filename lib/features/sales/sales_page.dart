import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/models/sale_draft.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/sale_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/money_text.dart';

enum _SalePeriod { all, today, week, month }

enum _PaymentFilter { all, cash, credit, partial }

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

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _search = TextEditingController();
  late Future<List<SaleListEntry>> _future;
  _SalePeriod _period = _SalePeriod.all;
  _PaymentFilter _payment = _PaymentFilter.all;
  bool _showCancelled = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<SaleListEntry>> _load() async {
    final db = sl<AppDatabase>();
    final results = await Future.wait([
      (db.select(db.sales)
            ..where((row) => row.isDeleted.equals(false))
            ..orderBy([(row) => OrderingTerm.desc(row.soldAt)]))
          .get(),
      db.select(db.customers).get(),
      db.select(db.saleItems).get(),
    ]);
    final sales = results[0] as List<Sale>;
    final customers = {
      for (final customer in results[1] as List<Customer>)
        customer.id: customer.name,
    };
    final counts = <String, int>{};
    for (final item in results[2] as List<SaleItem>) {
      counts.update(item.saleId, (value) => value + 1, ifAbsent: () => 1);
    }
    return [
      for (final sale in sales)
        SaleListEntry(
          sale: sale,
          customerName: customers[sale.customerId] ?? 'عميل غير متاح',
          itemCount: counts[sale.id] ?? 0,
        ),
    ];
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

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final canCreate =
        context.watch<AuthCubit>().state.session?.can(
          AppPermission.salesCreate,
        ) ==
        true;
    return AppScaffold(
      title: S.sales,
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      fab: canCreate
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/sales/new');
                _refresh();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text(S.newSale),
            )
          : null,
      child: FutureBuilder<List<SaleListEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
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
                                  _refresh();
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
  final _paid = TextEditingController(text: '0.000');
  final _lines = <SaleLineDraft>[];
  final _products = <String, Product>{};
  bool _saving = false;

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
    final result = _total - _paidAmount;
    return result.isNegative ? Money.zero() : result;
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              padding: const EdgeInsets.all(16),
              children: [
                _Section(
                  title: 'العميل',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(_customer?.name ?? S.selectCustomer),
                    subtitle: Text(
                      _customer?.phone ?? 'اختر حساب العميل قبل تأكيد البيع',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: _pickCustomer,
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'أصناف الفاتورة',
                  action: FilledButton.tonalIcon(
                    onPressed: _pickAndAddProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة صنف'),
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
                                onRemove: () =>
                                    setState(() => _lines.removeAt(index)),
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
                              selected: _paidAmount >= _total && !_total.isZero,
                              label: const Text('نقدي بالكامل'),
                              onSelected: (_) => setState(
                                () => _paid.text = _total.toStorage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              selected: _paidAmount.isZero,
                              label: const Text('آجل'),
                              onSelected: (_) =>
                                  setState(() => _paid.text = '0.000'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _paid,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: S.paidAmount,
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AmountRow(label: S.total, amount: _total),
                      _AmountRow(label: S.paidAmount, amount: _paidAmount),
                      _AmountRow(
                        label: S.remaining,
                        amount: _remaining,
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 100),
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

  Future<void> _pickCustomer() async {
    final customers = await sl<CatalogService>().searchCustomers('');
    if (!mounted) return;
    final selected = await _SearchPicker.show<Customer>(
      context: context,
      title: S.selectCustomer,
      items: customers,
      searchableText: (customer) =>
          '${customer.name} ${customer.phone ?? ''} ${customer.area ?? ''}',
      tileBuilder: (customer) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(customer.name),
        subtitle: Text(
          [customer.phone, customer.area].whereType<String>().join(' • '),
        ),
      ),
    );
    if (selected != null) setState(() => _customer = selected);
  }

  Future<void> _pickAndAddProduct() async {
    final products = await sl<CatalogService>().searchProducts('');
    if (!mounted) return;
    final selected = await _SearchPicker.show<Product>(
      context: context,
      title: S.selectProduct,
      items: products,
      searchableText: (product) =>
          '${product.name} ${product.sku} ${product.brand ?? ''}',
      tileBuilder: (product) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
        title: Text(product.name),
        subtitle: Text('${product.sku} • متوفر ${product.currentStock}'),
        trailing: MoneyText(Money.parse(product.sellingPrice)),
      ),
    );
    if (selected == null || !mounted) return;
    final quantity = await _quantityDialog(selected, Quantity.parse('1'));
    if (quantity == null) return;
    _addProduct(selected, quantity);
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
    });
  }

  Future<void> _editLine(int index) async {
    final product = _products[_lines[index].productId];
    if (product == null) return;
    final quantity = await _quantityDialog(product, _lines[index].quantity);
    if (quantity == null) return;
    final others = _lines
        .asMap()
        .entries
        .where(
          (entry) => entry.key != index && entry.value.productId == product.id,
        )
        .fold(Quantity.zero(), (sum, entry) => sum + entry.value.quantity);
    if (others + quantity > Quantity.parse(product.currentStock)) {
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
    });
  }

  Future<Quantity?> _quantityDialog(Product product, Quantity initial) async {
    final controller = TextEditingController(text: initial.toStorage());
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: S.quantity,
            helperText: 'المتوفر ${product.currentStock}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text(S.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return null;
    try {
      final quantity = Quantity.parse(value);
      if (!quantity.isPositive) throw const FormatException();
      return quantity;
    } catch (_) {
      _message(S.invalidQty);
      return null;
    }
  }

  Future<void> _confirm() async {
    if (_customer == null || _lines.isEmpty) {
      _message(S.requiredField);
      return;
    }
    if (_paidAmount > _total) {
      _message('المبلغ المدفوع لا يمكن أن يتجاوز إجمالي البيع.');
      return;
    }
    setState(() => _saving = true);
    try {
      await sl<AppBusyCubit>().guard(() async {
        await sl<SaleService>().create(
          context.read<AuthCubit>().state.session!,
          SaleDraft(
            customerId: _customer!.id,
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

class _SearchPicker {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String Function(T item) searchableText,
    required Widget Function(T item) tileBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = items
                .where(
                  (item) => searchableText(
                    item,
                  ).toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
            return FractionallySizedBox(
              heightFactor: .88,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          autofocus: true,
                          onChanged: (value) =>
                              setState(() => query = value.trim()),
                          decoration: const InputDecoration(
                            hintText: S.search,
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => InkWell(
                        onTap: () => Navigator.pop(context, filtered[index]),
                        child: tileBuilder(filtered[index]),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
  late Future<_SaleDetails?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SaleDetails?> _load() async {
    final db = sl<AppDatabase>();
    final sale = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(widget.saleId))).getSingleOrNull();
    if (sale == null) return null;
    final customer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(sale.customerId))).getSingleOrNull();
    final items = await (db.select(
      db.saleItems,
    )..where((row) => row.saleId.equals(sale.id))).get();
    final products = await db.select(db.products).get();
    return _SaleDetails(
      sale: sale,
      customer: customer,
      items: items,
      productNames: {for (final product in products) product.id: product.name},
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل البيع')),
      body: FutureBuilder<_SaleDetails?>(
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
            const Text('سيتم عكس المخزون وحساب العميل. لن تُحذف الفاتورة.'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء البيع وعكس حركاته.')),
        );
        setState(() => _future = _load());
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

class _SaleDetails {
  const _SaleDetails({
    required this.sale,
    required this.customer,
    required this.items,
    required this.productNames,
  });

  final Sale sale;
  final Customer? customer;
  final List<SaleItem> items;
  final Map<String, String> productNames;
}
