import 'package:flutter/material.dart';

import '../../core/utils/arabic_format.dart';

enum TransactionTimestampStyle { stacked, inline }

/// Shows a business timestamp in Egypt (Africa/Cairo) time.
class TransactionTimestamp extends StatelessWidget {
  const TransactionTimestamp({
    super.key,
    required this.dateTime,
    this.style = TransactionTimestampStyle.inline,
    this.textStyle,
    this.secondaryStyle,
  });

  final DateTime dateTime;
  final TransactionTimestampStyle style;
  final TextStyle? textStyle;
  final TextStyle? secondaryStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = textStyle ?? theme.textTheme.bodySmall;
    final secondary = secondaryStyle ??
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );

    if (style == TransactionTimestampStyle.inline) {
      return Text(
        ArabicFormat.transactionDateTime(dateTime),
        style: primary,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('التاريخ: ${ArabicFormat.transactionDate(dateTime)}', style: primary),
        Text('الوقت: ${ArabicFormat.transactionTime(dateTime)}', style: secondary),
      ],
    );
  }
}
