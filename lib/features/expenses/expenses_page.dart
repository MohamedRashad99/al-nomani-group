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
import '../../shared/widgets/summary_metrics.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String _query = '';
  late CairoDateRange _range = CairoDateRange.preset(ReportPeriod.thisMonth);
  late final Stream<List<Expense>> _expenses = sl<ExpenseService>().watch();

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
              stream: _expenses,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text(snap.error.toString()));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = sl<ExpenseService>().filter(
                  snap.data!,
                  range: _range,
                  query: _query,
                );
                final summary = sl<ExpenseService>().summarize(items);
                return Column(
                  children: [
                    if (session.isAdmin) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SummaryMetricsRow(
                          metrics: [
                            SummaryMetric(
                              label: 'إجمالي المصروفات',
                              value: MoneyText(summary.total),
                            ),
                            SummaryMetric(
                              label: 'عدد المصروفات',
                              value: Text(ArabicFormat.number(summary.count)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: items.isEmpty
                          ? const Center(child: Text(S.empty))
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (_, index) {
                                final item = items[index];
                                final canUpdate =
                                    session.can(AppPermission.expensesUpdate);
                                final canDelete =
                                    session.can(AppPermission.expensesDelete);
                                final note = item.note?.trim();
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: ListTile(
                                    isThreeLine: note != null && note.isNotEmpty,
                                    title: Text(
                                      ExpenseCategory.byCode(item.category).label,
                                    ),
                                    subtitle: Text(
                                      [
                                        '${ArabicFormat.transactionDate(item.occurredAt)} • ${ArabicFormat.transactionTime(item.occurredAt)}',
                                        if (note != null && note.isNotEmpty) note,
                                      ].join('\n'),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        MoneyText(Money.parse(item.amount)),
                                        if (canUpdate)
                                          IconButton(
                                            tooltip: S.edit,
                                            onPressed: () => _edit(item),
                                            icon: const Icon(Icons.edit_outlined),
                                          ),
                                        if (canDelete)
                                          IconButton(
                                            tooltip: 'حذف',
                                            onPressed: () => _delete(item),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: AppColors.danger,
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: canUpdate
                                        ? () => _edit(item)
                                        : () => _view(item),
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
    final session = context.read<AuthCubit>().state.session;
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
            if (expense.note != null && expense.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(expense.note!),
            ],
          ],
        ),
        actions: [
          if (session?.can(AppPermission.expensesUpdate) == true)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _edit(expense);
              },
              child: const Text(S.edit),
            ),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ExpenseEditorSheet(
        expense: expense,
        onDelete: expense == null
            ? null
            : () async {
                Navigator.pop(ctx);
                await _delete(expense);
              },
      ),
    );
  }
}

class _ExpenseEditorSheet extends StatefulWidget {
  const _ExpenseEditorSheet({required this.expense, this.onDelete});

  final Expense? expense;
  final Future<void> Function()? onDelete;

  @override
  State<_ExpenseEditorSheet> createState() => _ExpenseEditorSheetState();
}

class _ExpenseEditorSheetState extends State<_ExpenseEditorSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _category;
  late DateTime _occurredAt;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _amount = TextEditingController(
      text: expense == null ? '' : Money.parse(expense.amount).toDisplay(),
    );
    _note = TextEditingController(text: expense?.note ?? '');
    _category = expense?.category ?? ExpenseCategory.salary.code;
    _occurredAt = expense?.occurredAt ?? EgyptTime.nowUtc();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = context.read<AuthCubit>().state.session!;
      await sl<AppBusyCubit>().guard(() async {
        await sl<ExpenseService>().upsert(
          session: session,
          id: widget.expense?.id,
          amount: Money.parse(_amount.text),
          category: _category,
          note: _note.text,
          occurredAt: _occurredAt,
        );
        await sl<SyncEngine>().maybeSyncAfterLocalWrite();
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pickOccurredAt() async {
    final cairo = EgyptTime.toCairo(_occurredAt);
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(cairo.year, cairo.month, cairo.day),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cairo.hour, minute: cairo.minute),
    );
    if (!mounted) return;
    setState(() {
      _occurredAt = EgyptTime.fromCairo(
        year: date.year,
        month: date.month,
        day: date.day,
        hour: time?.hour ?? cairo.hour,
        minute: time?.minute ?? cairo.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session!;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.expense == null ? 'مصروف جديد' : S.edit,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            AmountField(controller: _amount, label: 'المبلغ'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: S.category),
              items: [
                for (final item in ExpenseCategory.all)
                  DropdownMenuItem(value: item.code, child: Text(item.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: S.notes,
                hintText: 'اكتب وصف المصروف هنا',
                alignLabelWithHint: true,
              ),
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('التاريخ والوقت'),
              subtitle: Text(ArabicFormat.transactionDateTime(_occurredAt)),
              trailing: const Icon(Icons.event),
              onTap: _saving ? null : _pickOccurredAt,
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(S.save),
            ),
            if (widget.expense != null &&
                widget.onDelete != null &&
                session.can(AppPermission.expensesDelete)) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : widget.onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف المصروف'),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
