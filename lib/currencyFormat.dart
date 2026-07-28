import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SharedPreferencesService.dart';

class CurrencyFormatter {
  static SharedPreferences? _preferences = SharedPreferencesService.preferences;

  /// 🔹 Get saved decimal places or fallback to 2
  static int _getDecimalPlaces() {
    return _preferences?.getInt('decimalplace') ?? 2;
  }

  /// 🔹 Get saved currency code or fallback to AED
  static String _getCurrencyCode() {
    return _preferences?.getString('currencycode') ?? 'AED';
  }

  /// 🔹 Public accessor for the saved currency code (needed by widget-based
  /// formatters that must know whether to render the Dirham glyph).
  static String getCurrencyCode() => _getCurrencyCode();

  /// 🔹 Symbol and formatted number kept separate, for callers that need to
  /// style the currency symbol independently from the amount (e.g. to swap
  /// in the Dirham glyph for AED without affecting the amount's font).
  static ({String symbol, String number}) formatCurrencyParts(double amount) {
    final code = _getCurrencyCode();
    final format = _buildFormat(code);
    final symbol = format.currencySymbol;
    final number = NumberFormat(
      "#,##0.${'0' * _getDecimalPlaces()}",
    ).format(amount);
    return (symbol: symbol, number: number);
  }

  /// 🔹 Build NumberFormat safely
  static NumberFormat _buildFormat(String code, {int? decimals}) {
    final decimalDigits = decimals ?? _getDecimalPlaces();

    try {
      if (code == 'INR' || code == 'EUR' || code == 'USD' || code == 'PKR') {
        return NumberFormat.simpleCurrency(
          name: code,
          decimalDigits: decimalDigits,
        );
      } else {
        return NumberFormat.currency(
          locale: 'en',
          name: code,
          decimalDigits: decimalDigits,
        );
      }
    } catch (e) {
      return NumberFormat.currency(
        locale: 'en',
        name: 'AED',
        decimalDigits: decimalDigits,
      );
    }
  }

  /// 🔹 Format double
  static String formatCurrency_double(double amount) {
    final code = _getCurrencyCode();
    final format = _buildFormat(code);

    final symbol = format.currencySymbol;
    final number = NumberFormat("#,##0.${'0' * _getDecimalPlaces()}").format(amount);

    return "$symbol $number";
  }

  /// 🔹 Format int
  static String formatCurrency_int(int amount) {
    final code = _getCurrencyCode();
    final format = _buildFormat(code, decimals: 0);

    final symbol = format.currencySymbol;
    final number = NumberFormat("#,##0").format(amount);

    return "$symbol $number";
  }

  /// 🔹 Format from string (normal)
  static String formatCurrency_normal(String amount) {
    final code = _getCurrencyCode();
    int decimals = _getDecimalPlaces();

    // ✅ Clean string
    String cleaned = amount.trim();

    if (cleaned.isEmpty || cleaned.toLowerCase() == "null") {
      return "${_buildFormat(code).currencySymbol} 0.${'0' * decimals}";
    }

    // ✅ Split by "/" if unit exists
    String unit = "";
    if (cleaned.contains("/")) {
      final parts = cleaned.split("/");
      cleaned = parts[0]; // numeric part
      unit = "/${parts.sublist(1).join("/")}";
    }

    // ✅ Parse numeric part
    double parsed = double.tryParse(cleaned.replaceAll(",", "")) ?? 0.0;

    // ✅ Format number
    final number = NumberFormat("#,##0.${'0' * decimals}").format(parsed);

    // ✅ Attach symbol + unit
    final format = _buildFormat(code);
    return "${format.currencySymbol} $number$unit";
  }
}


