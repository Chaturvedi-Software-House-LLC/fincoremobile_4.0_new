import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants.dart';

/// Drop-in replacement for `DropdownButtonFormField` for lists that can grow
/// large or dynamic (parties, items, ledgers, companies, roles, ...).
/// Renders like a normal form field; tapping it opens a bottom sheet with a
/// search box and a lazily-built list, so it stays smooth even with
/// thousands of entries.
class SearchableSelectorField<T> extends StatelessWidget {
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final String label;
  final String hintText;
  final bool enabled;
  final String? Function(T?)? validator;
  // Optional gradient prefix icon, matching the look of EntryDropdownField /
  // the app's other entry-form fields (fillColor, rounded 18 border, gradient
  // icon chip) so a searchable field doesn't stand out from its siblings.
  final IconData? icon;
  final List<Color> iconGradient;
  // When false, skips the InputDecorator box (fill/border/floating label)
  // entirely and just renders text + a chevron - for call sites that are
  // already wrapped in their own tinted pill/container (e.g. Items.dart's
  // and Party.dart's compact header dropdowns), matching the flat look the
  // plain DropdownButton used to have there instead of nesting two boxes.
  final bool decorated;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final IconData trailingIcon;
  // Style overrides so a converted field can match whatever sibling field
  // it sits next to (the app has more than one "compact field" convention -
  // e.g. EntryFormField's 18-radius themed fill vs the flatter 14-radius
  // grey.shade100 fill used by amount fields) - defaults mirror
  // EntryDropdownField/EntryFormField, the most common convention.
  final double borderRadius;
  final Color? fillColor;
  final bool filled;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry iconMargin;

  const SearchableSelectorField({
    super.key,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.label = '',
    this.hintText = 'Select...',
    this.enabled = true,
    this.validator,
    this.icon,
    this.iconGradient = const [Colors.purpleAccent, Colors.deepPurple],
    this.decorated = true,
    this.textStyle,
    this.hintStyle,
    this.trailingIcon = Icons.arrow_drop_down,
    this.borderRadius = 18,
    this.fillColor,
    this.filled = true,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 14,
    ),
    this.iconMargin = const EdgeInsets.all(6),
  });

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SearchablePickerSheet<T>(
        items: items,
        itemLabel: itemLabel,
        title: label.isNotEmpty ? label : hintText,
        currentValue: value,
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    // Guards against a caller's `value` not actually being a member of
    // `items` yet (e.g. a `dynamic`-typed field still holding its initial
    // placeholder while the real list is still loading) - itemLabel can
    // throw in that case (e.g. indexing into a Map field on a plain String),
    // which would otherwise crash the whole screen before data ever loads.
    String text = '';
    if (value != null) {
      try {
        text = itemLabel(value as T);
      } catch (_) {
        text = '';
      }
    }

    if (!decorated) {
      return InkWell(
        onTap: enabled ? () => _openPicker(context) : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.isEmpty ? hintText : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.isEmpty
                    ? (hintStyle ??
                          TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).hintColor,
                          ))
                    : (textStyle ??
                          TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface,
                          )),
              ),
            ),
            Icon(
              trailingIcon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      );
    }

    return FormField<T>(
      initialValue: value,
      validator: validator,
      builder: (state) {
        return InkWell(
          onTap: enabled
              ? () async {
                  await _openPicker(context);
                  state.didChange(value);
                }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              filled: filled,
              fillColor: !filled
                  ? null
                  : (fillColor ??
                        Theme.of(context).inputDecorationTheme.fillColor ??
                        Theme.of(context).cardColor.withValues(alpha: 0.95)),
              labelText: label.isNotEmpty ? label : null,
              labelStyle: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              prefixIcon: icon == null
                  ? null
                  : Container(
                      margin: iconMargin,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: iconGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
              suffixIcon: const Icon(Icons.arrow_drop_down),
              errorText: state.errorText,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(borderRadius),
                borderSide: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(borderRadius),
                borderSide: BorderSide(color: app_color, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(borderRadius),
                borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              contentPadding: contentPadding,
            ),
            child: Text(
              text.isEmpty ? hintText : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 14.5,
                color: text.isEmpty
                    ? Theme.of(context).hintColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchablePickerSheet<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) itemLabel;
  final String title;
  final T? currentValue;

  const _SearchablePickerSheet({
    required this.items,
    required this.itemLabel,
    required this.title,
    required this.currentValue,
  });

  @override
  State<_SearchablePickerSheet<T>> createState() =>
      _SearchablePickerSheetState<T>();
}

class _SearchablePickerSheetState<T> extends State<_SearchablePickerSheet<T>> {
  late List<T> _filtered;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.items
          : widget.items
                .where((e) => widget.itemLabel(e).toLowerCase().contains(q))
                .toList();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _controller.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No matches found',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final item = _filtered[i];
                          final label = widget.itemLabel(item);
                          String? currentLabel;
                          if (widget.currentValue != null) {
                            try {
                              currentLabel = widget.itemLabel(
                                widget.currentValue as T,
                              );
                            } catch (_) {
                              currentLabel = null;
                            }
                          }
                          final isSelected = currentLabel == label;
                          return ListTile(
                            title: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: app_color,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, item),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience helper for screens that just want a searchable bottom-sheet
/// picker without a form field wrapper (e.g. a plain "tap to select" row).
/// Returns the selected item, or null if the sheet was dismissed.
Future<T?> showSearchablePicker<T>(
  BuildContext context, {
  required List<T> items,
  required String Function(T) itemLabel,
  required String title,
  T? currentValue,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _SearchablePickerSheet<T>(
      items: items,
      itemLabel: itemLabel,
      title: title,
      currentValue: currentValue,
    ),
  );
}
