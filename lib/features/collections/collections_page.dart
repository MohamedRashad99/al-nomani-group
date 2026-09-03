import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/collection_service.dart';
import '../../features/app/app_alert_cubit.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/searchable_select.dart';
import '../../shared/widgets/transaction_audit_footer.dart';
import '../../shared/widgets/transaction_period_filter.dart';
import '../../shared/widgets/transaction_timestamp.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  TransactionPeriod _period = TransactionPeriod.all;

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
          final items = (snap.data ?? const <Collection>[])
              .where((c) => TransactionPeriodFilter.includes(c.collectedAt, _period))
              .toList();
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    for (final period in TransactionPeriod.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: FilterChip(
                          selected: _period == period,
                          label: Text(TransactionPeriodFilter.label(period)),
                          onSelected: (_) => setState(() => _period = period),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text(S.empty))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final c = items[i];
                          return ListTile(
                            title: MoneyText(Money.parse(c.amount)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ArabicFormat.paymentMethod(c.paymentMethod),
                                ),
                                TransactionTimestamp(dateTime: c.collectedAt),
                              ],
                            ),
                            onTap: () => _showDetails(context, c),
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

  static Future<void> _showDetails(
    BuildContext context,
    Collection collection,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.collections, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(S.collectionAmount),
              trailing: MoneyText(Money.parse(collection.amount)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(S.paymentMethod),
              trailing: Text(
                ArabicFormat.paymentMethod(collection.paymentMethod),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تاريخ التحصيل'),
              trailing: Text(
                ArabicFormat.transactionDateTime(collection.collectedAt),
              ),
            ),
            if ((collection.notes ?? '').trim().isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(S.notes),
                subtitle: Text(collection.notes!.trim()),
              ),
            TransactionAuditFooter(
              createdAt: collection.createdAt,
              updatedAt: collection.updatedAt,
              createdBy: collection.createdBy,
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _create(BuildContext context) async {
    final customers = await sl<CatalogService>().searchCustomers('');
    if (!context.mounted) return;
    String? customerId;
    String? customName;
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
                    allowCustom: true,
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
                    onChanged: (value) => setS(() {
                      customerId = value;
                      if (value != null) customName = null;
                    }),
                    onCustomText: (value) => setS(() {
                      customName = value;
                      if (value.isNotEmpty) customerId = null;
                    }),
                  ),
                  AmountField(
                    controller: amount,
                    label: S.collectionAmount,
                  ),
                  SearchableSelectField<String>(
                    label: S.paymentMethod,
                    required: true,
                    allowCustom: false,
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
                              await sl<AppBusyCubit>().guard(() async {
                                await sl<CollectionService>().record(
                                  session: session,
                                  customerId: resolvedId,
                                  amount: Money.parse(amount.text),
                                  paymentMethod: method,
                                  notes: notes.text,
                                );
                                await sl<SyncEngine>()
                                    .maybeSyncAfterLocalWrite();
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                sl<AppAlertCubit>().success(S.collectionSuccess);
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
