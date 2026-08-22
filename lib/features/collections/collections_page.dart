import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/collection_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  late Future<List<Collection>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Collection>> _load() {
    final db = sl<AppDatabase>();
    return (db.select(db.collections)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.collectedAt)]))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.collections,
      fab: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      child: FutureBuilder<List<Collection>>(
        future: _future,
        builder: (context, snap) {
          final items = snap.data ?? const <Collection>[];
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) return const Center(child: Text(S.empty));
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final c = items[i];
              return ListTile(
                title: MoneyText(Money.parse(c.amount)),
                subtitle: Text(
                  '${c.paymentMethod} • ${c.collectedAt.toLocal()}',
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create() async {
    final customers = await sl<CatalogService>().searchCustomers('');
    if (!mounted) return;
    Customer? selected = customers.isEmpty ? null : customers.first;
    final amount = TextEditingController();
    final notes = TextEditingController();
    var method = 'cash';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
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
              DropdownButtonFormField<Customer>(
                initialValue: selected,
                items: [
                  for (final c in customers)
                    DropdownMenuItem(value: c, child: Text(c.name)),
                ],
                onChanged: (v) => setS(() => selected = v),
                decoration: const InputDecoration(labelText: S.customerName),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: S.collectionAmount,
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text(S.cash)),
                  DropdownMenuItem(value: 'transfer', child: Text(S.transfer)),
                ],
                onChanged: (v) => setS(() => method = v ?? method),
                decoration: const InputDecoration(labelText: S.paymentMethod),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: S.notes),
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
    if (ok != true || selected == null || !mounted) return;
    try {
      await sl<AppBusyCubit>().guard(() async {
        await sl<CollectionService>().record(
          session: context.read<AuthCubit>().state.session!,
          customerId: selected!.id,
          amount: Money.parse(amount.text),
          paymentMethod: method,
          notes: notes.text,
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(S.collectionSuccess)));
        setState(() => _future = _load());
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
