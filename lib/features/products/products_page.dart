import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/breakpoints.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/catalog_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/deletion_workflow_dialog.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/searchable_select.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.products,
      fab: session.can(AppPermission.productsCreate)
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
            child: StreamBuilder<List<Product>>(
              stream: sl<CatalogService>().watchProducts(_query),
              builder: (context, snap) {
                final items = snap.data ?? const <Product>[];
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) return const Center(child: Text(S.empty));
                if (Breakpoints.isPhone(context)) {
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
                          subtitle: Text(
                            [
                              p.sku,
                              if (p.packSize != null && p.packSize!.isNotEmpty)
                                p.packSize,
                              '${p.currentStock} ${p.unit}',
                            ].join(' • '),
                          ),
                          trailing: MoneyText(Money.parse(p.sellingPrice)),
                          onTap: session.can(AppPermission.productsUpdate)
                              ? () => _edit(p)
                              : null,
                        ),
                      );
                    },
                  );
                }
                return SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text(S.productName)),
                        DataColumn(label: Text(S.sku)),
                        DataColumn(label: Text(S.currentStock)),
                        DataColumn(label: Text(S.sellingPrice)),
                      ],
                      rows: [
                        for (final p in items)
                          DataRow(
                            onSelectChanged:
                                session.can(AppPermission.productsUpdate)
                                ? (_) => _edit(p)
                                : null,
                            cells: [
                              DataCell(Text(p.name)),
                              DataCell(Text(p.sku)),
                              DataCell(Text(p.currentStock)),
                              DataCell(MoneyText(Money.parse(p.sellingPrice))),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Product? product) async {
    final name = TextEditingController(text: product?.name ?? '');
    final sku = TextEditingController(text: product?.sku ?? '');
    final brand = TextEditingController(text: product?.brand ?? '');
    final purchase = TextEditingController(text: product?.purchasePrice ?? '');
    final sell = TextEditingController(text: product?.sellingPrice ?? '');
    final stock = TextEditingController(text: product?.currentStock ?? '');
    final min = TextEditingController(text: product?.minimumStock ?? '');
    final unit = TextEditingController(text: product?.unit ?? '');
    final packSize = TextEditingController(text: product?.packSize ?? '');
    var categoryId = product?.categoryId;
    final categories = CatalogCategories.all;
    if (!mounted) return;
    await showModalBottomSheet<bool>(
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
                    decoration: const InputDecoration(labelText: S.productName),
                  ),
                  TextField(
                    controller: sku,
                    decoration: const InputDecoration(labelText: S.sku),
                  ),
                  TextField(
                    controller: brand,
                    decoration: const InputDecoration(labelText: S.brand),
                  ),
                  AmountField(
                    controller: purchase,
                    label: S.purchasePrice,
                  ),
                  AmountField(
                    controller: sell,
                    label: S.sellingPrice,
                  ),
                  if (product == null)
                    AmountField(
                      controller: stock,
                      label: S.currentStock,
                    ),
                  AmountField(
                    controller: min,
                    label: S.minimumStock,
                  ),
                  SearchableSelectField<String?>(
                    label: S.category,
                    value: categoryId,
                    options: [
                      const SearchableOption(value: null, label: S.noCategory),
                      for (final category in categories)
                        SearchableOption(
                          value: category.id,
                          label: category.name,
                        ),
                    ],
                    onChanged: (v) => setS(() => categoryId = v),
                  ),
                  TextField(
                    controller: packSize,
                    decoration: const InputDecoration(labelText: S.packSize),
                  ),
                  TextField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: S.unit),
                  ),
                  const SizedBox(height: 12),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
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
                                await sl<CatalogService>().upsertProduct(
                                  session: context
                                      .read<AuthCubit>()
                                      .state
                                      .session!,
                                  id: product?.id,
                                  name: name.text,
                                  sku: sku.text,
                                  categoryId: categoryId,
                                  brand: brand.text,
                                  packSize: packSize.text,
                                  purchasePrice: Money.parse(
                                    purchase.text.isEmpty ? '0' : purchase.text,
                                  ),
                                  sellingPrice: Money.parse(
                                    sell.text.isEmpty ? '0' : sell.text,
                                  ),
                                  currentStock: Quantity.parse(
                                    stock.text.isEmpty ? '0' : stock.text,
                                  ),
                                  minimumStock: Quantity.parse(
                                    min.text.isEmpty ? '0' : min.text,
                                  ),
                                  unit: unit.text,
                                );
                                await sl<SyncEngine>()
                                    .maybeSyncAfterLocalWrite();
                              });
                              if (ctx.mounted) Navigator.pop(ctx, true);
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
                  if (product != null &&
                      context
                              .read<AuthCubit>()
                              .state
                              .session
                              ?.can(AppPermission.productsDelete) ==
                          true) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              try {
                                final report = await sl<CatalogService>()
                                    .inspectProduct(product.id);
                                if (!ctx.mounted) return;
                                final confirmed =
                                    await showDeletionWorkflowDialog(
                                      context: ctx,
                                      title: S.deleteProduct,
                                      report: report,
                                    );
                                if (confirmed != true) return;
                                setS(() {
                                  saving = true;
                                  error = null;
                                });
                                await sl<AppBusyCubit>().guard(() async {
                                  await sl<CatalogService>().deleteProduct(
                                    session: context
                                        .read<AuthCubit>()
                                        .state
                                        .session!,
                                    id: product.id,
                                  );
                                  await sl<SyncEngine>()
                                      .maybeSyncAfterLocalWrite();
                                });
                                if (ctx.mounted) Navigator.pop(ctx, true);
                              } catch (e) {
                                if (ctx.mounted) {
                                  setS(() {
                                    saving = false;
                                    error = e.toString();
                                  });
                                }
                              }
                            },
                      child: const Text(S.deleteProduct),
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
