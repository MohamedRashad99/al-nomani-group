import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/outstanding_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/searchable_select.dart';

enum _OutstandingMode { add, cash, setExact }

class OutstandingPage extends StatelessWidget {
  const OutstandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.outstanding,
      fab: session.can(AppPermission.outstandingCreate)
          ? FloatingActionButton(
              onPressed: () => _edit(context, null),
              child: const Icon(Icons.add),
            )
          : null,
      child: StreamBuilder<List<OutstandingRow>>(
        stream: sl<OutstandingService>().watchDue(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <OutstandingRow>[];
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final total = sl<OutstandingService>().totalDue(rows);
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: ListTile(
                  title: const Text(S.outstandingTotal),
                  subtitle: Text('${S.customersWithDebt}: ${rows.length}'),
                  trailing: MoneyText(total),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text(S.empty))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              title: Text(row.customer.name),
                              subtitle: Text(
                                [row.customer.phone, row.customer.area]
                                    .whereType<String>()
                                    .where((v) => v.isNotEmpty)
                                    .join(' • '),
                              ),
                              trailing: MoneyText(row.balance),
                              onTap: () => context.push(
                                '/customers/${row.customer.id}/statement',
                              ),
                              onLongPress:
                                  session.can(AppPermission.outstandingCreate)
                                  ? () => _edit(context, row)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, OutstandingRow? row) async {
    final rows = await sl<OutstandingService>().list();
    if (!context.mounted) return;
    String? customerId = row?.customer.id;
    var customName = row?.customer.name;
    var mode = row == null ? _OutstandingMode.add : _OutstandingMode.cash;
    final amount = TextEditingController();
    final cash = TextEditingController();
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
            builder: (ctx, setS) => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    S.outstanding,
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SearchableSelectField<String>(
                    label: S.customerName,
                    required: true,
                    allowCustom: true,
                    value: customerId,
                    options: [
                      for (final item in rows)
                        SearchableOption(
                          value: item.customer.id,
                          label: item.customer.name,
                          subtitle: item.balance.toDisplay(),
                          searchText:
                              '${item.customer.phone ?? ''} ${item.customer.area ?? ''}',
                        ),
                    ],
                    onChanged: (value) => setS(() {
                      customerId = value;
                      if (value != null) customName = null;
                    }),
                    onCustomText: (value) => setS(() {
                      customName = value;
                      if (value.isNotEmpty) customerId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  SearchableSelectField<_OutstandingMode>(
                    label: 'نوع الحركة',
                    required: true,
                    allowCustom: false,
                    value: mode,
                    options: const [
                      SearchableOption(
                        value: _OutstandingMode.add,
                        label: S.outstandingAdd,
                      ),
                      SearchableOption(
                        value: _OutstandingMode.cash,
                        label: S.outstandingCash,
                      ),
                      SearchableOption(
                        value: _OutstandingMode.setExact,
                        label: S.outstandingSet,
                      ),
                    ],
                    onChanged: (value) =>
                        setS(() => mode = value ?? _OutstandingMode.add),
                  ),
                  if (mode != _OutstandingMode.cash)
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: mode == _OutstandingMode.setExact
                            ? S.outstandingSet
                            : S.outstandingAdd,
                      ),
                    ),
                  TextField(
                    controller: cash,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: S.outstandingCashAmount,
                    ),
                  ),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: S.notes),
                  ),
                  const SizedBox(height: 8),
                  const Text(S.outstandingWarning),
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
                              final session = context
                                  .read<AuthCubit>()
                                  .state
                                  .session!;
                              final resolvedId = await sl<CatalogService>()
                                  .findOrCreateCustomer(
                                    session: session,
                                    id: customerId,
                                    name: customName,
                                  );
                              final deferred = _tryMoney(amount.text);
                              final cashPaid = _tryMoney(cash.text);
                              if (mode == _OutstandingMode.cash &&
                                  (cashPaid == null || !cashPaid.isPositive)) {
                                throw Exception(S.invalidAmount);
                              }
                              if (mode != _OutstandingMode.cash &&
                                  (deferred == null || !deferred.isPositive) &&
                                  (cashPaid == null || !cashPaid.isPositive)) {
                                throw Exception(S.invalidAmount);
                              }
                              await sl<AppBusyCubit>().guard(() async {
                                if (mode == _OutstandingMode.setExact &&
                                    deferred != null) {
                                  await sl<OutstandingService>().setTarget(
                                    session: session,
                                    customerId: resolvedId,
                                    target: deferred,
                                    notes: notes.text.isEmpty
                                        ? 'تعيين رصيد آجل'
                                        : notes.text,
                                  );
                                } else if (mode == _OutstandingMode.add &&
                                    deferred != null &&
                                    deferred.isPositive) {
                                  await sl<OutstandingService>().add(
                                    session: session,
                                    customerId: resolvedId,
                                    amount: deferred,
                                    notes: notes.text.isEmpty
                                        ? 'إضافة مبلغ آجل'
                                        : notes.text,
                                  );
                                }
                                if (cashPaid != null && cashPaid.isPositive) {
                                  await sl<OutstandingService>().collectCash(
                                    session: session,
                                    customerId: resolvedId,
                                    amount: cashPaid,
                                    notes: notes.text,
                                  );
                                }
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

  static Money? _tryMoney(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      return Money.parse(text);
    } catch (_) {
      return null;
    }
  }
}
