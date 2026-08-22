import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/inventory_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.inventory,
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
                        subtitle: Text('${S.currentStock}: ${p.currentStock}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: S.stockIn,
                              onPressed: () => _move(p, 'stock_in'),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            IconButton(
                              tooltip: S.stockOut,
                              onPressed: () => _move(p, 'stock_out'),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                        onTap: () => _showMovements(p),
                      ),
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

  Future<void> _move(Product product, String type) async {
    final qty = TextEditingController(text: '1.000');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'stock_in' ? S.stockIn : S.stockOut),
        content: TextField(
          controller: qty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: S.quantity),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await sl<AppBusyCubit>().guard(() async {
        await sl<InventoryService>().adjust(
          session: context.read<AuthCubit>().state.session!,
          productId: product.id,
          quantity: Quantity.parse(qty.text),
          type: type,
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

  Future<void> _showMovements(Product product) async {
    final db = sl<AppDatabase>();
    final rows =
        await (db.select(db.inventoryMovements)
              ..where((t) => t.productId.equals(product.id))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(50))
            .get();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView(
        children: [
          ListTile(
            title: Text(product.name),
            subtitle: const Text(S.recentMovements),
          ),
          for (final m in rows)
            ListTile(
              title: Text('${m.type} ${m.quantity}'),
              subtitle: Text('${m.previousStock} → ${m.newStock}'),
              trailing: Text(m.createdAt.toLocal().toString()),
            ),
        ],
      ),
    );
  }
}
