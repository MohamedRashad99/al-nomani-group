import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../domain/services/supplier_service.dart';
import '../../shared/widgets/money_text.dart';

enum SupplierRemovalKind {
  dismiss,
  delete,
  archive,
  settle,
  statement,
  openInvoice,
}

class SupplierRemovalChoice {
  const SupplierRemovalChoice._(this.kind, [this.purchaseId]);

  const SupplierRemovalChoice.dismiss() : this._(SupplierRemovalKind.dismiss);
  const SupplierRemovalChoice.delete() : this._(SupplierRemovalKind.delete);
  const SupplierRemovalChoice.archive() : this._(SupplierRemovalKind.archive);
  const SupplierRemovalChoice.settle() : this._(SupplierRemovalKind.settle);
  const SupplierRemovalChoice.statement()
      : this._(SupplierRemovalKind.statement);
  const SupplierRemovalChoice.openInvoice(String id)
      : this._(SupplierRemovalKind.openInvoice, id);

  final SupplierRemovalKind kind;
  final String? purchaseId;
}

Future<SupplierRemovalChoice> showSupplierRemovalDialog({
  required BuildContext context,
  required SupplierDeleteInspection inspection,
}) async {
  final choice = await showDialog<SupplierRemovalChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('إزالة ${inspection.supplierName}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: _SupplierRemovalBody(inspection: inspection),
        ),
      ),
      actionsAlignment: MainAxisAlignment.start,
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, const SupplierRemovalChoice.dismiss()),
          child: const Text(S.close),
        ),
        if (!inspection.canDelete) ...[
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, const SupplierRemovalChoice.statement()),
            child: const Text('كشف الحساب'),
          ),
          if (inspection.invoices.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, const SupplierRemovalChoice.settle()),
              child: const Text('تسوية'),
            ),
        ],
        if (inspection.canArchive)
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(ctx, const SupplierRemovalChoice.archive()),
            child: const Text('أرشفة'),
          ),
        if (inspection.canDelete)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () =>
                Navigator.pop(ctx, const SupplierRemovalChoice.delete()),
            child: const Text('حذف نهائي'),
          ),
      ],
    ),
  );
  return choice ?? const SupplierRemovalChoice.dismiss();
}

class _SupplierRemovalBody extends StatelessWidget {
  const _SupplierRemovalBody({required this.inspection});

  final SupplierDeleteInspection inspection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          inspection.summary,
          style: theme.textTheme.titleSmall?.copyWith(
            color: inspection.canDelete ? AppColors.darkGreen : AppColors.danger,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _CountLine(label: 'فواتير غير ملغاة', count: inspection.activePurchases),
        _CountLine(
          label: 'فواتير ملغاة (أرشيف)',
          count: inspection.archivedPurchases,
        ),
        if (!inspection.balance.isZero)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Expanded(child: Text('رصيد الحساب')),
                MoneyText(inspection.balance),
              ],
            ),
          ),
        if (inspection.invoices.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'الفواتير المرتبطة',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final invoice in inspection.invoices)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(invoice.title),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => Navigator.pop(
                context,
                SupplierRemovalChoice.openInvoice(invoice.id),
              ),
            ),
        ],
        const SizedBox(height: 12),
        const Text(
          'الخطوات المطلوبة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < inspection.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${ArabicFormat.number(i + 1)}. ${inspection.steps[i]}'),
          ),
        if (inspection.canArchive) ...[
          const SizedBox(height: 8),
          Text(
            'الأرشفة تخفي المورد من القائمة النشطة فقط. الفواتير والقيود والرصيد لا تُحذف ولا تُسوّى تلقائياً.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
        if (inspection.canDelete && inspection.archivedPurchases > 0) ...[
          const SizedBox(height: 8),
          Text(
            'ستبقى ${ArabicFormat.number(inspection.archivedPurchases)} فاتورة ملغاة في الأرشيف دون حذف بياناتها.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ],
    );
  }
}

class _CountLine extends StatelessWidget {
  const _CountLine({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            ArabicFormat.number(count),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: count > 0 ? AppColors.text : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
