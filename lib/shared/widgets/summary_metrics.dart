import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/breakpoints.dart';
import '../../domain/services/catalog_service.dart';
import 'money_text.dart';

class SummaryMetric {
  const SummaryMetric({required this.label, required this.value});

  final String label;
  final Widget value;
}

/// One Card with purchase / selling / profit side-by-side on narrow screens.
class FinancialSummaryCard extends StatelessWidget {
  const FinancialSummaryCard({
    super.key,
    required this.purchaseValue,
    required this.sellingValue,
    required this.profit,
    required this.marginPercent,
    this.compact = false,
  });

  final Money purchaseValue;
  final Money sellingValue;
  final Money profit;
  final double marginPercent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final margin = marginPercent == marginPercent.roundToDouble()
        ? marginPercent.toStringAsFixed(0)
        : marginPercent.toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 16,
          vertical: compact ? 8 : 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: _FinancialCell(
                compact: compact,
                label: S.totalPurchaseValue,
                value: MoneyText(purchaseValue),
              ),
            ),
            _Divider(compact: compact),
            Expanded(
              child: _FinancialCell(
                compact: compact,
                label: S.totalSellingValue,
                value: MoneyText(sellingValue),
              ),
            ),
            _Divider(compact: compact),
            Expanded(
              child: _FinancialCell(
                compact: compact,
                label: S.expectedProfitMargin,
                value: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoneyText(profit),
                    Text(
                      '$margin٪',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12),
      child: SizedBox(
        height: compact ? 36 : 48,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).dividerColor,
        ),
      ),
    );
  }
}

class _FinancialCell extends StatelessWidget {
  const _FinancialCell({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final Widget value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: compact
              ? theme.textTheme.labelSmall
              : theme.textTheme.labelLarge,
        ),
        SizedBox(height: compact ? 4 : 8),
        FittedBox(fit: BoxFit.scaleDown, child: value),
      ],
    );
  }
}

/// Desktop: separate StatCards. Mobile (< 600px): one row of compact tiles.
class SummaryMetricsRow extends StatelessWidget {
  const SummaryMetricsRow({
    super.key,
    required this.metrics,
    this.cardWidth = 220,
  });

  final List<SummaryMetric> metrics;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final narrow = Breakpoints.isNarrow(context);
    if (!narrow) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final metric in metrics)
            SizedBox(
              width: cardWidth,
              child: StatCard(label: metric.label, child: metric.value),
            ),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    height: 36,
                    child: VerticalDivider(width: 1, thickness: 1),
                  ),
                ),
              Expanded(
                child: _FinancialCell(
                  compact: true,
                  label: metrics[i].label,
                  value: metrics[i].value,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProductCatalogSummaryBar extends StatelessWidget {
  const ProductCatalogSummaryBar({super.key, required this.summary});

  final ProductValueSummary summary;

  @override
  Widget build(BuildContext context) {
    final narrow = Breakpoints.isNarrow(context);
    if (!narrow) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 220,
            child: StatCard(
              label: S.totalProducts,
              child: Text('${summary.totalProducts}'),
            ),
          ),
          SizedBox(
            width: 220,
            child: StatCard(
              label: S.totalPurchaseValue,
              child: MoneyText(summary.purchaseValue),
            ),
          ),
          SizedBox(
            width: 220,
            child: StatCard(
              label: S.totalSellingValue,
              child: MoneyText(summary.sellingValue),
            ),
          ),
          SizedBox(
            width: 220,
            child: StatCard(
              label: S.expectedProfitMargin,
              child: MoneyText(summary.expectedProfit),
            ),
          ),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: StatCard(
              compact: true,
              label: S.totalProducts,
              child: Text('${summary.totalProducts}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: FinancialSummaryCard(
              compact: true,
              purchaseValue: summary.purchaseValue,
              sellingValue: summary.sellingValue,
              profit: summary.expectedProfit,
              marginPercent: summary.profitMarginPercent,
            ),
          ),
        ],
      ),
    );
  }
}
