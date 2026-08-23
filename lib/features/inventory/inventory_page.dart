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
import '../../shared/widgets/quantity_sheet.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    final canMove =
        session?.can(AppPermission.inventoryAdjust) == true ||
        session?.can(AppPermission.inventoryCreate) == true;
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
            child: StreamBuilder<List<Product>>(
              stream: sl<CatalogService>().watchProducts(_query),
              builder: (context, snap) {
                final items = snap.data ?? const <Product>[];
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) return const Center(child: Text(S.empty));
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
                        trailing: !canMove
                            ? null
                            : Wrap(
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
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
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
    final stock = Quantity.parse(product.currentStock);
    final quantity = await showQuantitySheet(
      context: context,
      title: type == 'stock_in' ? S.stockIn : S.stockOut,
      helperText: '${S.currentStock}: ${product.currentStock}',
      max: type == 'stock_out'
          ? (stock.isPositive ? stock : Quantity.zero())
          : null,
    );
    if (quantity == null || !mounted) return;
    try {
      await sl<AppBusyCubit>().guard(() async {
        await sl<InventoryService>().adjust(
          session: context.read<AuthCubit>().state.session!,
          productId: product.id,
          quantity: quantity,
          type: type,
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showMovements(Product product) async {
    final db = sl<AppDatabase>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StreamBuilder<List<InventoryMovement>>(
        stream:
            (db.select(db.inventoryMovements)
                  ..where((t) => t.productId.equals(product.id))
                  ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
                  ..limit(50))
                .watch(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <InventoryMovement>[];
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              ListTile(
                title: Text(product.name),
                subtitle: const Text(S.recentMovements),
              ),
              if (rows.isEmpty) const ListTile(title: Text(S.empty)),
              for (final m in rows)
                ListTile(
                  title: Text('${m.type} ${m.quantity}'),
                  subtitle: Text('${m.previousStock} → ${m.newStock}'),
                  trailing: Text(m.createdAt.toLocal().toString()),
                ),
            ],
          );
        },
      ),
    );
  }
}
