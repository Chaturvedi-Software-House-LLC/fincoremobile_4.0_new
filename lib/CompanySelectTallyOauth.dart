import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'Dashboard.dart';
import 'Login.dart';
import 'constants.dart';
import 'providers/company_select_notifier.dart';

/// Company-switch entry points (Dashboard's app-bar company name,
/// `app_bottom_nav.dart`'s "Companies" quick action). Used to switch between
/// `SerialSelect()` (legacy-paired login) and `CompanySelectTallyOauth()`
/// depending on whether a `serial_no` pref was set - now that tally-oauth is
/// the app's sole login driver (Phase 6+; the legacy backend is no longer
/// used by any screen), no session ever sets a real `serial_no`, so this
/// always resolves to `CompanySelectTallyOauth()`.
Future<void> navigateToCompanySwitch(BuildContext context) async {
  if (!context.mounted) return;

  // pushAndRemoveUntil, not pushReplacement - matches
  // app_bottom_nav.dart's own `_replaceWith` helper for the same "Companies"
  // action, clearing the whole nav stack rather than leaving a stale entry
  // behind a company switch.
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const CompanySelectTallyOauth()),
    (route) => false,
  );
}

/// Serial-number/company-selection screen for the tally-oauth-only login
/// path (Phase 6+). This is a pixel-for-pixel clone of legacy
/// [SerialSelect]'s layout and interactions (info header, "Serial Numbers"
/// section with search/view-more once there are more than a handful, then
/// a "Companies" section for whichever serial is picked, the same dimmed
/// progress overlay, the same logout/exit confirmation dialogs) - only the
/// data source changed, from legacy's `login_list` prefs blob to
/// `AuthRepository.listLicenses`/`listCompanies`, fetched automatically
/// with no manual serial-number entry (tally-oauth already knows every
/// license this account owns):
/// - Exactly one valid license with exactly one company -> straight to
///   Dashboard, no UI shown at all (same as legacy's silent auto-navigate).
/// - Exactly one valid license with multiple companies -> the "Companies"
///   section only, no serial list to pick from.
/// - Multiple valid licenses -> the "Serial Numbers" list first, then
///   "Companies" for whichever one is tapped. Expired/suspended/inactive
///   licenses are still listed (greyed out, with the reason) rather than
///   silently hidden - mirrors legacy's license-expiry check blocking a
///   serial instead of omitting it.
///
/// Unlike [SerialSelect] (which drives the legacy-paired login flow and is
/// untouched by this file), this screen has no legacy session to fall back
/// on - `AuthRepository.instance.selectCompanyById` here is the *only* auth
/// tally-api gets, so failures are surfaced and block navigation rather than
/// being swallowed like `SerialSelect`'s best-effort
/// `_selectCompanyOnTallyOauth` wrapper.
///
/// Every SharedPreferences key this screen doesn't write (`hostname`,
/// `token`, `company_trn`/`address`/`emirate`/`country`) is a deliberate
/// gap, not a bug - see the "Phase 6" section of the migration plan. The
/// ~48 legacy screen-visibility/enable flags are now set from the real
/// permission-catalog `permissions` claim decoded off the company-user JWT
/// (`AuthRepository.currentCompanyUserPermissions`), via
/// `legacy_permission_flags.dart`'s mapping table - no longer the old
/// hardcoded "everything True" interim default.
class CompanySelectTallyOauth extends ConsumerStatefulWidget {
  const CompanySelectTallyOauth({super.key});

  @override
  ConsumerState<CompanySelectTallyOauth> createState() =>
      _CompanySelectTallyOauthState();
}

class _CompanySelectTallyOauthState
    extends ConsumerState<CompanySelectTallyOauth>
    with TickerProviderStateMixin {
  final _serialSearchController = TextEditingController();
  final _companySearchController = TextEditingController();

  CompanySelectNotifier get _notifier =>
      ref.read(companySelectNotifierProvider.notifier);
  CompanySelectState get _s => ref.read(companySelectNotifierProvider);

  @override
  void initState() {
    super.initState();
    // loadData() completes the entire auto-select flow itself (network
    // calls included) for an account with exactly one valid license and
    // one company - so its result must be observed here to navigate, or
    // that case would fully sign the session in and then never leave this
    // screen. See company_select_notifier.dart's constructor comment.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _serialSearchController.dispose();
    _companySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final result = await _notifier.loadData();
    if (result.success && mounted) _goToDashboard();
  }

  Future<void> _proceedWithLicense(Map<String, dynamic> license) async {
    _companySearchController.clear();
    final result = await _notifier.proceedWithLicense(license);
    if (result.success && mounted) _goToDashboard();
  }

  void _backToSerialList() => _notifier.backToSerialList();

  Future<void> _selectCompany(Map<String, dynamic> company) async {
    final result = await _notifier.selectCompany(company);
    if (result.success && mounted) _goToDashboard();
  }

  void _goToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => Dashboard()),
    );
  }

  Future<void> _logout() async {
    await _notifier.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => Login(username: '', password: '')),
    );
  }

  Future<void> _showLogoutConfirmation() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: app_color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    size: 40,
                    color: app_color,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Logout Confirmation',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Are you sure you want to log out of your account?',
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: app_color),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: app_color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _logout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Logout',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showExitConfirmation() async {
    var shouldExit = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: AnimationController(
              duration: const Duration(milliseconds: 500),
              vsync: this,
            )..forward(),
            curve: Curves.fastOutSlowIn,
          ),
          child: AlertDialog(
            title: const Text('Exit Confirmation'),
            content: const SingleChildScrollView(
              child: ListBody(
                children: <Widget>[Text('Do you really want to Exit?')],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('No', style: GoogleFonts.poppins(color: app_color)),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: Text(
                  'Yes',
                  style: GoogleFonts.poppins(color: app_color),
                ),
                onPressed: () {
                  shouldExit = true;
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
    if (shouldExit) exit(0);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(companySelectNotifierProvider);
    final showFullScreenLoader =
        (_s.isLoading || _s.isSelecting) && !_s.listShown;
    if (showFullScreenLoader) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogoLoader(size: 80),
              const SizedBox(height: 20),
              Text(
                'Signing in…',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _showExitConfirmation,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: AppBar(
            backgroundColor: app_color,
            elevation: 6,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            automaticallyImplyLeading: false,
            leading: null,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: _showLogoutConfirmation,
              ),
              const SizedBox(width: 5),
            ],
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    "Fincore Go",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: SizedBox(
                height: MediaQuery.of(context).size.height,
                width: MediaQuery.of(context).size.width,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoHeader(),
                              const SizedBox(height: 18),
                              if (_s.errorMessage != null &&
                                  _s.selectedLicense == null) ...[
                                _buildErrorBanner(
                                  _s.errorTitle ?? 'License Unavailable',
                                  _s.errorMessage!,
                                  _loadData,
                                ),
                                const SizedBox(height: 18),
                              ],
                              if (_s.validLicenses.length > 1) ...[
                                _buildSectionHeader(
                                  title: "Serial Numbers",
                                  count: _s.validLicenses.length,
                                  icon: Icons.confirmation_number_outlined,
                                ),
                                const SizedBox(height: 10),
                                _buildSerialList(),
                                const SizedBox(height: 22),
                              ],
                              if (_s.selectedLicense != null) ...[
                                _buildSectionHeader(
                                  title: "Companies",
                                  count: _s.companiesFor(
                                    _s.selectedLicense!['id'] as String,
                                  ).length,
                                  icon: Icons.business_rounded,
                                ),
                                const SizedBox(height: 10),
                                if (_s.errorMessage != null)
                                  _buildErrorBanner(
                                    _s.errorTitle ?? 'License Unavailable',
                                    _s.errorMessage!,
                                    _s.validLicenses.length > 1
                                        ? _backToSerialList
                                        : _loadData,
                                    retryLabel: _s.validLicenses.length > 1
                                        ? 'Back to serial numbers'
                                        : 'Retry',
                                  )
                                else
                                  _buildCompanyList(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildProgressOverlay(),
          ],
        ),
      ),
    );
  }

  /// Modern icon-led error card - replaces the earlier plain red-bordered
  /// text box. In practice [Login]'s pre-flight check
  /// (`AuthRepository.checkAnyLicenseUsable`) now catches an
  /// expired/suspended/inactive license before the user ever reaches this
  /// screen; this stays as defense-in-depth for the rare race of a license
  /// lapsing between that check and company selection, so it's still worth
  /// looking deliberate rather than like a stale error dialog.
  Widget _buildErrorBanner(
    String title,
    String message,
    VoidCallback onRetry, {
    String retryLabel = 'Retry',
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_clock_rounded,
              size: 30,
              color: Colors.red.shade600,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: Colors.red.shade700.withOpacity(0.9),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: app_color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: onRetry,
              child: Text(
                retryLabel,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressOverlay() {
    if (!_s.isLoading && !_s.isSelecting) return const SizedBox.shrink();

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withOpacity(0.25),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogoLoader(),
                  const SizedBox(height: 16),
                  Text(
                    "Please wait...",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoHeader() {
    // "Users Allowed" has no direct tally-oauth equivalent shown before a
    // license is picked (legacy fetched it per-serial via `getadmindata`) -
    // shows the max-users-per-company cap once a license is selected, or
    // the count of active serial numbers while still choosing one.
    final subtitle = _s.selectedLicense != null
        ? "Max Users: ${_s.selectedLicense!['maxUsersPerCompany'] ?? '-'}"
        : "Active Serial Numbers: ${_s.validLicenses.length}";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: app_color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: app_color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: app_color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person_outline_rounded, color: app_color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s.adminEmail.isEmpty ? "Account" : _s.adminEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required int count,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: app_color),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: app_color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            "$count",
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: app_color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        style: GoogleFonts.poppins(fontSize: 13.5),
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: GoogleFonts.poppins(fontSize: 13),
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: app_color.withOpacity(0.6), width: 1.4),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildViewMoreButton({required bool expanded, required VoidCallback onTap}) {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(
          expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
          color: app_color,
        ),
        label: Text(
          expanded ? "View less" : "View more",
          style: GoogleFonts.poppins(
            color: app_color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSerialList() {
    final searchedSerials = _s.serialSearchQuery.isEmpty
        ? _s.validLicenses
        : _s.validLicenses.where((item) {
            return _notifier
                .licenseLabel(item)
                .toLowerCase()
                .contains(_s.serialSearchQuery);
          }).toList();

    final visibleSerials =
        _s.showAllSerials ? searchedSerials : searchedSerials.take(3).toList();

    return Column(
      children: [
        if (_s.validLicenses.length > 6)
          _buildSearchField(
            controller: _serialSearchController,
            hintText: 'Search serial numbers...',
            onChanged: _notifier.setSerialSearchQuery,
          ),
        if (searchedSerials.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No matching serial numbers',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...visibleSerials.map((item) {
          final bool isSelected = item == _s.selectedLicense;
          final serialText = _notifier.licenseLabel(item);
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          final Color unselectedBorder = isDark
              ? Theme.of(context).dividerColor.withOpacity(0.55)
              : Colors.grey.shade300;
          final Color unselectedBackground =
              isDark ? Theme.of(context).cardColor.withOpacity(0.38) : Colors.white;
          final Color unselectedIconBackground = isDark
              ? Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5)
              : Colors.grey.shade50;

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _proceedWithLicense(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSelected
                    ? app_color.withOpacity(isDark ? 0.14 : 0.08)
                    : unselectedBackground,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? app_color : unselectedBorder,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: isSelected ? app_color : unselectedIconBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isSelected ? app_color : unselectedBorder),
                    ),
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: 20,
                      color: isSelected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      serialText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle_rounded, color: app_color, size: 21),
                ],
              ),
            ),
          );
        }),
        if (searchedSerials.length > 3)
          _buildViewMoreButton(
            expanded: _s.showAllSerials,
            onTap: _notifier.toggleShowAllSerials,
          ),
      ],
    );
  }

  Widget _buildCompanyList() {
    final allForLicense =
        _s.companiesFor(_s.selectedLicense!['id'] as String);
    final searchedCompanies = _s.companySearchQuery.isEmpty
        ? allForLicense
        : allForLicense.where((item) {
            final companyName = (item['name']?.toString() ?? '').toLowerCase();
            return companyName.contains(_s.companySearchQuery);
          }).toList();

    final visibleCompanies = _s.showAllCompanies
        ? searchedCompanies
        : searchedCompanies.take(3).toList();

    return Column(
      children: [
        // "Change serial number" back-link removed on request - the
        // Companies section stays a one-way drill-down from the serial
        // list rather than offering a way back to it.
        if (allForLicense.length > 6)
          _buildSearchField(
            controller: _companySearchController,
            hintText: 'Search companies...',
            onChanged: _notifier.setCompanySearchQuery,
          ),
        if (searchedCompanies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No matching companies',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...visibleCompanies.map((item) {
          final companyName = item['name']?.toString() ?? '';
          final firstLetters = companyName.length >= 2
              ? companyName.substring(0, 2).toUpperCase()
              : companyName.toUpperCase();

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _selectCompany(item),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: app_color.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      firstLetters,
                      style: GoogleFonts.poppins(
                        color: app_color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          companyName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: app_color),
                ],
              ),
            ),
          );
        }),
        if (searchedCompanies.length > 3)
          _buildViewMoreButton(
            expanded: _s.showAllCompanies,
            onTap: _notifier.toggleShowAllCompanies,
          ),
      ],
    );
  }
}
