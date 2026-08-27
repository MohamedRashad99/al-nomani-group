import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/outstanding_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/deletion_workflow_dialog.dart';
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
            child: StreamBuilder<List<Customer>>(
              stream: sl<CatalogService>().watchCustomers(_query),
              builder: (context, snap) {
                final items = snap.data ?? const <Customer>[];
                if (!snap.hasData) {
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
                        onTap: () =>
                            context.push('/customers/${c.id}/statement'),
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
                    decoration: const InputDecoration(
                      labelText: S.customerName,
                    ),
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
                                await sl<CatalogService>().upsertCustomer(
                                  session: context
                                      .read<AuthCubit>()
                                      .state
                                      .session!,
                                  id: customer?.id,
                                  name: name.text,
                                  phone: phone.text,
                                  area: area.text,
                                  address: address.text,
                                  notes: notes.text,
                                );
                                await sl<SyncEngine>()
                                    .maybeSyncAfterLocalWrite();
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
                  if (customer != null &&
                      context
                              .read<AuthCubit>()
                              .state
                              .session
                              ?.can(AppPermission.customersDelete) ==
                          true) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              try {
                                final report = await sl<CatalogService>()
                                    .inspectCustomer(customer.id);
                                if (!ctx.mounted) return;
                                final confirmed =
                                    await showDeletionWorkflowDialog(
                                      context: ctx,
                                      title: S.deleteCustomer,
                                      report: report,
                                    );
                                if (confirmed != true) return;
                                setS(() {
                                  saving = true;
                                  error = null;
                                });
                                await sl<AppBusyCubit>().guard(() async {
                                  await sl<CatalogService>().deleteCustomer(
                                    session: context
                                        .read<AuthCubit>()
                                        .state
                                        .session!,
                                    id: customer.id,
                                  );
                                  await sl<SyncEngine>()
                                      .maybeSyncAfterLocalWrite();
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
                      child: const Text(S.deleteCustomer),
                    ),
                  ],
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

class CustomerStatementPage extends StatelessWidget {
  const CustomerStatementPage({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${S.statement} — ${customer.name}')),
      body: StreamBuilder(
        stream: sl<OutstandingService>().watchStatement(customer.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final account = snap.data!.account;
          final txs = snap.data!.txs;
          final balance = Money.parse(account?.cachedBalance ?? '0.000');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                title: const Text(S.balance),
                trailing: MoneyText(balance),
              ),
              const Divider(),
              if (txs.isEmpty) const Center(child: Text(S.empty)),
              for (final tx in txs)
                ListTile(
                  title: Text(_accountType(tx.type)),
                  subtitle: Text(
                    [
                      ArabicFormat.dateTime(tx.createdAt),
                      if (tx.notes?.isNotEmpty == true) tx.notes!,
                    ].join(' • '),
                  ),
                  trailing: MoneyText(Money.parse(tx.amount)),
                ),
            ],
          );
        },
      ),
    );
  }

  String _accountType(String type) => switch (type) {
    'sale' => 'بيع',
    'payment' => 'سداد',
    'sale_cancel' => 'عكس بيع ملغى',
    'payment_cancel' => 'عكس سداد',
    'opening_balance' => 'رصيد افتتاحي',
    'manual_debit' => 'مبلغ آجل يدوي',
    'manual_credit' => 'تخفيض يدوي',
    _ => 'حركة حساب',
  };
}

class CustomerStatementRoutePage extends StatelessWidget {
  const CustomerStatementRoutePage({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Customer?>(
      stream: sl<OutstandingService>().watchCustomer(customerId),
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final customer = snapshot.data;
        if (customer == null) {
          return const Scaffold(body: Center(child: Text('العميل غير موجود.')));
        }
        return CustomerStatementPage(customer: customer);
      },
    );
  }
}
