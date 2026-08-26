import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import 'amount_field.dart';

Future<Quantity?> showQuantitySheet({
  required BuildContext context,
  required String title,
  String? helperText,
  Quantity? max,
}) {
  return showModalBottomSheet<Quantity>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _QuantitySheet(
      title: title,
      helperText: helperText,
      max: max,
    ),
  );
}

class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet({
    required this.title,
    this.helperText,
    this.max,
  });

  final String title;
  final String? helperText;
  final Quantity? max;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _allowed(Quantity quantity) {
    final max = widget.max;
    return max == null || quantity <= max;
  }

  void _submit(String raw) {
    try {
      final quantity = Quantity.parse(raw);
      if (!quantity.isPositive || !_allowed(quantity)) {
        throw const FormatException();
      }
      Navigator.pop(context, quantity);
    } catch (_) {
      setState(() => _error = S.invalidQty);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          if (widget.helperText != null) ...[
            const SizedBox(height: 6),
            Text(widget.helperText!),
          ],
          const SizedBox(height: 12),
          AmountField(
            controller: _controller,
            label: S.quantity,
            autofocus: true,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: _submit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                onPressed: () => _submit(_controller.text),
                child: const Text(S.confirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
