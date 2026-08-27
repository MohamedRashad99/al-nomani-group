import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../domain/services/entity_link_inspector.dart';
import 'money_text.dart';

Future<bool> showDeletionWorkflowDialog({
  required BuildContext context,
  required String title,
  required EntityLinkReport report,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  report.summary,
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                    color: report.canDelete
                        ? AppColors.darkGreen
                        : AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (!report.canDelete)
                  Text(
                    'لا يمكن حذف ${report.entityName} بسبب:',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  )
                else
                  const Text('ملخص الارتباطات التاريخية:'),
                const SizedBox(height: 8),
                _CountLine(
                  label: 'فواتير بيع نشطة',
                  count: report.activeSales,
                ),
                _CountLine(
                  label: 'فواتير بيع ملغاة (أرشيف)',
                  count: report.cancelledSales,
                ),
                if (report.purchasesNotApplicable)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'فواتير الشراء تخص الموردين وليست مرتبطة بالعميل.',
                    ),
                  )
                else ...[
                  _CountLine(
                    label: 'فواتير شراء نشطة',
                    count: report.activePurchases,
                  ),
                  _CountLine(
                    label: 'فواتير شراء ملغاة (أرشيف)',
                    count: report.cancelledPurchases,
                  ),
                ],
                _CountLine(label: 'تحصيلات / إيصالات', count: report.receipts),
                _CountLine(
                  label: 'قيود محاسبية',
                  count: report.accountEntries,
                ),
                _CountLine(
                  label: 'حركات مخزون',
                  count: report.inventoryMovements,
                ),
                _CountLine(label: 'مرتجعات', count: report.returns),
                if (!report.outstanding.isZero)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Expanded(child: Text('الرصيد الآجل المتبقي')),
                        MoneyText(report.outstanding),
                      ],
                    ),
                  ),
                if (report.activeSaleLinks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'فواتير البيع المرتبطة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final link in report.activeSaleLinks)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(link.title),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () {
                        Navigator.pop(ctx, false);
                        context.push(link.route);
                      },
                    ),
                ],
                if (report.activePurchaseLinks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'فواتير الشراء المرتبطة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final link in report.activePurchaseLinks)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(link.title),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () {
                        Navigator.pop(ctx, false);
                        context.push(link.route);
                      },
                    ),
                ],
                if (report.extraLinks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'صفحات ذات صلة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final link in report.extraLinks)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(link.title),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () {
                        Navigator.pop(ctx, false);
                        context.push(link.route);
                      },
                    ),
                ],
                if (!report.canDelete) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'الخطوات المطلوبة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < report.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${ArabicFormat.number(i + 1)}. ${report.steps[i]}',
                      ),
                    ),
                ],
                if (report.canDelete &&
                    (report.cancelledSales > 0 ||
                        report.cancelledPurchases > 0 ||
                        report.receipts > 0 ||
                        report.accountEntries > 0))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'السجلات الملغاة والتحصيلات والقيود تبقى في الأرشيف للحفاظ على المراجعة المحاسبية.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.close),
          ),
          if (report.canDelete)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(S.confirm),
            ),
        ],
      );
    },
  );
  return confirmed == true;
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
