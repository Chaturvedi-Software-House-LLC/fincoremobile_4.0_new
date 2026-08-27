import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Dashboard.dart';
import 'Login.dart';
import 'constants.dart';
import 'api/api_exception.dart';
import 'api/auth_repository.dart';
import 'legacy_permission_flags.dart';

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
class CompanySelectTallyOauth extends StatefulWidget {
  const CompanySelectTallyOauth({super.key});

  @override
  State<CompanySelectTallyOauth> createState() =>
      _CompanySelectTallyOauthState();
}

class _CompanySelectTallyOauthState extends State<CompanySelectTallyOauth>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _isSelecting = false;
  String? _errorMessage;
  // Cause-specific heading for _errorMessage ("License Expired" vs.
  // "License Suspended" etc.) - null falls back to a generic title.
  String? _errorTitle;

  // Becomes true the first time the serial/company list UI is actually
  // rendered - before that, a single-license+single-company account never
  // sees any list at all, matching legacy's silent auto-navigate.
  bool _listShown = false;

  List<Map<String, dynamic>> _allCompanies = [];
  // "Valid" = usable for login (active, not suspended, not expired) -
  // mirrors legacy's license-expiry/suspension check, which blocked a
  // serial from being used rather than just hiding it silently.
  List<Map<String, dynamic>> _validLicenses = [];

  // null = still on the "pick a serial number" step (only reached when
  // there's more than one valid license). Set once a license is chosen,
  // or auto-chosen when there's exactly one.
  Map<String, dynamic>? _selectedLicense;

  String _adminEmail = '';

  final _serialSearchController = TextEditingController();
  final _companySearchController = TextEditingController();
  String _serialSearchQuery = '';
  String _companySearchQuery = '';
  bool _showAllSerials = false;
  bool _showAllCompanies = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _serialSearchController.dispose();
    _companySearchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _companiesFor(String licenseId) =>
      _allCompanies.where((c) => c['licenseId'] == licenseId).toList();

  /// Same checks legacy's license-expiry dialog made before letting a
  /// serial number be used: active, not suspended, not past its
  /// `validUntil` date. tally-oauth also enforces this server-side at
  /// company-user login, but checking here too means an expired/suspended
  /// license shows a clear reason up front instead of a generic "sign-in
  /// failed" after the user has already picked a company under it. Now a
  /// thin wrapper over [AuthRepository.isLicenseUsable] - kept as one
  /// source of truth shared with [Login]'s own pre-flight check.
  bool _isLicenseValid(Map<String, dynamic> license) =>
      AuthRepository.instance.isLicenseUsable(license);

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorTitle = null;
      _selectedLicense = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _adminEmail = prefs.getString('username') ?? '';

      final results = await Future.wait([
        AuthRepository.instance.listLicenses(),
        AuthRepository.instance.listCompanies(),
      ]);
      final licenses = results[0];
      final companies = results[1];

      final valid = licenses.where(_isLicenseValid).toList();
      final invalid = licenses.where((l) => !_isLicenseValid(l)).toList();

      if (!mounted) return;
      setState(() {
        _allCompanies = companies;
        _validLicenses = valid;
        _isLoading = false;
      });

      if (valid.isEmpty) {
        setState(() {
          if (invalid.isNotEmpty) {
            final reason = invalid.length == 1
                ? AuthRepository.instance.licenseUnavailableReason(
                    invalid.first,
                  )
                : null;
            _errorTitle = reason?.$1 ?? 'Licenses Unavailable';
            _errorMessage = reason?.$2 ??
                'None of your licenses are currently active. Please contact your administrator.';
          } else {
            _errorTitle = 'No License Found';
            _errorMessage = 'No license was found for this account.';
          }
        });
        return;
      }

      // Single serial + single company -> straight to Dashboard, no UI
      // shown at all (matches legacy's auto-navigate behavior exactly).
      if (valid.length == 1) {
        await _proceedWithLicense(valid.first);
      } else {
        setState(() => _listShown = true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load your companies. Please try again.';
      });
    }
  }

  Future<void> _proceedWithLicense(Map<String, dynamic> license) async {
    final companies = _companiesFor(license['id'] as String);
    if (!mounted) return;
    setState(() {
      _selectedLicense = license;
      _errorMessage = null;
      _errorTitle = null;
      _showAllCompanies = false;
      _companySearchController.clear();
      _companySearchQuery = '';
    });

    if (companies.isEmpty) {
      setState(() {
        _errorMessage = 'No companies found for this serial number.';
        _listShown = true;
      });
    } else if (companies.length == 1) {
      // Single company under this serial -> straight to Dashboard.
      await _selectCompany(companies.first);
    } else {
      setState(() => _listShown = true);
    }
  }

  void _backToSerialList() {
    setState(() {
      _selectedLicense = null;
      _errorMessage = null;
      _errorTitle = null;
    });
  }

  String _normalizeCompanyName(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _licenseLabel(Map<String, dynamic> license) {
    final serial = license['tallySerialNumber'] as String?;
    if (serial != null && serial.isNotEmpty) return serial;
    // Falls back to the license name when no Tally serial number has been
    // bound yet (see AuthRepository.listLicenses's doc comment) - still
    // lets the account be selected rather than showing a blank row.
    return license['name']?.toString() ?? 'Unnamed license';
  }

  Future<void> _selectCompany(Map<String, dynamic> company) async {
    setState(() {
      _isSelecting = true;
      _errorMessage = null;
      _errorTitle = null;
    });

    try {
      final companyId = company['id'] as String;
      final companyName = company['name'] as String;
      final startFrom = company['startFrom']?.toString() ?? '';
      // tally-oauth's `GET /company` response nests the owning license's
      // real `validUntil` here (CompanyResponseSchema). Dashboard.dart
      // treats a missing/unparseable `license_expiry` as *already expired*
      // (a safe-by-default fallback for the legacy flow, where a missing
      // value genuinely meant "never checked") and force-navigates to the
      // legacy SerialSelect screen via a non-dismissible dialog - so this
      // must be populated with the real value, not left blank, even though
      // tally-oauth already enforces validity server-side at login too.
      final licenseExpiry =
          (company['license'] as Map<String, dynamic>?)?['validUntil']
              as String?;

      // The only auth tally-api gets for this session - awaited and
      // error-handled, not best-effort, unlike SerialSelect's
      // fire-and-forget equivalent.
      await AuthRepository.instance.selectCompanyById(companyId);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('company_name', _normalizeCompanyName(companyName));
      await prefs.setString('startfrom', startFrom);
      if (licenseExpiry != null) {
        await prefs.setString('license_expiry', licenseExpiry);
      }
      await prefs.setString('serial_no', '');
      await prefs.setString('base_currency', '');
      await prefs.setString('company_trn', '');
      await prefs.setString('company_address', '');
      await prefs.setString('company_emirate', '');
      await prefs.setString('company_country', '');

      // Real per-permission screen-visibility flags, replacing the old
      // hardcoded "everything True" interim default - see
      // legacy_permission_flags.dart for the full legacy-key <-> new
      // permission-string mapping and the fail-closed default it applies
      // when the permissions claim can't be read at all.
      final permissions =
          await AuthRepository.instance.currentCompanyUserPermissions();
      await applyPermissionFlags(prefs, permissions);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => Dashboard()),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSelecting = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSelecting = false;
        _errorMessage = 'Could not sign in to this company. Please try again.';
      });
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await AuthRepository.instance.logout();
    await prefs.clear();
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
    final showFullScreenLoader = (_isLoading || _isSelecting) && !_listShown;
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
                              if (_errorMessage != null &&
                                  _selectedLicense == null) ...[
                                _buildErrorBanner(
                                  _errorTitle ?? 'License Unavailable',
                                  _errorMessage!,
                                  _loadData,
                                ),
                                const SizedBox(height: 18),
                              ],
                              if (_validLicenses.length > 1) ...[
                                _buildSectionHeader(
                                  title: "Serial Numbers",
                                  count: _validLicenses.length,
                                  icon: Icons.confirmation_number_outlined,
                                ),
                                const SizedBox(height: 10),
                                _buildSerialList(),
                                const SizedBox(height: 22),
                              ],
                              if (_selectedLicense != null) ...[
                                _buildSectionHeader(
                                  title: "Companies",
                                  count: _companiesFor(
                                    _selectedLicense!['id'] as String,
                                  ).length,
                                  icon: Icons.business_rounded,
                                ),
                                const SizedBox(height: 10),
                                if (_errorMessage != null)
                                  _buildErrorBanner(
                                    _errorTitle ?? 'License Unavailable',
                                    _errorMessage!,
                                    _validLicenses.length > 1
                                        ? _backToSerialList
                                        : _loadData,
                                    retryLabel: _validLicenses.length > 1
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
    if (!_isLoading && !_isSelecting) return const SizedBox.shrink();

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
    final subtitle = _selectedLicense != null
        ? "Max Users: ${_selectedLicense!['maxUsersPerCompany'] ?? '-'}"
        : "Active Serial Numbers: ${_validLicenses.length}";

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
                  _adminEmail.isEmpty ? "Account" : _adminEmail,
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
    final searchedSerials = _serialSearchQuery.isEmpty
        ? _validLicenses
        : _validLicenses.where((item) {
            return _licenseLabel(item).toLowerCase().contains(_serialSearchQuery);
          }).toList();

    final visibleSerials =
        _showAllSerials ? searchedSerials : searchedSerials.take(3).toList();

    return Column(
      children: [
        if (_validLicenses.length > 6)
          _buildSearchField(
            controller: _serialSearchController,
            hintText: 'Search serial numbers...',
            onChanged: (value) {
              setState(() => _serialSearchQuery = value.trim().toLowerCase());
            },
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
          final bool isSelected = item == _selectedLicense;
          final serialText = _licenseLabel(item);
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
            expanded: _showAllSerials,
            onTap: () => setState(() => _showAllSerials = !_showAllSerials),
          ),
      ],
    );
  }

  Widget _buildCompanyList() {
    final allForLicense = _companiesFor(_selectedLicense!['id'] as String);
    final searchedCompanies = _companySearchQuery.isEmpty
        ? allForLicense
        : allForLicense.where((item) {
            final companyName = (item['name']?.toString() ?? '').toLowerCase();
            return companyName.contains(_companySearchQuery);
          }).toList();

    final visibleCompanies =
        _showAllCompanies ? searchedCompanies : searchedCompanies.take(3).toList();

    return Column(
      children: [
        // "Change serial number" back-link removed on request - the
        // Companies section stays a one-way drill-down from the serial
        // list rather than offering a way back to it.
        if (allForLicense.length > 6)
          _buildSearchField(
            controller: _companySearchController,
            hintText: 'Search companies...',
            onChanged: (value) {
              setState(() => _companySearchQuery = value.trim().toLowerCase());
            },
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
            expanded: _showAllCompanies,
            onTap: () => setState(() => _showAllCompanies = !_showAllCompanies),
          ),
      ],
    );
  }
}
