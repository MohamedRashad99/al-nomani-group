import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/cairo_date_range.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/expense_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/date_range_bar.dart';
import '../../shared/widgets/destructive_action_guard.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/searchable_select.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String _query = '';
  late CairoDateRange _range = CairoDateRange.preset(ReportPeriod.thisMonth);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.expenses,
      fab: session.can(AppPermission.expensesCreate)
          ? FloatingActionButton(
              onPressed: () => _edit(null),
              child: const Icon(Icons.add),
            )
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DateRangeBar(
              value: _range,
              onChanged: (range) => setState(() => _range = range),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: S.search,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Expense>>(
              stream: sl<ExpenseService>().watch(range: _range, query: _query),
              builder: (context, snap) {
                final items = snap.data ?? const <Expense>[];
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final summary = sl<ExpenseService>().summarize(items);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: StatCard(
                              label: 'إجمالي المصروفات',
                              child: MoneyText(summary.total),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatCard(
                              label: 'عدد المصروفات',
                              child: Text(ArabicFormat.number(summary.count)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(child: Text(S.empty))
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (_, index) {
                                final item = items[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      ExpenseCategory.byCode(item.category).label,
                                    ),
                                    subtitle: Text(
                                      '${ArabicFormat.transactionDate(item.occurredAt)} • ${ArabicFormat.transactionTime(item.occurredAt)}${item.note == null ? '' : '\n${item.note}'}',
                                    ),
                                    trailing: MoneyText(Money.parse(item.amount)),
                                    onTap: session.can(AppPermission.expensesUpdate)
                                        ? () => _edit(item)
                                        : () => _view(item),
                                    onLongPress:
                                        session.can(AppPermission.expensesDelete)
                                        ? () => _delete(item)
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
          ),
        ],
      ),
    );
  }

  Future<void> _view(Expense expense) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ExpenseCategory.byCode(expense.category).label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MoneyText(Money.parse(expense.amount)),
            const SizedBox(height: 8),
            Text(ArabicFormat.transactionDateTime(expense.occurredAt)),
            if (expense.note != null) ...[
              const SizedBox(height: 8),
              Text(expense.note!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(S.close),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Expense expense) async {
    await DestructiveActionGuard.run(
      context: context,
      title: 'حذف المصروف',
      message: 'سيتم إخفاء المصروف من القائمة. السجل يبقى للمراجعة.',
      confirmLabel: 'حذف',
      successMessage: 'تم حذف المصروف.',
      action: () async {
        await sl<ExpenseService>().delete(
          session: context.read<AuthCubit>().state.session!,
          id: expense.id,
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      },
    );
  }

  Future<void> _edit(Expense? expense) async {
    final amount = TextEditingController(
      text: expense == null ? '' : Money.parse(expense.amount).toDisplay(),
    );
    final note = TextEditingController(text: expense?.note ?? '');
    var category = expense?.category ?? ExpenseCategory.salary.code;
    var occurredAt = expense?.occurredAt ?? EgyptTime.nowUtc();
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
                  AmountField(controller: amount, label: 'المبلغ'),
                  SearchableSelectField<String>(
                    label: 'التصنيف',
                    required: true,
                    allowCustom: false,
                    value: category,
                    options: [
                      for (final item in ExpenseCategory.all)
                        SearchableOption(value: item.code, label: item.label),
                    ],
                    onChanged: (value) =>
                        setS(() => category = value ?? category),
                  ),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(labelText: S.notes),
                    maxLines: 2,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('التاريخ والوقت'),
                    subtitle: Text(ArabicFormat.transactionDateTime(occurredAt)),
                    trailing: const Icon(Icons.event),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: EgyptTime.toCairo(occurredAt),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (date == null || !ctx.mounted) return;
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(
                          EgyptTime.toCairo(occurredAt),
                        ),
                      );
                      final cairo = EgyptTime.toCairo(occurredAt);
                      final next = DateTime.utc(
                        date.year,
                        date.month,
                        date.day,
                        time?.hour ?? cairo.hour,
                        time?.minute ?? cairo.minute,
                      );
                      setS(() => occurredAt = EgyptTime.startOfDayCairo(next).add(
                        Duration(
                          hours: time?.hour ?? cairo.hour,
                          minutes: time?.minute ?? cairo.minute,
                        ),
                      ));
                    },
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: AppColors.danger)),
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
                                await sl<ExpenseService>().upsert(
                                  session: context
                                      .read<AuthCubit>()
                                      .state
                                      .session!,
                                  id: expense?.id,
                                  amount: Money.parse(amount.text),
                                  category: category,
                                  note: note.text,
                                  occurredAt: occurredAt,
                                );
                                await sl<SyncEngine>().maybeSyncAfterLocalWrite();
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
                    child: const Text(S.save),
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
