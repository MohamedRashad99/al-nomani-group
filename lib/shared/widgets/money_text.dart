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
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.child,
    this.color,
  });
  final String label;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.headlineSmall,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
