import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/services/outstanding_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/searchable_select.dart';

enum _OutstandingMode { add, reduce, setExact }

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
        stream: sl<OutstandingService>().watch(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <OutstandingRow>[];
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (rows.isEmpty) return const Center(child: Text(S.empty));
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(row.customer.name),
                  subtitle: Text(
                    [row.customer.phone, row.customer.area]
                        .whereType<String>()
                        .where((value) => value.isNotEmpty)
                        .join(' • '),
                  ),
                  trailing: MoneyText(row.balance),
                  onTap: () =>
                      context.push('/customers/${row.customer.id}/statement'),
                  onLongPress: session.can(AppPermission.outstandingCreate)
                      ? () => _edit(context, row)
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, OutstandingRow? row) async {
    final rows = await sl<OutstandingService>().list();
    if (!context.mounted) return;
    var customerId = row?.customer.id;
    var mode = _OutstandingMode.add;
    final amount = TextEditingController(
      text: row == null ? '' : row.balance.toStorage(),
    );
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
                    onChanged: (value) => setS(() => customerId = value),
                  ),
                  const SizedBox(height: 12),
                  SearchableSelectField<_OutstandingMode>(
                    label: 'نوع الحركة',
                    required: true,
                    value: mode,
                    options: const [
                      SearchableOption(
                        value: _OutstandingMode.add,
                        label: S.outstandingAdd,
                      ),
                      SearchableOption(
                        value: _OutstandingMode.reduce,
                        label: S.outstandingReduce,
                      ),
                      SearchableOption(
                        value: _OutstandingMode.setExact,
                        label: S.outstandingSet,
                      ),
                    ],
                    onChanged: (value) =>
                        setS(() => mode = value ?? _OutstandingMode.add),
                  ),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: S.balance),
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
                              if (customerId == null) {
                                throw Exception(S.selectCustomer);
                              }
                              final money = Money.parse(amount.text);
                              final session = context
                                  .read<AuthCubit>()
                                  .state
                                  .session!;
                              await sl<AppBusyCubit>().guard(() async {
                                switch (mode) {
                                  case _OutstandingMode.add:
                                    await sl<OutstandingService>().add(
                                      session: session,
                                      customerId: customerId!,
                                      amount: money,
                                      notes: notes.text,
                                    );
                                  case _OutstandingMode.reduce:
                                    await sl<OutstandingService>().reduce(
                                      session: session,
                                      customerId: customerId!,
                                      amount: money,
                                      notes: notes.text,
                                    );
                                  case _OutstandingMode.setExact:
                                    await sl<OutstandingService>().setTarget(
                                      session: session,
                                      customerId: customerId!,
                                      target: money,
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
}
