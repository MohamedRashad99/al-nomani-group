import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/remote/erp_store.dart';
import 'transaction_timestamp.dart';

/// Audit metadata rendered at the bottom of transaction detail views.
class TransactionAuditFooter extends StatelessWidget {
  const TransactionAuditFooter({
    super.key,
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
  });

  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;

  bool get _showUpdated {
    final updated = updatedAt;
    if (updated == null) return false;
    return updated.difference(createdAt).inSeconds.abs() > 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text(
          'سجل العملية',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _AuditRow(
          label: 'تاريخ الإنشاء',
          child: TransactionTimestamp(
            dateTime: createdAt,
            style: TransactionTimestampStyle.stacked,
          ),
        ),
        if (createdBy != null && createdBy!.isNotEmpty)
          _AuditRow(
            label: 'أنشأها',
            child: _UserLabel(userId: createdBy!),
          ),
        if (_showUpdated)
          _AuditRow(
            label: 'آخر تحديث',
            child: TransactionTimestamp(
              dateTime: updatedAt!,
              style: TransactionTimestampStyle.stacked,
            ),
          ),
        if (cancelledAt != null) ...[
          const SizedBox(height: 8),
          _AuditRow(
            label: 'تاريخ الإلغاء',
            child: TransactionTimestamp(
              dateTime: cancelledAt!,
              style: TransactionTimestampStyle.stacked,
            ),
          ),
          if (cancelledBy != null && cancelledBy!.isNotEmpty)
            _AuditRow(
              label: 'ألغاها',
              child: _UserLabel(userId: cancelledBy!),
            ),
          if (cancelReason != null && cancelReason!.trim().isNotEmpty)
            _AuditRow(
              label: 'سبب الإلغاء',
              child: Text(cancelReason!.trim()),
            ),
        ],
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _UserLabel extends StatelessWidget {
  const _UserLabel({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: sl<ErpStore>().getUser(userId),
      builder: (context, snapshot) {
        final name = snapshot.data?.displayName;
        if (name != null && name.isNotEmpty) return Text(name);
        return Text(ArabicFormat.compactId(userId));
      },
    );
  }
}
