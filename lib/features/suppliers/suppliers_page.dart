import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/purchase_service.dart';
import '../../domain/services/supplier_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.suppliers,
      fab: session.can(AppPermission.suppliersCreate)
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
            child: StreamBuilder<List<Supplier>>(
              stream: sl<SupplierService>().watch(_query),
              builder: (context, snap) {
                final items = snap.data ?? const <Supplier>[];
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) return const Center(child: Text(S.empty));
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final supplier = items[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(supplier.name),
                        subtitle: Text(
                          '${supplier.phone ?? ''} • ${supplier.area ?? ''}',
                        ),
                        onTap: () => context.push('/suppliers/${supplier.id}'),
                        trailing: session.can(AppPermission.suppliersUpdate)
                            ? IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _edit(supplier),
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

  Future<void> _edit(Supplier? supplier) async {
    final name = TextEditingController(text: supplier?.name ?? '');
    final phone = TextEditingController(text: supplier?.phone ?? '');
    final area = TextEditingController(text: supplier?.area ?? '');
    final address = TextEditingController(text: supplier?.address ?? '');
    final notes = TextEditingController(text: supplier?.notes ?? '');
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
                      labelText: S.supplierName,
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
                                await sl<SupplierService>().upsert(
                                  session: context
                                      .read<AuthCubit>()
                                      .state
                                      .session!,
                                  id: supplier?.id,
                                  name: name.text,
                                  phone: phone.text,
                                  area: area.text,
                                  address: address.text,
                                  notes: notes.text,
                                );
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

class SupplierDetailPage extends StatelessWidget {
  const SupplierDetailPage({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    return StreamBuilder<Supplier?>(
      stream: sl<SupplierService>().watch('').map((rows) {
        for (final row in rows) {
          if (row.id == supplierId) return row;
        }
        return null;
      }),
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final supplier = snapshot.data;
        if (supplier == null) {
          return const Scaffold(body: Center(child: Text('المورد غير موجود.')));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(supplier.name),
            actions: [
              if (session?.can(AppPermission.purchasesCreate) == true)
                IconButton(
                  tooltip: S.newPurchase,
                  onPressed: () =>
                      context.push('/purchases/new?supplierId=$supplierId'),
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                ),
              if (session?.can(AppPermission.suppliersDelete) == true)
                IconButton(
                  tooltip: S.cancel,
                  onPressed: () => _delete(context, supplier),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FutureBuilder<SupplierTotals>(
                future: sl<SupplierService>().totals(supplierId),
                builder: (context, snap) {
                  final totals = snap.data;
                  if (totals == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('المستحق للمورد'),
                          trailing: MoneyText(totals.outstanding),
                        ),
                        ListTile(
                          title: const Text('إجمالي المشتريات'),
                          trailing: MoneyText(totals.purchases),
                        ),
                        ListTile(
                          title: const Text('إجمالي المدفوعات'),
                          trailing: MoneyText(totals.payments),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              if (session?.can(AppPermission.suppliersUpdate) == true ||
                  session?.can(AppPermission.purchasesCreate) == true)
                FilledButton.tonal(
                  onPressed: () => _pay(context, supplier),
                  child: const Text('تسجيل دفعة للمورد'),
                ),
              const SizedBox(height: 16),
              Text(
                S.purchases,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              StreamBuilder<List<PurchaseListEntry>>(
                stream: sl<PurchaseService>().watchEntries().map(
                  (rows) => [
                    for (final row in rows)
                      if (row.purchase.supplierId == supplierId) row,
                  ],
                ),
                builder: (context, snap) {
                  final rows = snap.data ?? const <PurchaseListEntry>[];
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (rows.isEmpty) return const Text(S.empty);
                  return Column(
                    children: [
                      for (final row in rows)
                        ListTile(
                          title: Text(row.purchase.purchaseNumber),
                          subtitle: Text(
                            ArabicFormat.dateTime(row.purchase.purchasedAt),
                          ),
                          trailing: MoneyText(
                            Money.parse(row.purchase.subtotal),
                          ),
                          onTap: () =>
                              context.push('/purchases/${row.purchase.id}'),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(S.statement, style: Theme.of(context).textTheme.titleMedium),
              StreamBuilder(
                stream: sl<SupplierService>().watchStatement(supplierId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final txs = snap.data!.txs;
                  if (txs.isEmpty) return const Text(S.empty);
                  return Column(
                    children: [
                      for (final tx in txs)
                        ListTile(
                          title: Text(_txLabel(tx.type)),
                          subtitle: Text(ArabicFormat.dateTime(tx.createdAt)),
                          trailing: MoneyText(Money.parse(tx.amount)),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static String _txLabel(String type) => switch (type) {
    'purchase' => 'شراء',
    'payment' => 'سداد',
    'purchase_cancel' => 'عكس شراء ملغى',
    'payment_cancel' => 'عكس سداد',
    _ => 'حركة حساب',
  };

  static Future<void> _pay(BuildContext context, Supplier supplier) async {
    final amount = TextEditingController();
    final notes = TextEditingController();
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
            builder: (ctx, setS) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AmountField(controller: amount, label: S.paidAmount),
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
                            await sl<SupplierService>().recordPayment(
                              session: context.read<AuthCubit>().state.session!,
                              supplierId: supplier.id,
                              amount: Money.parse(amount.text),
                              notes: notes.text,
                            );
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
                  child: const Text(S.save),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _delete(BuildContext context, Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المورد'),
        content: const Text(
          'يُحذف المورد فقط إن لم تكن له مشتريات أو رصيد مستحق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await sl<SupplierService>().delete(
        session: context.read<AuthCubit>().state.session!,
        id: supplier.id,
      );
      if (context.mounted) context.go('/suppliers');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
