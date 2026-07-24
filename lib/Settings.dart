import 'package:FincoreGo/FastMovingInactiveItemsCriteria.dart';
import 'package:FincoreGo/widgets/entry_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'AgeingConfig.dart';
import 'constants.dart';
import 'Dashboard.dart';
import 'SerialSelect.dart';
import 'theme_controller.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'services/biometric_auth_service.dart';

class Settings extends StatefulWidget {
  Settings({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<Settings> with TickerProviderStateMixin {
  String groupvalue = 'AED';
  double vatValue = 0.0;
  int inactiveparties_days = 0;
  String dateRangeOption = 'Today';
  DateTime? customStartDate;
  DateTime? customEndDate;
  int? decimal = 1;
  String sort = 'Default';
  bool _canCurrency = true,
      _canAmtDecimals = true,
      _canVatPerc = true,
      _canInactivePDays = true,
      _canSortType = true,
      _canDefDateRange = true,
      _canAgeingConfig = true,
      _canFastSlowInactiveItem = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricLabel = 'Biometric';
  final TextEditingController vatController = TextEditingController();
  final TextEditingController inactivedaysController = TextEditingController();

  final GlobalKey<FormState> _vatFormkey = GlobalKey<FormState>();
  final GlobalKey<FormState> _inactivepartydaysFormkey = GlobalKey<FormState>();

  late GlobalKey<ScaffoldState> _scaffoldMessengerKey;
  late SharedPreferences prefs;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _pageColor => _isDarkMode ? const Color(0xFF0F172A) : Colors.white;
  Color get _surfaceColor =>
      _isDarkMode ? const Color(0xFF111827) : Colors.white;
  Color get _textColor =>
      _isDarkMode ? const Color(0xFFF9FAFB) : const Color(0xFF17202A);
  Color get _mutedTextColor =>
      _isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _cardBorderColor =>
      _isDarkMode ? const Color(0xFF263244) : const Color(0xFFE7EAF0);
  Color get _chipColor =>
      _isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFF1F4F8);
  Color get _inputFillColor =>
      _isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFF7F9FC);

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();
    vatValue = prefs.getDouble('vatperc') ?? 5;
    inactiveparties_days = prefs.getInt('inactiveparties_days') ?? 30;

    vatController.text = vatValue.toString();
    inactivedaysController.text = inactiveparties_days.toString();
    dateRangeOption = prefs.getString('dateRangeOption') ?? 'Today';

    String? start = prefs.getString('startdate');
    String? end = prefs.getString('enddate');
    if (start != null && end != null) {
      customStartDate = DateTime.tryParse(start);
      customEndDate = DateTime.tryParse(end);
    }

    try {
      groupvalue = prefs.getString('currencycode')!;
      if (groupvalue == 'null') {
        groupvalue = 'AED';
      }
    } catch (e) {
      groupvalue = 'AED';
    }

    try {
      sort = prefs.getString('sort')!;
      if (sort == 'null') {
        sort = 'Default';
      }
    } catch (e) {
      sort = 'Default';
    }

    try {
      decimal = prefs.getInt('decimalplace');
      if (decimal == null || decimal == 'null') {
        decimal = 2;
      }
    } catch (e) {
      decimal = 2;
    }

    final bool isAdmin = (prefs.getString('secbtnaccess') ?? 'False') == 'True';
    _canCurrency =
        isAdmin || (prefs.getString('settings_currency') ?? 'False') == 'True';
    _canAmtDecimals =
        isAdmin ||
        (prefs.getString('settings_amtdecimals') ?? 'False') == 'True';
    _canVatPerc =
        isAdmin || (prefs.getString('settings_vatperc') ?? 'False') == 'True';
    _canInactivePDays =
        isAdmin ||
        (prefs.getString('settings_inactivepdays') ?? 'False') == 'True';
    _canSortType =
        isAdmin || (prefs.getString('settings_sorttype') ?? 'False') == 'True';
    _canDefDateRange =
        isAdmin ||
        (prefs.getString('settings_defdaterange') ?? 'False') == 'True';
    _canAgeingConfig =
        isAdmin ||
        (prefs.getString('settings_ageingconfig') ?? 'False') == 'True';
    _canFastSlowInactiveItem =
        isAdmin ||
        (prefs.getString('settings_fastslowinactiveitem') ?? 'False') == 'True';

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldState>();
    themeController.addListener(_handleThemeChanged);
    _initSharedPreferences();
    _initBiometricSettings();
  }

  Future<void> _initBiometricSettings() async {
    final available = await BiometricAuthService.instance.isDeviceSupported();
    final enabled = await BiometricAuthService.instance.isEnabled();
    final label = await BiometricAuthService.instance.biometricLabel();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _biometricLabel = label;
    });
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      final storedUser = prefs.getString('username_remember');
      final storedPass = prefs.getString('password_remember');
      if (storedUser == null || storedPass == null) {
        showAppMessage(
          context,
          'Please log in once with "Remember me" checked before enabling $_biometricLabel login.',
        );
        return;
      }
      final confirmed = await BiometricAuthService.instance.authenticate(
        reason: 'Confirm $_biometricLabel to enable it for sign in',
      );
      if (!confirmed) return;
      await BiometricAuthService.instance.setEnabled(true);
      await prefs.setString('biometric_username', storedUser);
      await prefs.setString('biometric_password', storedPass);
    } else {
      await BiometricAuthService.instance.setEnabled(false);
      await prefs.remove('biometric_username');
      await prefs.remove('biometric_password');
    }
    if (!mounted) return;
    setState(() => _biometricEnabled = enable);
  }

  @override
  void dispose() {
    themeController.removeListener(_handleThemeChanged);
    vatController.dispose();
    inactivedaysController.dispose();
    super.dispose();
  }

  void _handleThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String getCurrencySymbol(String currencyCode) {
    NumberFormat format;
    Locale locale = Localizations.localeOf(context);

    try {
      if (currencyCode == 'INR' ||
          currencyCode == 'EUR' ||
          currencyCode == 'PKR') {
        format = NumberFormat.simpleCurrency(
          locale: locale.toString(),
          name: currencyCode,
        );
      } else {
        format = NumberFormat.currency(
          locale: locale.toString(),
          name: currencyCode,
        );
      }
      return format.currencySymbol;
    } catch (e) {
      return 'AED';
    }
  }

  String _decimalLabel() {
    final value = decimal ?? 2;
    return '$value Decimal${value == 1 ? '' : 's'}';
  }

  String _dateRangeLabel() {
    if (dateRangeOption == 'Custom Date' &&
        customStartDate != null &&
        customEndDate != null) {
      final formatter = DateFormat('dd MMM yyyy');
      return '${formatter.format(customStartDate!)} - ${formatter.format(customEndDate!)}';
    }
    return dateRangeOption;
  }

  String _themeModeLabel() {
    switch (themeController.themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.more,
        activeMoreItem: AppMoreItem.settings,
      ),
      key: _scaffoldMessengerKey,
      backgroundColor: _pageColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          automaticallyImplyLeading: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => Dashboard()),
              );
            },
          ),
          title: GestureDetector(
            onTap: () {},
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    "Settings" ?? '',

                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          centerTitle: true,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildHeaderCard(),

            // ── Appearance (always visible) ──────────────────────────────
            const SizedBox(height: 18),
            _buildSectionLabel('Appearance'),
            _buildSettingsGroup(
              children: [
                _buildTile(
                  icon: themeController.themeMode == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  title: 'Theme',
                  subtitle: 'Choose system, light, or dark mode',
                  value: _themeModeLabel(),
                  onTap: () => _showThemeDialog(context),
                ),
              ],
            ),

            // ── Security ─────────────────────────────────────────────────
            if (_biometricAvailable) const SizedBox(height: 18),
            if (_biometricAvailable) _buildSectionLabel('Security'),
            if (_biometricAvailable)
              _buildSettingsGroup(
                children: [
                  SwitchListTile(
                    activeColor: app_color,
                    secondary: Icon(
                      _biometricLabel == 'Face ID'
                          ? Icons.face_retouching_natural
                          : Icons.fingerprint,
                      color: _textColor,
                    ),
                    title: Text(
                      '$_biometricLabel login',
                      style: TextStyle(color: _textColor),
                    ),
                    subtitle: Text(
                      'Sign in using $_biometricLabel instead of your password',
                      style: TextStyle(color: _mutedTextColor),
                    ),
                    value: _biometricEnabled,
                    onChanged: _toggleBiometric,
                  ),
                ],
              ),

            // ── General ──────────────────────────────────────────────────
            if ([_canCurrency, _canAmtDecimals, _canVatPerc].any((v) => v))
              const SizedBox(height: 18),
            if ([_canCurrency, _canAmtDecimals, _canVatPerc].any((v) => v))
              _buildSectionLabel('General'),
            if ([_canCurrency, _canAmtDecimals, _canVatPerc].any((v) => v))
              _buildSettingsGroup(
                children: [
                  if (_canCurrency)
                    _buildTile(
                      icon: Icons.attach_money_rounded,
                      title: 'Currency',
                      subtitle: 'Select currency for the app',
                      value: groupvalue,
                      onTap: () => _showCurrencyDialog(context),
                    ),
                  if (_canAmtDecimals)
                    _buildTile(
                      icon: Icons.numbers_rounded,
                      title: 'Amount in Decimals',
                      subtitle: 'Customize number of decimal points',
                      value: _decimalLabel(),
                      onTap: () => _showDecimalDialog(context),
                    ),
                  if (_canVatPerc)
                    _buildTile(
                      icon: Icons.percent_rounded,
                      title: 'VAT Percentage',
                      subtitle: 'Set VAT percentage for the app',
                      value: '${vatController.text}%',
                      onTap: () => _showVatInputDialog(context),
                    ),
                ],
              ),

            // ── Defaults ─────────────────────────────────────────────────
            if ([
              _canInactivePDays,
              _canSortType,
              _canDefDateRange,
            ].any((v) => v))
              const SizedBox(height: 18),
            if ([
              _canInactivePDays,
              _canSortType,
              _canDefDateRange,
            ].any((v) => v))
              _buildSectionLabel('Defaults'),
            if ([
              _canInactivePDays,
              _canSortType,
              _canDefDateRange,
            ].any((v) => v))
              _buildSettingsGroup(
                children: [
                  if (_canInactivePDays)
                    _buildTile(
                      icon: Icons.calendar_today_outlined,
                      title: 'Inactive Parties Days',
                      subtitle: 'Set no. of inactive party days',
                      value: '${inactivedaysController.text} days',
                      onTap: () => _showInactivedaysInputDialog(context),
                    ),
                  if (_canSortType)
                    _buildTile(
                      icon: Icons.sort_rounded,
                      title: 'Sort Type',
                      subtitle: 'Default sorting selection for the app',
                      value: sort,
                      onTap: () => _showSortDialog(context),
                    ),
                  if (_canDefDateRange)
                    _buildTile(
                      icon: Icons.date_range_rounded,
                      title: 'Default Date Range',
                      subtitle: 'Select default report period',
                      value: _dateRangeLabel(),
                      onTap: () => _showDateRangeDialog(context),
                    ),
                ],
              ),

            // ── Configurations ───────────────────────────────────────────
            if ([_canAgeingConfig, _canFastSlowInactiveItem].any((v) => v))
              const SizedBox(height: 18),
            if ([_canAgeingConfig, _canFastSlowInactiveItem].any((v) => v))
              _buildSectionLabel('Configurations'),
            if ([_canAgeingConfig, _canFastSlowInactiveItem].any((v) => v))
              _buildSettingsGroup(
                children: [
                  if (_canAgeingConfig)
                    _buildTile(
                      icon: Icons.access_time_rounded,
                      title: 'Ageing Configuration',
                      subtitle: 'Customize ageing range',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AgeingConfig()),
                      ),
                    ),
                  if (_canFastSlowInactiveItem)
                    _buildTile(
                      icon: Icons.stacked_bar_chart_rounded,
                      title: 'Fast/Slow/Inactive Items',
                      subtitle: 'Customize Fast/Slow/Inactive Items Criteria',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FastMovingInactiveItemsCriteria(
                              fastmoving_visible: true,
                              slowmoving_visible: true,
                              inactive_visible: true,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: app_color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: app_color.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App Preferences',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage defaults for reports, values, and item criteria.',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          color: _mutedTextColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDarkMode ? 0.18 : 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index != children.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: _cardBorderColor,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: app_color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: app_color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      color: _mutedTextColor,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (value != null && value.trim().isNotEmpty) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 118),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _chipColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _cardBorderColor),
                  ),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: _mutedTextColor, size: 22),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: app_color),
      labelStyle: GoogleFonts.poppins(color: _mutedTextColor),
      filled: true,
      fillColor: _inputFillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _cardBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: app_color, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }

  Widget _dialogHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: app_color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: app_color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _mutedTextColor,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          style: IconButton.styleFrom(
            backgroundColor: _chipColor,
            foregroundColor: _mutedTextColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  RadioListTile<T> _optionTile<T>({
    required T value,
    required T? groupValue,
    required String title,
    required ValueChanged<T?> onChanged,
  }) {
    final bool selected = groupValue == value;

    return RadioListTile<T>(
      value: value,
      groupValue: groupValue,
      activeColor: app_color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selected ? app_color.withOpacity(0.08) : Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: _textColor,
          fontSize: 13.5,
        ),
      ),
      onChanged: onChanged,
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: _surfaceColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogHeader(
                  icon: Icons.contrast_rounded,
                  title: 'Theme',
                  subtitle: 'Current theme: ${_themeModeLabel()}',
                ),
                const SizedBox(height: 12),
                _optionTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: themeController.themeMode,
                  title: 'System default',
                  onChanged: (value) => _selectThemeMode(context, value),
                ),
                _optionTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: themeController.themeMode,
                  title: 'Light mode',
                  onChanged: (value) => _selectThemeMode(context, value),
                ),
                _optionTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: themeController.themeMode,
                  title: 'Dark mode',
                  onChanged: (value) => _selectThemeMode(context, value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectThemeMode(BuildContext context, ThemeMode? mode) {
    if (mode == null) {
      return;
    }

    themeController.setThemeMode(mode);
    Navigator.pop(context);
  }

  void _showVatInputDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: _surfaceColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogHeader(
                  icon: Icons.percent_rounded,
                  title: 'VAT Percentage',
                  subtitle: 'Current value: ${vatController.text}%',
                ),
                const SizedBox(height: 18),
                Form(
                  key: _vatFormkey,
                  child: TextFormField(
                    controller: vatController,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter VAT (%)';
                      }
                      return null;
                    },
                    decoration: _inputDecoration(
                      label: 'VAT (%)',
                      hint: 'Enter VAT (%)',
                      icon: Icons.edit_note_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.save_alt_outlined),
                    label: Text(
                      'Save',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      if (_vatFormkey.currentState?.validate() ?? false) {
                        _vatFormkey.currentState!.save();
                        double vat = double.tryParse(vatController.text) ?? 0.0;
                        prefs.setDouble('vatperc', vat);
                        setState(() {
                          vatValue = vat;
                        });
                        print('VAT: $vat%');
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInactivedaysInputDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: _surfaceColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogHeader(
                  icon: Icons.calendar_today_rounded,
                  title: 'Inactive Parties Days',
                  subtitle:
                      'Current value: ${inactivedaysController.text} days',
                ),
                const SizedBox(height: 18),
                Form(
                  key: _inactivepartydaysFormkey,
                  child: TextFormField(
                    controller: inactivedaysController,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter day(s)';
                      }
                      return null;
                    },
                    decoration: _inputDecoration(
                      label: 'Day(s)',
                      hint: 'Enter number of day(s)',
                      icon: Icons.timer_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.save_alt_outlined),
                    label: Text(
                      'Save',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      if (_inactivepartydaysFormkey.currentState?.validate() ??
                          false) {
                        _inactivepartydaysFormkey.currentState!.save();

                        int days =
                            int.tryParse(inactivedaysController.text) ?? 30;
                        prefs.setInt('inactiveparties_days', days);
                        setState(() {
                          inactiveparties_days = days;
                        });

                        print('Inactive Days: $days');
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDateRangeDialog(BuildContext context) {
    final options = [
      'Today',
      'Yesterday',
      'This Month',
      'Last Month',
      'This Year',
      'Last Year',
      'Year To Date',
    ];

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            children: [
              _dialogHeader(
                icon: Icons.date_range_rounded,
                title: 'Select Date Range',
                subtitle: 'Selected: $dateRangeOption',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: options.map((option) {
                    return _optionTile<String>(
                      value: option,
                      groupValue: dateRangeOption,
                      title: option,
                      onChanged: (val) async {
                        Navigator.pop(context);

                        if (val == 'Custom Date') {
                          await _showCustomDatePicker(context);
                        } else {
                          setState(() {
                            dateRangeOption = val!;
                          });
                          prefs.setString('dateRangeOption', dateRangeOption);
                          prefs.remove('startdate');
                          prefs.remove('enddate');
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomDatePicker(BuildContext context) async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: customStartDate != null && customEndDate != null
          ? DateTimeRange(start: customStartDate!, end: customEndDate!)
          : null,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: (_isDarkMode ? ThemeData.dark() : ThemeData.light()).copyWith(
            colorScheme:
                (_isDarkMode
                        ? const ColorScheme.dark()
                        : const ColorScheme.light())
                    .copyWith(
                      primary: app_color,
                      onPrimary: Colors.white,
                      surface: _surfaceColor,
                      onSurface: _textColor,
                    ),
            datePickerTheme: DatePickerThemeData(
              rangeSelectionBackgroundColor: app_color.withOpacity(0.15),
              rangeSelectionOverlayColor: MaterialStatePropertyAll(
                app_color.withOpacity(0.15),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        dateRangeOption = 'Custom Date';
        customStartDate = picked.start;
        customEndDate = picked.end;
      });
      prefs.setString('dateRangeOption', 'Custom Date');
      prefs.setString('startdate', picked.start.toIso8601String());
      prefs.setString('enddate', picked.end.toIso8601String());
    }
  }

  void _showCurrencyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            children: [
              _dialogHeader(
                icon: Icons.attach_money_rounded,
                title: 'Currency',
                subtitle: 'Selected: $groupvalue',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      _buildCurrencyOption(context, 'USD', 'USD (\$)'),
                      _buildCurrencyOption(
                        context,
                        'AED',
                        'UAE Dirhams (${getCurrencySymbol('AED')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'INR',
                        'Indian Rupees (${getCurrencySymbol('INR')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'PKR',
                        'Pakistani Rupees (${getCurrencySymbol('PKR')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'EUR',
                        'Euro (${getCurrencySymbol('EUR')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'LKR',
                        'SriLankan Rupees (${getCurrencySymbol('LKR')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'SAR',
                        'Saudi Riyal (${getCurrencySymbol('SAR')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'OMR',
                        'Omani Riyal (${getCurrencySymbol('OMR')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'BHD',
                        'Bahraini Dinar (${getCurrencySymbol('BHD')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'QAR',
                        'Qatari Riyal (${getCurrencySymbol('QAR')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'KWD',
                        'Kuwaiti Dinar (${getCurrencySymbol('KWD')})',
                      ),
                      _buildCurrencyOption(
                        context,
                        'SLE',
                        'Sierra Leonean Leone (${getCurrencySymbol('SLE')})',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyOption(
    BuildContext context,
    String value,
    String label,
  ) {
    return _optionTile<String>(
      value: value,
      groupValue: groupvalue,
      title: label,
      onChanged: (selected) {
        setState(() {
          groupvalue = selected!;
        });
        prefs.setString('currencycode', groupvalue);
        Navigator.pop(context);
      },
    );
  }

  void _showDecimalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            children: [
              _dialogHeader(
                icon: Icons.numbers_rounded,
                title: 'Amount in Decimals',
                subtitle: 'Selected: ${_decimalLabel()}',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: List.generate(4, (index) {
                    int value = index + 1;
                    return _optionTile<int>(
                      value: value,
                      groupValue: decimal,
                      title: '$value Decimal${value > 1 ? 's' : ''}',
                      onChanged: (val) {
                        setState(() {
                          decimal = val!;
                        });
                        prefs.setInt('decimalplace', decimal!);
                        Navigator.pop(context);
                      },
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortDialog(BuildContext context) {
    final options = [
      'Default',
      'Newest to Oldest',
      'Oldest to Newest',
      'A->Z',
      'Z->A',
      'Amount High to Low',
      'Amount Low to High',
    ];

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            children: [
              _dialogHeader(
                icon: Icons.sort_rounded,
                title: 'Sort Options',
                subtitle: 'Selected: $sort',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: options.map((s) {
                    return _optionTile<String>(
                      value: s,
                      groupValue: sort,
                      title: s,
                      onChanged: (val) {
                        setState(() {
                          sort = val!;
                        });
                        prefs.setString('sort', sort);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
