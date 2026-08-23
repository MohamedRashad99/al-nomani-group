import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/breakpoints.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/catalog_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.products,
      fab: session.can(AppPermission.productsCreate)
          ? FloatingActionButton(
              onPressed: () => _edit(null),
              child: const Icon(Icons.add),
            )
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: S.search,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: sl<CatalogService>().searchProducts(_query),
              builder: (context, snap) {
                final items = snap.data ?? const <Product>[];
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) return const Center(child: Text(S.empty));
                if (Breakpoints.isPhone(context)) {
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final p = items[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.sku} • ${p.currentStock} ${ProductUnit.fromCode(p.unit).arabicLabel}',
                          ),
                          trailing: MoneyText(Money.parse(p.sellingPrice)),
                          onTap: session.can(AppPermission.productsUpdate)
                              ? () => _edit(p)
                              : null,
                        ),
                      );
                    },
                  );
                }
                return SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text(S.productName)),
                        DataColumn(label: Text(S.sku)),
                        DataColumn(label: Text(S.currentStock)),
                        DataColumn(label: Text(S.sellingPrice)),
                      ],
                      rows: [
                        for (final p in items)
                          DataRow(
                            onSelectChanged:
                                session.can(AppPermission.productsUpdate)
                                ? (_) => _edit(p)
                                : null,
                            cells: [
                              DataCell(Text(p.name)),
                              DataCell(Text(p.sku)),
                              DataCell(Text(p.currentStock)),
                              DataCell(MoneyText(Money.parse(p.sellingPrice))),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Product? product) async {
    final name = TextEditingController(text: product?.name ?? '');
    final sku = TextEditingController(text: product?.sku ?? '');
    final brand = TextEditingController(text: product?.brand ?? '');
    final purchase = TextEditingController(
      text: product?.purchasePrice ?? '0.000',
    );
    final sell = TextEditingController(text: product?.sellingPrice ?? '0.000');
    final stock = TextEditingController(text: product?.currentStock ?? '0.000');
    final min = TextEditingController(text: product?.minimumStock ?? '0.000');
    var unit = product?.unit ?? 'kg';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
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
                    decoration: const InputDecoration(labelText: S.productName),
                  ),
                  TextField(
                    controller: sku,
                    decoration: const InputDecoration(labelText: S.sku),
                  ),
                  TextField(
                    controller: brand,
                    decoration: const InputDecoration(labelText: S.brand),
                  ),
                  TextField(
                    controller: purchase,
                    decoration: const InputDecoration(
                      labelText: S.purchasePrice,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: sell,
                    decoration: const InputDecoration(
                      labelText: S.sellingPrice,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (product == null)
                    TextField(
                      controller: stock,
                      decoration: const InputDecoration(
                        labelText: S.currentStock,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  TextField(
                    controller: min,
                    decoration: const InputDecoration(
                      labelText: S.minimumStock,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: unit,
                    items: [
                      for (final u in ProductUnit.values)
                        DropdownMenuItem(
                          value: u.code,
                          child: Text(u.arabicLabel),
                        ),
                    ],
                    onChanged: (v) => setS(() => unit = v ?? unit),
                    decoration: const InputDecoration(labelText: S.unit),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(S.save),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (saved != true || !mounted) return;
    try {
      await sl<AppBusyCubit>().guard(() async {
        await sl<CatalogService>().upsertProduct(
          session: context.read<AuthCubit>().state.session!,
          id: product?.id,
          name: name.text,
          sku: sku.text,
          brand: brand.text,
          purchasePrice: Money.parse(purchase.text),
          sellingPrice: Money.parse(sell.text),
          currentStock: Quantity.parse(stock.text),
          minimumStock: Quantity.parse(min.text),
          unit: unit,
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      });
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
