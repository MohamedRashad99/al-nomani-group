import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, this.style});
  final Money amount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${amount.toDisplay()} ${Money.currencySymbol}',
      style: style,
      textDirection: TextDirection.rtl,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.child,
    this.color,
    this.compact = false,
  });
  final String label;
  final Widget child;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color,
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              maxLines: compact ? 2 : 2,
              overflow: TextOverflow.ellipsis,
              style: compact
                  ? theme.textTheme.labelSmall
                  : theme.textTheme.labelLarge,
            ),
            SizedBox(height: compact ? 4 : 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: DefaultTextStyle.merge(
                style: compact
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.headlineSmall,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
