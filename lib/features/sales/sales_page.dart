import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/models/sale_draft.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/sale_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  late Future<List<Sale>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Sale>> _load() {
    final db = sl<AppDatabase>();
    return (db.select(db.sales)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.soldAt)]))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.sales,
      fab: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const NewSalePage()));
          setState(() => _future = _load());
        },
        icon: const Icon(Icons.add),
        label: const Text(S.newSale),
      ),
      child: FutureBuilder<List<Sale>>(
        future: _future,
        builder: (context, snap) {
          final items = snap.data ?? const <Sale>[];
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) return const Center(child: Text(S.empty));
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final s = items[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(s.saleNumber),
                  subtitle: Text(
                    '${s.soldAt.toLocal()} • ${S.remaining} ${s.remainingAmount}',
                  ),
                  trailing: MoneyText(Money.parse(s.subtotal)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NewSalePage extends StatefulWidget {
  const NewSalePage({super.key});

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  Product? _product;
  Customer? _customer;
  final _qty = TextEditingController(text: '1.000');
  final _paid = TextEditingController(text: '0.000');
  final _lines = <SaleLineDraft>[];

  @override
  void dispose() {
    _qty.dispose();
    _paid.dispose();
    super.dispose();
  }

  Money get _total => _lines.fold(Money.zero(), (m, l) => m + l.lineTotal);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.newSale)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.tonal(
              onPressed: _pickProduct,
              child: Text(_product?.name ?? S.selectProduct),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: S.quantity),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _addLine, child: const Text(S.add)),
            const Divider(),
            ..._lines.map(
              (l) => ListTile(
                title: Text(l.productId),
                subtitle: Text(
                  '${l.quantity.toStorage()} × ${l.unitPrice.toStorage()}',
                ),
                trailing: MoneyText(l.lineTotal),
              ),
            ),
            ListTile(title: const Text(S.total), trailing: MoneyText(_total)),
            FilledButton.tonal(
              onPressed: _pickCustomer,
              child: Text(_customer?.name ?? S.selectCustomer),
            ),
            TextField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: S.paidAmount),
              onChanged: (_) => setState(() {}),
            ),
            Builder(
              builder: (_) {
                var remaining = Money.zero();
                try {
                  remaining =
                      _total -
                      Money.parse(_paid.text.isEmpty ? '0' : _paid.text);
                  if (remaining.isNegative) remaining = Money.zero();
                } catch (_) {}
                return ListTile(
                  title: const Text(S.remaining),
                  trailing: MoneyText(remaining),
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _confirm,
                child: const Text(S.confirmSale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickProduct() async {
    final items = await sl<CatalogService>().searchProducts('');
    if (!mounted) return;
    final selected = await showModalBottomSheet<Product>(
      context: context,
      builder: (ctx) => ListView(
        children: [
          for (final p in items)
            ListTile(
              title: Text(p.name),
              subtitle: Text('${p.sku} • ${p.currentStock}'),
              trailing: MoneyText(Money.parse(p.sellingPrice)),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ],
      ),
    );
    if (selected != null) setState(() => _product = selected);
  }

  Future<void> _pickCustomer() async {
    final items = await sl<CatalogService>().searchCustomers('');
    if (!mounted) return;
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      builder: (ctx) => ListView(
        children: [
          for (final c in items)
            ListTile(
              title: Text(c.name),
              subtitle: Text(c.phone ?? ''),
              onTap: () => Navigator.pop(ctx, c),
            ),
        ],
      ),
    );
    if (selected != null) setState(() => _customer = selected);
  }

  void _addLine() {
    final product = _product;
    if (product == null) return;
    try {
      final qty = Quantity.parse(_qty.text);
      setState(() {
        _lines.add(
          SaleLineDraft(
            productId: product.id,
            quantity: qty,
            unit: product.unit,
            unitPrice: Money.parse(product.sellingPrice),
          ),
        );
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirm() async {
    if (_customer == null || _lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(S.requiredField)));
      return;
    }
    try {
      final paid = Money.parse(_paid.text.isEmpty ? '0' : _paid.text);
      await sl<AppBusyCubit>().guard(() async {
        await sl<SaleService>().create(
          context.read<AuthCubit>().state.session!,
          SaleDraft(
            customerId: _customer!.id,
            lines: List.of(_lines),
            paidAmount: paid,
          ),
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(S.saleSuccess)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
