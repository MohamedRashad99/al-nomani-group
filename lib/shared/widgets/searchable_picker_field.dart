import 'package:flutter/material.dart';

typedef PickerDisplay<T> = String Function(T value);

/// A strict combobox: users can type to filter or open the full option list,
/// but persisted values always come from [options].
class SearchablePickerField<T extends Object> extends StatefulWidget {
  const SearchablePickerField({
    super.key,
    required this.options,
    required this.displayStringForOption,
    required this.onChanged,
    required this.label,
    this.value,
    this.searchHint,
    this.required = true,
    this.enabled = true,
    this.leadingBuilder,
  });

  final List<T> options;
  final PickerDisplay<T> displayStringForOption;
  final ValueChanged<T?> onChanged;
  final String label;
  final T? value;
  final String? searchHint;
  final bool required;
  final bool enabled;
  final Widget Function(T value)? leadingBuilder;

  @override
  State<SearchablePickerField<T>> createState() =>
      _SearchablePickerFieldState<T>();
}

class _SearchablePickerFieldState<T extends Object>
    extends State<SearchablePickerField<T>> {
  TextEditingController? _controller;
  T? _selected;
  bool _settingText = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.value;
  }

  @override
  void didUpdateWidget(covariant SearchablePickerField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _selected) {
      _select(widget.value, notify: false);
    }
  }

  void _attachController(TextEditingController controller) {
    if (identical(_controller, controller)) return;
    _controller?.removeListener(_handleTextChanged);
    _controller = controller;
    _controller!.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    if (_settingText || _controller == null) return;
    final selected = _selected;
    if (selected != null &&
        _controller!.text != widget.displayStringForOption(selected)) {
      _selected = null;
      widget.onChanged(null);
    }
  }

  void _select(T? value, {bool notify = true}) {
    _selected = value;
    final controller = _controller;
    if (controller != null) {
      _settingText = true;
      controller.text = value == null
          ? ''
          : widget.displayStringForOption(value);
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      _settingText = false;
    }
    if (notify) widget.onChanged(value);
    if (mounted) setState(() {});
  }

  Future<void> _openAllOptions() async {
    if (!widget.enabled) return;
    final selected = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PickerSheet<T>(
        options: widget.options,
        displayStringForOption: widget.displayStringForOption,
        searchHint: widget.searchHint ?? widget.label,
        leadingBuilder: widget.leadingBuilder,
      ),
    );
    if (selected != null) _select(selected);
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<T>(
      initialValue: TextEditingValue(
        text: _selected == null
            ? ''
            : widget.displayStringForOption(_selected as T),
      ),
      displayStringForOption: widget.displayStringForOption,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return widget.options;
        return widget.options.where(
          (option) => widget
              .displayStringForOption(option)
              .toLowerCase()
              .contains(query),
        );
      },
      onSelected: _select,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        _attachController(controller);
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.searchHint,
            suffixIcon: IconButton(
              tooltip: 'عرض الخيارات',
              onPressed: widget.enabled ? _openAllOptions : null,
              icon: const Icon(Icons.arrow_drop_down_rounded),
            ),
          ),
          validator: (_) {
            if (widget.required && _selected == null) {
              return 'اختر قيمة من القائمة.';
            }
            return null;
          },
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final values = options.toList(growable: false);
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 280,
                minWidth: 280,
                maxWidth: 440,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: values.length,
                itemBuilder: (context, index) {
                  final option = values[index];
                  return ListTile(
                    leading: widget.leadingBuilder?.call(option),
                    title: Text(widget.displayStringForOption(option)),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PickerSheet<T extends Object> extends StatefulWidget {
  const _PickerSheet({
    required this.options,
    required this.displayStringForOption,
    required this.searchHint,
    this.leadingBuilder,
  });

  final List<T> options;
  final PickerDisplay<T> displayStringForOption;
  final String searchHint;
  final Widget Function(T value)? leadingBuilder;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T extends Object> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final options = query.isEmpty
        ? widget.options
        : widget.options
              .where(
                (option) => widget
                    .displayStringForOption(option)
                    .toLowerCase()
                    .contains(query),
              )
              .toList(growable: false);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.searchHint,
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: options.isEmpty
                ? const Center(child: Text('لا توجد نتائج مطابقة.'))
                : ListView.builder(
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return ListTile(
                        leading: widget.leadingBuilder?.call(option),
                        title: Text(widget.displayStringForOption(option)),
                        onTap: () => Navigator.pop(context, option),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
