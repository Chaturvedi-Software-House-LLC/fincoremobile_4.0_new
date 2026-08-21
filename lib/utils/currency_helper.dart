import 'package:FincoreGo/Settings.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> checkCurrencyMismatch(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final userCurrency = prefs.getString('currencycode') ?? "AED";
  final baseCurrency = prefs.getString('base_currency');

  // `base_currency` is written as an empty string (not `null`) for a
  // tally-oauth-only session - tally-api has no Company-master sync yet,
  // so this field is genuinely unknown, not "same as the app's currency".
  // Treating "" as a real mismatch produced a false-positive warning with
  // an empty currency code: "doesn't match ... base currency ()."
  if (baseCurrency == null || baseCurrency.isEmpty) return;

  if (userCurrency != baseCurrency) {
    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 6), // 👈 stays longer now
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "App currency ($userCurrency) doesn’t match your Tally company’s base currency ($baseCurrency). Please review or change your settings.",
                style:  TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Settings()));
              },
              child: Text(
                "Change",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
