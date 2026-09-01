import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../domain/models/sale_unit.dart';
import '../../domain/services/sale_unit_conversion.dart';
import 'amount_field.dart';
import 'money_text.dart';

/// Quantity entry for a sale line, with the product's own units.
///
/// The seller types packages or a fraction of one (250 جم of a 500 جم عبوة);
/// the sheet always returns the converted package quantity alongside what was
/// typed. Products without a meaningful sub unit show no selector.
Future<SaleQuantityBreakdown?> showUnitQuantitySheet({
  required BuildContext context,
  required String title,
  required SaleUnitConverter converter,
  required Quantity availablePackages,
  SaleQuantityBreakdown? initial,
}) {
  return showModalBottomSheet<SaleQuantityBreakdown>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _UnitQuantitySheet(
      title: title,
      converter: converter,
      availablePackages: availablePackages,
      initial: initial,
    ),
  );
}

class _UnitQuantitySheet extends StatefulWidget {
  const _UnitQuantitySheet({
    required this.title,
    required this.converter,
    required this.availablePackages,
    this.initial,
  });

  final String title;
  final SaleUnitConverter converter;
  final Quantity availablePackages;
  final SaleQuantityBreakdown? initial;

  @override
  State<_UnitQuantitySheet> createState() => _UnitQuantitySheetState();
}

class _UnitQuantitySheetState extends State<_UnitQuantitySheet> {
  late final List<SaleUnitOption> _options = widget.converter.options;
  late SaleUnitOption _option;
  late final TextEditingController _controller;
  SaleQuantityBreakdown? _preview;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _option = _options.firstWhere(
      (option) => option == initial?.option,
      orElse: () => _options.first,
    );
    _controller = TextEditingController(
      text: initial == null ? '' : initial.inputQuantity.toDisplay(),
    );
    _preview = _evaluate(_controller.text).breakdown;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SaleQuantityResult _evaluate(String raw) => widget.converter.evaluate(
    option: _option,
    rawInput: raw,
    availablePackages: widget.availablePackages,
  );

  void _refresh() {
    setState(() {
      _preview = _evaluate(_controller.text).breakdown;
      _error = null;
    });
  }

  void _selectOption(SaleUnitOption option) {
    if (option == _option) return;
    setState(() {
      _option = option;
      _preview = _evaluate(_controller.text).breakdown;
      _error = null;
    });
  }

  void _submit() {
    final result = _evaluate(_controller.text);
    final breakdown = result.breakdown;
    if (breakdown == null) {
      setState(() {
        _preview = null;
        _error = result.error;
      });
      return;
    }
    Navigator.pop(context, breakdown);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(widget.converter.availabilityLabel(widget.availablePackages)),
          if (widget.converter.hasSubUnits) ...[
            const SizedBox(height: 12),
            Text('وحدة البيع', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _options)
                  ChoiceChip(
                    selected: option == _option,
                    label: Text(option.label),
                    onSelected: (_) => _selectOption(option),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          AmountField(
            controller: _controller,
            label: _option.quantityLabel,
            autofocus: true,
            onChanged: (_) => _refresh(),
            onSubmitted: (_) => _submit(),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            _PreviewCard(preview: _preview!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(S.cancel),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _submit,
                child: const Text(S.confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final SaleQuantityBreakdown preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packages = preview.option.isPackage
        ? preview.packageLabel
        : '${preview.inputLabel} = ${preview.packageLabel}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(packages, style: theme.textTheme.bodyMedium)),
          Text('${S.total}: ', style: theme.textTheme.bodyMedium),
          MoneyText(preview.totalPrice, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
