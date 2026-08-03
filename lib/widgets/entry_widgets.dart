import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:image/image.dart' as img;
import '../constants.dart';
import '../currencyFormat.dart';

// ─── Section Header ──────────────────────────────────────────────
class EntrySection extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  const EntrySection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.iconGradient = const [Colors.teal, Colors.green],
    this.trailing,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: iconGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: iconGradient.first.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Modern Form Field ───────────────────────────────────────────
class EntryFormField extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> iconGradient;
  final TextEditingController? controller;
  final bool readOnly;
  final bool enabled;
  final bool enableInteractiveSelection;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;

  const EntryFormField({
    super.key,
    required this.label,
    required this.icon,
    this.iconGradient = const [Colors.teal, Colors.tealAccent],
    this.controller,
    this.readOnly = false,
    this.enabled = true,
    this.enableInteractiveSelection = true,
    this.onTap,
    this.onChanged,
    this.errorText,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabledFill = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Colors.grey.shade100;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        enabled: enabled,
        enableInteractiveSelection: enableInteractiveSelection && !readOnly,
        onTap: onTap,
        onChanged: onChanged,
        keyboardType: keyboardType,
        validator: validator,
        maxLines: maxLines,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: enabled
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          errorText: errorText,
          filled: true,
          fillColor: enabled
              ? (Theme.of(context).inputDecorationTheme.fillColor ??
                    Theme.of(context).cardColor.withValues(alpha: 0.95))
              : disabledFill,
          prefixIcon: Container(
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: enabled
                    ? iconGradient
                    : [Colors.grey, Colors.grey.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          suffixIcon: suffixIcon,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: app_color, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

// ─── Modern Dropdown Field ───────────────────────────────────────
class EntryDropdownField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> iconGradient;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool locked;
  final String? hintText;

  const EntryDropdownField({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    this.iconGradient = const [Colors.purpleAccent, Colors.deepPurple],
    this.value,
    this.onChanged,
    this.locked = false,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: IgnorePointer(
        ignoring: locked,
        child: Opacity(
          opacity: locked ? 0.7 : 1,
          child: DropdownButtonFormField<T>(
            isExpanded: true,
            initialValue: value,
            items: items,
            onChanged: locked ? null : onChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: locked
                  ? (isDark
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Colors.grey.shade100)
                  : (Theme.of(context).inputDecorationTheme.fillColor ??
                        Theme.of(context).cardColor.withValues(alpha: 0.95)),
              labelText: label,
              labelStyle: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: locked
                        ? [Colors.grey, Colors.grey.shade600]
                        : iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  locked ? Icons.lock_outline : icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: app_color, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
            hint: Text(
              hintText ?? label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Item Card for line items list ───────────────────────────────
class EntryItemCard extends StatelessWidget {
  final String itemName;
  final String quantity;
  final String rate;
  final String amount;
  final String? unit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  // When true, the qty stepper is disabled (shows a lock icon instead of
  // +/- controls) - used for meter-reading items whose quantity is
  // derived from the start/end reading, not manually editable.
  final bool quantityLocked;
  // Override the plain rate/amount Text with a currency-symbol-aware
  // widget (renders the Dirham glyph for AED) - rate/amount stay as
  // plain strings for callers that don't need this (e.g. legacy screens
  // not yet converted).
  final Widget? rateWidget;
  final Widget? amountWidget;

  const EntryItemCard({
    super.key,
    required this.itemName,
    required this.quantity,
    required this.rate,
    required this.amount,
    this.unit,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    this.onTap,
    this.quantityLocked = false,
    this.rateWidget,
    this.amountWidget,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dismissible(
      key: UniqueKey(),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: app_color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      color: app_color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      itemName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Qty stepper
                  _QtyControl(
                    quantity: quantity,
                    onIncrement: onIncrement,
                    onDecrement: onDecrement,
                    locked: quantityLocked,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: rateWidget != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Rate: ',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                rateWidget!,
                              ],
                            )
                          : Text(
                              'Rate: $rate',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.right,
                            ),
                    ),
                  ),
                ],
              ),
              if (unit != null && unit!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          unit!,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child:
                        amountWidget ??
                        Text(
                          amount,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: app_color,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final String quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool locked;

  const _QtyControl({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: locked ? null : onDecrement,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(10),
            ),
            child: Container(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.remove,
                size: 18,
                color: locked ? Colors.grey.shade400 : Colors.redAccent,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locked) ...[
                  Icon(Icons.lock, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                ],
                Text(
                  quantity,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: locked ? null : onIncrement,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(10),
            ),
            child: Container(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.add,
                size: 18,
                color: locked ? Colors.grey.shade400 : app_color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Modern Save Button ──────────────────────────────────────────
class EntrySaveButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const EntrySaveButton({
    super.key,
    this.label = 'Save Entry',
    this.icon = Icons.check_circle_outline,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? app_color : Colors.grey.shade400,
            foregroundColor: Colors.white,
            elevation: enabled ? 4 : 0,
            shadowColor: app_color.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Info Banner ─────────────────────────────────────────────────
class EntryInfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;

  const EntryInfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bannerColor = color ?? app_color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bannerColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: bannerColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Total Bar (for bottom of forms) ─────────────────────────────
class EntryTotalBar extends StatelessWidget {
  final String label;
  final String value;
  final String? currencySymbol;
  final String? currencyCode;

  const EntryTotalBar({
    super.key,
    this.label = 'Total',
    required this.value,
    this.currencySymbol,
    this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2332), const Color(0xFF0D1B2A)]
              : [Colors.white, const Color(0xFFF8FAFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: app_color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: app_color.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: app_color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: app_color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          // Expanded + right-aligned so an unusually long amount (e.g. a
          // huge bulk-delivery quantity) wraps onto a second line instead
          // of overflowing off the right edge of the card.
          Expanded(
            child: currencySymbol != null
                ? currencyAmountText(
                    currencyCode: currencyCode ?? 'AED',
                    symbol: currencySymbol!,
                    amountText: value,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: app_color,
                    ),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: app_color,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Modern AppBar for entry screens ─────────────────────────────
PreferredSizeWidget entryAppBar({
  required BuildContext context,
  required String title,
  required VoidCallback onBack,
  List<Widget>? actions,
}) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(56),
    child: AppBar(
      backgroundColor: app_color,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white,
          size: 20,
        ),
        onPressed: onBack,
      ),
      centerTitle: true,
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      actions: actions,
    ),
  );
}

// ─── Ledger Item Card ────────────────────────────────────────────
class EntryLedgerCard extends StatelessWidget {
  final String ledgerName;
  final String amount;
  final VoidCallback onDelete;
  final Widget? amountWidget;

  const EntryLedgerCard({
    super.key,
    required this.ledgerName,
    required this.amount,
    required this.onDelete,
    this.amountWidget,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dismissible(
      key: UniqueKey(),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.account_balance_outlined,
                color: Colors.indigo,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ledgerName,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            amountWidget ??
                Text(
                  amount,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ─── Pending Entry Card ──────────────────────────────────────────
class PendingEntryCard extends StatelessWidget {
  final String voucherNo;
  final String date;
  final String? partyName;
  final String amount;
  final bool isSynced;
  final String? errorMessage;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final List<Widget>? expandedContent;

  const PendingEntryCard({
    super.key,
    required this.voucherNo,
    required this.date,
    this.partyName,
    required this.amount,
    this.isSynced = false,
    this.errorMessage,
    this.isExpanded = false,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onShare,
    this.expandedContent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : null,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: isExpanded ? 20 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              app_color,
                              app_color.withValues(alpha: 0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#$voucherNo',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (partyName != null && partyName!.isNotEmpty)
                              Text(
                                partyName!,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Builder(
                            builder: (context) {
                              final parsed =
                                  double.tryParse(
                                    amount.replaceAll(',', ''),
                                  ) ??
                                  0.0;
                              final parts = CurrencyFormatter.formatCurrencyParts(
                                parsed,
                              );
                              return currencyAmountText(
                                currencyCode:
                                    CurrencyFormatter.getCurrencyCode(),
                                symbol: parts.symbol,
                                amountText: parts.number,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: app_color,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSynced
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isSynced ? 'Synced' : 'Pending',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isSynced
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: app_color.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: app_color,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorMessage != null && errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isExpanded) ...[
              Divider(
                height: 1,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _metaChip(context, Icons.calendar_today_outlined, date),
                  ],
                ),
              ),
              if (expandedContent != null) ...expandedContent!,
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onEdit != null)
                      _actionButton(
                        context,
                        Icons.edit_outlined,
                        'Edit',
                        app_color,
                        onTap: onEdit!,
                      ),
                    if (onShare != null)
                      _actionButton(
                        context,
                        Icons.share_outlined,
                        'Share',
                        Colors.blue,
                        onTap: onShare!,
                      ),
                    if (onDelete != null)
                      _actionButton(
                        context,
                        Icons.delete_outline,
                        'Delete',
                        Colors.red,
                        onTap: onDelete!,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    IconData icon,
    String label,
    Color color, {
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Modern Search Bar for pending screens ───────────────────────
class EntrySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final VoidCallback? onClear;

  const EntrySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search...',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const searchRadius = BorderRadius.all(Radius.circular(18));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Colors.grey.shade50,
          borderRadius: searchRadius,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.poppins(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            prefixIcon: Icon(Icons.search_rounded, color: app_color, size: 22),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                      onClear?.call();
                    },
                  )
                : null,
            border: const OutlineInputBorder(
              borderRadius: searchRadius,
              borderSide: BorderSide.none,
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: searchRadius,
              borderSide: BorderSide.none,
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: searchRadius,
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── UniGas Direct-Print Animation ───────────────────────────────
// A full-screen animation of the ACTUAL generated document swiping up
// into a printer graphic, shown while a UniGas POS PDF (Delivery Note /
// Tax Invoice / Receipt) is handed straight to the OS print flow - no
// share sheet, no share button.
class _PrintingAnimationOverlay extends StatefulWidget {
  final Uint8List pdfBytes;

  const _PrintingAnimationOverlay({required this.pdfBytes});

  @override
  State<_PrintingAnimationOverlay> createState() =>
      _PrintingAnimationOverlayState();
}

class _PrintingAnimationOverlayState extends State<_PrintingAnimationOverlay>
    with SingleTickerProviderStateMixin {
  // Paper feed progress (0 -> 1, how much of the document has emerged).
  late final AnimationController _feedController;
  Uint8List? _pageImage;
  double? _pageAspectRatio;

  @override
  void initState() {
    super.initState();
    _feedController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _feedController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        });
      }
    });
    _renderPreview();
  }

  Future<void> _renderPreview() async {
    try {
      await for (final page in Printing.raster(
        widget.pdfBytes,
        pages: const [0],
        dpi: 160,
      )) {
        final png = await page.toPng();
        if (!mounted) return;
        setState(() {
          _pageImage = png;
          _pageAspectRatio = page.width / page.height;
        });
        break;
      }
    } catch (_) {
      // Fall back to just the printer body without a live paper preview.
    } finally {
      if (mounted) _feedController.forward();
    }
  }

  @override
  void dispose() {
    _feedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: _pageImage == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      'Preparing document...',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            // LayoutBuilder gives the SafeArea's own (notch/status-bar
            // excluded) constraints, so the printer graphic is placed
            // relative to the actual visible canvas instead of the raw
            // MediaQuery size - otherwise it can render too high and
            // overlap the status bar / device chrome.
            : LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  final slotTop = size.height * 0.14;

                  // Fit the document's width/height to whatever's left
                  // below the top instead of a fixed size, since UniGas
                  // receipts can be very tall (continuous-roll).
                  final aspectRatio = _pageAspectRatio ?? 0.34; // w / h
                  double paperWidth = size.width * 0.6;
                  double paperHeight = paperWidth / aspectRatio;
                  final maxPaperHeight = size.height - slotTop - 70;
                  if (paperHeight > maxPaperHeight) {
                    paperHeight = maxPaperHeight;
                    paperWidth = paperHeight * aspectRatio;
                  }

                  return AnimatedBuilder(
                    animation: _feedController,
                    builder: (context, child) {
                      final raw = _feedController.value.clamp(0.0, 1.0);
                      // Phase 1 (0 -> 0.65): the receipt grows out of the slot.
                      // Phase 2 (0.65 -> 1.0): once fully printed, it ejects -
                      // slides further down and out from under the printer.
                      final revealT = Curves.easeOutCubic.transform(
                        (raw / 0.65).clamp(0.0, 1.0),
                      );
                      final ejectRaw = ((raw - 0.65) / 0.35).clamp(0.0, 1.0);
                      final ejectT = Curves.easeIn.transform(ejectRaw);
                      // Eject upward off the top of the screen (past the
                      // printer) rather than sliding further down.
                      final ejectOffset = -ejectT * (size.height * 0.7);
                      final ejectOpacity =
                          1.0 -
                          Curves.easeIn.transform(
                            ((ejectRaw - 0.55) / 0.45).clamp(0.0, 1.0),
                          );

                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          // The real generated document: grows out from
                          // the top, then ejects (slides up and away)
                          // once fully printed.
                          Positioned(
                            top: slotTop + ejectOffset,
                            child: Opacity(
                              opacity: ejectOpacity,
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  heightFactor: revealT.clamp(0.001, 1.0),
                                  child: Container(
                                    width: paperWidth,
                                    height: paperHeight,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(6),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(6),
                                      ),
                                      child: Image.memory(
                                        _pageImage!,
                                        width: paperWidth,
                                        fit: BoxFit.fitWidth,
                                        alignment: Alignment.topCenter,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

/// Plays a full-screen "document grows out, then ejects upward" animation
/// using the ACTUAL generated PDF as the preview, then prints [pdfBytes].
///
/// On a Sunmi device, this goes straight to the built-in thermal printer
/// via its native SDK (sunmi_printer_plus) - no Android print dialog, no
/// "choose a printer" step for the user. Every PDF page is rasterized to
/// a bitmap and sent to the printer as-is, so the exact same invoice/
/// receipt/delivery-note layout already built elsewhere in the app is
/// reused untouched rather than re-implemented as raw print commands.
///
/// On any other device, or if the Sunmi print path fails for any reason
/// (service not bound, plugin error, etc.), this falls back to the
/// existing Android print framework flow (where the Sunmi's printer, or
/// any other registered print service/PDF viewer, is still selectable).
Future<void> printUniGasPdf(
  BuildContext context,
  Uint8List pdfBytes, {
  required String documentName,
}) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Printing',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) =>
        _PrintingAnimationOverlay(pdfBytes: pdfBytes),
  );

  final bool printedOnSunmi = await _tryPrintOnSunmiPrinter(pdfBytes);
  if (printedOnSunmi) return;

  await Printing.layoutPdf(
    onLayout: (format) async => pdfBytes,
    name: documentName,
  );
}

/// Attempts the direct-to-Sunmi print path. Returns true only if every
/// step (device check, printer status check, rasterizing, and sending
/// each page) completed without error - false triggers the Android print
/// dialog fallback in [printUniGasPdf].
Future<bool> _tryPrintOnSunmiPrinter(Uint8List pdfBytes) async {
  try {
    // Only even attempt this on an actual Sunmi device - on anything else
    // the native call would just fail anyway, and skipping it here avoids
    // that pointless delay before falling back.
    if (!kIsWeb && Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      if (!manufacturer.contains('sunmi')) return false;
    } else {
      return false;
    }

    // Confirms the printer service is actually bound/responding before
    // committing to this path - throws or returns null if the plugin/
    // service has an issue, which is treated the same as "not available".
    final status = await SunmiConfig.getStatus();
    if (status == null) return false;

    final int printerWidthPx = await detectThermalPrinterWidthPx();

    // 203 DPI matches standard thermal receipt printer resolution
    // (including the Sunmi V2 Plus's built-in printer).
    final pages = Printing.raster(pdfBytes, dpi: 203);
    await for (final page in pages) {
      final png = await page.toPng();
      await SunmiPrinter.printImage(
        fitToThermalPaperWidth(png, printerWidthPx),
        align: SunmiPrintAlign.CENTER,
      );
    }
    await SunmiPrinter.lineWrap(3);
    await SunmiPrinter.cutPaper();
    return true;
  } catch (e) {
    debugPrint(
      'SUNMI PRINT ERROR - falling back to Android print dialog: $e',
    );
    return false;
  }
}

// Sunmi's native SDK reports paper width via PrinterInfo.PAPER: "1" means
// 58mm paper (384 dots print head at 203 DPI), "0" means 80mm (576 dots).
// Falls back to 576 (80mm - confirmed against an actual deployed Sunmi V2
// Plus, measured with a ruler) if the query fails or returns something
// unexpected, since that's what the real hardware in the field has.
// Not underscore-prefixed (unlike its neighbors) so tests in test/ can
// call it directly to verify the branching without a real Sunmi device.
@visibleForTesting
Future<int> detectThermalPrinterWidthPx() async {
  try {
    final String? paper = await SunmiConfig.getPaper();
    if (paper?.trim() == '1') return 384;
    return 576;
  } catch (e) {
    debugPrint('SUNMI PAPER WIDTH QUERY ERROR - defaulting to 80mm: $e');
    return 576;
  }
}

// The receipt PDFs are laid out at 76mm (wider than a 58mm thermal paper,
// needed so the item table stays legible in the shared/exported PDF).
// Rasterizing that straight to the printer without resizing overflows its
// print head, silently clipping every row on the right instead of scaling
// to fit - this brings each page down to the printer's actual detected
// pixel width first, preserving aspect ratio.
@visibleForTesting
Uint8List fitToThermalPaperWidth(Uint8List png, int printerWidthPx) {
  final decoded = img.decodePng(png);
  if (decoded == null || decoded.width <= printerWidthPx) return png;

  final resized = img.copyResize(decoded, width: printerWidthPx);
  return Uint8List.fromList(img.encodePng(resized));
}

// ─── App-wide message banner ──────────────────────────────────────
// Replaces Fluttertoast across the app: Android's native Toast is capped
// at ~3.5s (LENGTH_LONG) with no way to extend it - too quick for a
// layman user to comfortably read. This renders into the ROOT overlay
// instead (so it's visible above any open dialog/modal bottom sheet),
// stays up for a duration we control, and has a manual close (X).
OverlayEntry? _appMessageOverlay;

void showAppMessage(
  BuildContext context,
  String message, {
  bool isError = true,
  int seconds = 3,
}) {
  if (!context.mounted) return;

  _appMessageOverlay?.remove();
  _appMessageOverlay = null;

  final Color bg = isError ? Colors.redAccent : Colors.teal;
  final IconData icon = isError
      ? Icons.error_outline
      : Icons.check_circle_outline;

  final OverlayState overlayState = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      left: 16,
      right: 16,
      // Clear the bottom nav bar + device safe-area inset, not just a
      // small fixed gap that ends up nearly touching the screen edge.
      bottom: 24 + MediaQuery.of(overlayContext).padding.bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_appMessageOverlay == entry) {
                    entry.remove();
                    _appMessageOverlay = null;
                  }
                },
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  _appMessageOverlay = entry;
  overlayState.insert(entry);

  Future.delayed(Duration(seconds: seconds), () {
    if (_appMessageOverlay == entry) {
      entry.remove();
      _appMessageOverlay = null;
    }
  });
}
