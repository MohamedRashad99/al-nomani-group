import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/collection_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/searchable_select.dart';

class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final canCreate =
        context.watch<AuthCubit>().state.session?.can(
          AppPermission.collectionsCreate,
        ) ==
        true;
    return AppScaffold(
      title: S.collections,
      fab: canCreate
          ? FloatingActionButton(
              onPressed: () => _create(context),
              child: const Icon(Icons.add),
            )
          : null,
      child: StreamBuilder<List<Collection>>(
        stream: sl<CollectionService>().watch(),
        builder: (context, snap) {
          final items = snap.data ?? const <Collection>[];
          if (!snap.hasData) {
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
                  '${ArabicFormat.paymentMethod(c.paymentMethod)} • ${ArabicFormat.dateTime(c.collectedAt)}',
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Future<void> _create(BuildContext context) async {
    final customers = await sl<CatalogService>().searchCustomers('');
    if (!context.mounted) return;
    String? customerId;
    var method = 'cash';
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
            builder: (ctx, setS) => SingleChildScrollView(
              child: Column(
                children: [
                  SearchableSelectField<String>(
                    label: S.customerName,
                    required: true,
                    value: customerId,
                    options: [
                      for (final customer in customers)
                        SearchableOption(
                          value: customer.id,
                          label: customer.name,
                          subtitle: customer.phone,
                          searchText:
                              '${customer.phone ?? ''} ${customer.area ?? ''}',
                        ),
                    ],
                    onChanged: (value) => setS(() => customerId = value),
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
                  SearchableSelectField<String>(
                    label: S.paymentMethod,
                    required: true,
                    value: method,
                    options: const [
                      SearchableOption(value: 'cash', label: S.cash),
                      SearchableOption(value: 'transfer', label: S.transfer),
                    ],
                    onChanged: (value) => setS(() => method = value ?? method),
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
                              if (customerId == null) {
                                throw Exception(S.selectCustomer);
                              }
                              await sl<AppBusyCubit>().guard(() async {
                                await sl<CollectionService>().record(
                                  session: context
                                      .read<AuthCubit>()
                                      .state
                                      .session!,
                                  customerId: customerId!,
                                  amount: Money.parse(amount.text),
                                  paymentMethod: method,
                                  notes: notes.text,
                                );
                                await sl<SyncEngine>()
                                    .maybeSyncAfterLocalWrite();
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(S.collectionSuccess),
                                  ),
                                );
                              }
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
