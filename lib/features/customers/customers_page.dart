import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/catalog_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.customers,
      fab: session.can(AppPermission.customersCreate)
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
            child: FutureBuilder<List<Customer>>(
              future: sl<CatalogService>().searchCustomers(_query),
              builder: (context, snap) {
                final items = snap.data ?? const <Customer>[];
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) return const Center(child: Text(S.empty));
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final c = items[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(c.name),
                        subtitle: Text('${c.phone ?? ''} • ${c.area ?? ''}'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerStatementPage(customer: c),
                          ),
                        ),
                        trailing: session.can(AppPermission.customersUpdate)
                            ? IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _edit(c),
                              )
                            : null,
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

  Future<void> _edit(Customer? customer) async {
    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final area = TextEditingController(text: customer?.area ?? '');
    final address = TextEditingController(text: customer?.address ?? '');
    final notes = TextEditingController(text: customer?.notes ?? '');
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: S.customerName),
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
    );
    if (ok != true || !mounted) return;
    await sl<AppBusyCubit>().guard(() async {
      await sl<CatalogService>().upsertCustomer(
        session: context.read<AuthCubit>().state.session!,
        id: customer?.id,
        name: name.text,
        phone: phone.text,
        area: area.text,
        address: address.text,
        notes: notes.text,
      );
      await sl<SyncEngine>().maybeSyncAfterLocalWrite();
    });
    if (mounted) setState(() {});
  }
}

class CustomerStatementPage extends StatelessWidget {
  const CustomerStatementPage({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final db = sl<AppDatabase>();
    return Scaffold(
      appBar: AppBar(title: Text('${S.statement} — ${customer.name}')),
      body: FutureBuilder(
        future: Future.wait([
          (db.select(
            db.customerAccounts,
          )..where((t) => t.customerId.equals(customer.id))).getSingleOrNull(),
          (db.select(db.customerAccountTransactions)
                ..where((t) => t.customerId.equals(customer.id))
                ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
              .get(),
        ]),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final account = snap.data![0] as CustomerAccount?;
          final txs = snap.data![1] as List<CustomerAccountTransaction>;
          final balance = Money.parse(account?.cachedBalance ?? '0.000');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                title: const Text(S.balance),
                trailing: MoneyText(balance),
              ),
              const Divider(),
              for (final tx in txs)
                ListTile(
                  title: Text(tx.type),
                  subtitle: Text(tx.createdAt.toLocal().toString()),
                  trailing: MoneyText(Money.parse(tx.amount)),
                ),
            ],
          );
        },
      ),
    );
  }
}
