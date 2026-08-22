import 'package:flutter/material.dart';

class SearchableOption<T> {
  const SearchableOption({
    required this.value,
    required this.label,
    this.searchText,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? searchText;
  final String? subtitle;

  String get haystack =>
      '${searchText ?? ''} $label ${subtitle ?? ''}'.toLowerCase();
}

class SearchableSelectField<T> extends StatefulWidget {
  const SearchableSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.enabled = true,
    this.required = false,
    this.allowCustom = true,
    this.onCustomText,
    this.hint,
    this.prefixIcon,
  });

  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final List<SearchableOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final ValueChanged<String>? onCustomText;
  final bool enabled;
  final bool required;
  final bool allowCustom;

  @override
  State<SearchableSelectField<T>> createState() =>
      _SearchableSelectFieldState<T>();
}

class _SearchableSelectFieldState<T> extends State<SearchableSelectField<T>> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  String? _error;

  SearchableOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selected?.label ?? '');
    _focus = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant SearchableSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _selected != null) {
      _controller.text = _selected!.label;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocusChange);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focus.hasFocus) return;
    _commitText(_controller.text);
  }

  void _commitText(String raw) {
    final query = raw.trim();
    if (query.isEmpty) {
      widget.onChanged(null);
      widget.onCustomText?.call('');
      setState(() {
        _error = widget.required ? 'هذا الحقل مطلوب.' : null;
      });
      return;
    }
    final matches = _filtered(query).toList(growable: false);
    final exact = matches
        .where((option) => option.label == query)
        .toList(growable: false);
    if (exact.length == 1) {
      _select(exact.single);
      return;
    }
    if (matches.length == 1) {
      _select(matches.single);
      return;
    }
    if (widget.allowCustom) {
      setState(() => _error = null);
      widget.onChanged(null);
      widget.onCustomText?.call(query);
      return;
    }
    setState(() {
      _error = 'اختر قيمة من القائمة.';
      _controller.text = _selected?.label ?? '';
    });
  }

  Iterable<SearchableOption<T>> _filtered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options.where((option) => option.haystack.contains(q));
  }

  void _select(SearchableOption<T> option) {
    _controller.text = option.label;
    setState(() => _error = null);
    widget.onChanged(option.value);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<SearchableOption<T>>(
      textEditingController: _controller,
      focusNode: _focus,
      displayStringForOption: (option) => option.label,
      optionsBuilder: (value) => _filtered(value.text),
      onSelected: _select,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          onChanged: (value) {
            if (_error != null) setState(() => _error = null);
            if (widget.allowCustom) {
              widget.onCustomText?.call(value.trim());
              if (widget.value != null) widget.onChanged(null);
            }
          },
          onSubmitted: _commitText,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint ?? 'اكتب للبحث أو افتح القائمة',
            prefixIcon: Icon(widget.prefixIcon ?? Icons.search),
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: 'فتح القائمة',
              onPressed: !widget.enabled
                  ? null
                  : () {
                      focusNode.requestFocus();
                      controller.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: controller.text.length,
                      );
                    },
              icon: const Icon(Icons.arrow_drop_down),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 280),
              child: options.isEmpty
                  ? const ListTile(title: Text('لا توجد نتائج مطابقة'))
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option.label),
                          subtitle: option.subtitle == null
                              ? null
                              : Text(option.subtitle!),
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
