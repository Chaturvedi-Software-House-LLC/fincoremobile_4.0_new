import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../SerialSelect.dart';
import '../constants.dart';

/// Fetches the company list directly, mirroring SerialSelect's own
/// fetchAllowedCompany -> (fallback) fetchCompany flow, so the quick
/// switcher works the very first time it's opened instead of depending on
/// a cache that only SerialSelect itself would otherwise populate.
Future<List<String>> _fetchCompaniesDirect(SharedPreferences prefs) async {
  final serialNo = prefs.getString('serial_no');
  final username = prefs.getString('username');
  if (serialNo == null || serialNo.isEmpty) return [];

  final headers = {
    'Authorization': 'Bearer $authTokenBase',
    'Content-Type': 'application/json',
  };

  List<dynamic> companyData = [];

  if (username != null && username.isNotEmpty) {
    try {
      final url = Uri.parse(
        '$BASE_URL_config/api/roles/allowed_companies?user_name=$username&serial_no=$serialNo',
      );
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) companyData = decoded;
      }
    } catch (_) {}
  }

  if (companyData.isEmpty) {
    try {
      final url = Uri.parse('$BASE_URL_config/api/admin/getCompany');
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({'serialno': serialNo}),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) companyData = decoded;
      }
    } catch (_) {}
  }

  final names = companyData
      .map((c) => (c['company_name'] ?? '').toString())
      .where((n) => n.isNotEmpty)
      .toList();

  if (names.isNotEmpty) {
    await prefs.setString('quick_switch_companies', jsonEncode(names));
  }

  return names;
}

/// Fast multi-company switcher - shows the companies under the user's
/// current serial (cached by SerialSelect the last time it loaded them, so
/// this normally opens instantly with no network call; if that cache is
/// missing - e.g. the very first time this is opened - it fetches the list
/// directly instead of falling back to the full SerialSelect screen) and
/// jumps straight to the tapped one via
/// `SerialSelect(autoSelectCompanyName: ...)`, which reuses the exact same
/// license/permission/role flow a manual full re-selection would use - just
/// without requiring the user to navigate back through SerialSelect's own
/// list to find and tap the company themselves.
Future<void> showQuickCompanySwitcher(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final currentCompany = prefs.getString('company_name') ?? '';
  final cachedJson = prefs.getString('quick_switch_companies');

  List<String> companies = [];
  if (cachedJson != null) {
    try {
      companies = (jsonDecode(cachedJson) as List).cast<String>();
    } catch (_) {
      companies = [];
    }
  }

  if (companies.length <= 1) {
    final loadingDialogShown = context.mounted;
    if (loadingDialogShown) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    List<String> fetched = [];
    try {
      fetched = await _fetchCompaniesDirect(prefs);
    } catch (_) {}

    if (loadingDialogShown && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (fetched.length > 1) {
      companies = fetched;
    } else {
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SerialSelect()),
      );
      return;
    }
  }

  if (!context.mounted) return;

  String companySearchQuery = '';

  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
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
                      "Switch Company",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (companies.length > 6)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      style: GoogleFonts.poppins(fontSize: 13.5),
                      onChanged: (value) {
                        setSheetState(() {
                          companySearchQuery = value.trim().toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search companies...',
                        hintStyle: GoogleFonts.poppins(fontSize: 13),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).brightness ==
                                Brightness.dark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: app_color.withOpacity(0.6),
                            width: 1.4,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: Builder(
                    builder: (context) {
                      final filteredCompanies = companySearchQuery.isEmpty
                          ? companies
                          : companies
                              .where((name) => name
                                  .toLowerCase()
                                  .contains(companySearchQuery))
                              .toList();

                      if (filteredCompanies.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No matching companies',
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        );
                      }

                      return ListView(
                        shrinkWrap: true,
                        children: [
                          for (final name in filteredCompanies)
                            ListTile(
                              onTap: () {
                                Navigator.pop(sheetContext);
                                if (name == currentCompany) return;
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SerialSelect(
                                        autoSelectCompanyName: name),
                                  ),
                                );
                              },
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: name == currentCompany
                                      ? app_color
                                      : app_color.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.business_rounded,
                                  size: 18,
                                  color: name == currentCompany
                                      ? Colors.white
                                      : app_color,
                                ),
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              trailing: name == currentCompany
                                  ? Icon(Icons.check_circle_rounded,
                                      color: app_color)
                                  : null,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}
