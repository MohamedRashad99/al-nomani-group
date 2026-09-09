import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';

import '../../domain/cairo_date_range.dart';

class DateRangeBar extends StatelessWidget {
  const DateRangeBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CairoDateRange value;
  final ValueChanged<CairoDateRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in ReportPeriod.values)
              if (period != ReportPeriod.custom)
                ChoiceChip(
                  label: Text(CairoDateRange.preset(period).label),
                  selected: value.period == period,
                  onSelected: (_) => onChanged(CairoDateRange.preset(period)),
                ),
            ChoiceChip(
              label: const Text('فترة مخصصة'),
              selected: value.period == ReportPeriod.custom,
              onSelected: (_) => _pickCustom(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${value.label}: ${EgyptTime.formatDate(value.startUtc)} → ${EgyptTime.formatDate(value.endInclusiveUtc)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: EgyptTime.toCairo(value.startUtc),
        end: EgyptTime.toCairo(value.endInclusiveUtc),
      ),
      helpText: 'اختر تاريخ البداية والنهاية',
    );
    if (picked == null) return;
    try {
      onChanged(
        CairoDateRange.custom(startDay: picked.start, endDay: picked.end),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}
