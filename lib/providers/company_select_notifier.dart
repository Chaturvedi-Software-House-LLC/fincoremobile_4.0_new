import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exception.dart';
import '../legacy_permission_flags.dart';
import 'repository_providers.dart';

class CompanySelectState {
  final bool isLoading;
  final bool isSelecting;
  final String? errorMessage;
  final String? errorTitle;
  final bool listShown;
  final List<Map<String, dynamic>> allCompanies;
  final List<Map<String, dynamic>> validLicenses;
  final Map<String, dynamic>? selectedLicense;
  final String adminEmail;
  final String serialSearchQuery;
  final String companySearchQuery;
  final bool showAllSerials;
  final bool showAllCompanies;

  const CompanySelectState({
    this.isLoading = true,
    this.isSelecting = false,
    this.errorMessage,
    this.errorTitle,
    this.listShown = false,
    this.allCompanies = const [],
    this.validLicenses = const [],
    this.selectedLicense,
    this.adminEmail = '',
    this.serialSearchQuery = '',
    this.companySearchQuery = '',
    this.showAllSerials = false,
    this.showAllCompanies = false,
  });

  CompanySelectState copyWith({
    bool? isLoading,
    bool? isSelecting,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? errorTitle,
    bool clearErrorTitle = false,
    bool? listShown,
    List<Map<String, dynamic>>? allCompanies,
    List<Map<String, dynamic>>? validLicenses,
    Map<String, dynamic>? selectedLicense,
    bool clearSelectedLicense = false,
    String? adminEmail,
    String? serialSearchQuery,
    String? companySearchQuery,
    bool? showAllSerials,
    bool? showAllCompanies,
  }) {
    return CompanySelectState(
      isLoading: isLoading ?? this.isLoading,
      isSelecting: isSelecting ?? this.isSelecting,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      errorTitle: clearErrorTitle ? null : (errorTitle ?? this.errorTitle),
      listShown: listShown ?? this.listShown,
      allCompanies: allCompanies ?? this.allCompanies,
      validLicenses: validLicenses ?? this.validLicenses,
      selectedLicense: clearSelectedLicense
          ? null
          : (selectedLicense ?? this.selectedLicense),
      adminEmail: adminEmail ?? this.adminEmail,
      serialSearchQuery: serialSearchQuery ?? this.serialSearchQuery,
      companySearchQuery: companySearchQuery ?? this.companySearchQuery,
      showAllSerials: showAllSerials ?? this.showAllSerials,
      showAllCompanies: showAllCompanies ?? this.showAllCompanies,
    );
  }

  List<Map<String, dynamic>> companiesFor(String licenseId) =>
      allCompanies.where((c) => c['licenseId'] == licenseId).toList();
}

/// Result of a company-selection attempt, so the widget can navigate to
/// Dashboard without the notifier reaching into `BuildContext`.
class CompanySelectResult {
  final bool success;

  const CompanySelectResult(this.success);
}

class CompanySelectNotifier extends StateNotifier<CompanySelectState> {
  final Ref _ref;

  // Deliberately NOT auto-calling loadData() here: for an account with
  // exactly one valid license and one company, loadData() completes the
  // entire auto-select flow itself (including the real selectCompanyById
  // network call) and returns a success result - but a result returned
  // from a call fired off in a constructor has no listener, so nothing
  // would ever navigate to Dashboard even though the session was fully
  // established. The widget's initState calls loadData() itself instead,
  // where the returned CompanySelectResult can actually be observed (see
  // _CompanySelectTallyOauthState._loadData).
  CompanySelectNotifier(this._ref) : super(const CompanySelectState());

  /// Same checks legacy's license-expiry dialog made before letting a
  /// serial number be used. Thin wrapper over [AuthRepository.isLicenseUsable]
  /// - kept as one source of truth shared with Login's own pre-flight check.
  bool _isLicenseValid(Map<String, dynamic> license) =>
      _ref.read(authRepositoryProvider).isLicenseUsable(license);

  Future<CompanySelectResult> loadData() async {
    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearErrorTitle: true,
      clearSelectedLicense: true,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final adminEmail = prefs.getString('username') ?? '';

      final repo = _ref.read(authRepositoryProvider);
      final results = await Future.wait([
        repo.listLicenses(),
        repo.listCompanies(),
      ]);
      final ownedLicenses = results[0];
      final ownedCompanies = results[1];

      // Fallback for an account with no owned license of its own - only
      // `company_users` rows under someone else's license (e.g. a
      // driver/employee role). `GET /license/user`/`GET /company` are both
      // owned-license-only, so such an account would otherwise always hit
      // "No License Found" here even though it has real company access -
      // see AuthRepository.companiesFromLastLogin.
      final ownedLicenseIds = ownedLicenses.map((l) => l['id']).toSet();
      final ownedCompanyIds = ownedCompanies.map((c) => c['id']).toSet();
      final licenses = [
        ...ownedLicenses,
        ...repo
            .licensesFromLastLoginCompanies()
            .where((l) => !ownedLicenseIds.contains(l['id'])),
      ];
      final companies = [
        ...ownedCompanies,
        ...repo.companiesFromLastLogin.where(
          (c) => !ownedCompanyIds.contains(c['id']),
        ),
      ];

      final valid = licenses.where(_isLicenseValid).toList();
      final invalid = licenses.where((l) => !_isLicenseValid(l)).toList();

      state = state.copyWith(
        allCompanies: companies,
        validLicenses: valid,
        isLoading: false,
        adminEmail: adminEmail,
      );

      if (valid.isEmpty) {
        if (invalid.isNotEmpty) {
          final reason = invalid.length == 1
              ? repo.licenseUnavailableReason(invalid.first)
              : null;
          state = state.copyWith(
            errorTitle: reason?.$1 ?? 'Licenses Unavailable',
            errorMessage: reason?.$2 ??
                'None of your licenses are currently active. Please contact your administrator.',
          );
        } else {
          state = state.copyWith(
            errorTitle: 'No License Found',
            errorMessage: 'No license was found for this account.',
          );
        }
        return const CompanySelectResult(false);
      }

      // Single serial + single company -> straight to Dashboard, no UI
      // shown at all (matches legacy's auto-navigate behavior exactly).
      if (valid.length == 1) {
        return await proceedWithLicense(valid.first);
      } else {
        state = state.copyWith(listShown: true);
        return const CompanySelectResult(false);
      }
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return const CompanySelectResult(false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not load your companies. Please try again.',
      );
      return const CompanySelectResult(false);
    }
  }

  Future<CompanySelectResult> proceedWithLicense(
    Map<String, dynamic> license,
  ) async {
    final companies = state.companiesFor(license['id'] as String);
    state = state.copyWith(
      selectedLicense: license,
      clearErrorMessage: true,
      clearErrorTitle: true,
      showAllCompanies: false,
      companySearchQuery: '',
    );

    if (companies.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No companies found for this serial number.',
        listShown: true,
      );
      return const CompanySelectResult(false);
    } else if (companies.length == 1) {
      // Single company under this serial -> straight to Dashboard.
      return await selectCompany(companies.first);
    } else {
      state = state.copyWith(listShown: true);
      return const CompanySelectResult(false);
    }
  }

  void backToSerialList() {
    state = state.copyWith(
      clearSelectedLicense: true,
      clearErrorMessage: true,
      clearErrorTitle: true,
    );
  }

  void setSerialSearchQuery(String value) {
    state = state.copyWith(serialSearchQuery: value.trim().toLowerCase());
  }

  void setCompanySearchQuery(String value) {
    state = state.copyWith(companySearchQuery: value.trim().toLowerCase());
  }

  void toggleShowAllSerials() {
    state = state.copyWith(showAllSerials: !state.showAllSerials);
  }

  void toggleShowAllCompanies() {
    state = state.copyWith(showAllCompanies: !state.showAllCompanies);
  }

  String normalizeCompanyName(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String licenseLabel(Map<String, dynamic> license) {
    final serial = license['tallySerialNumber'] as String?;
    if (serial != null && serial.isNotEmpty) return serial;
    return license['name']?.toString() ?? 'Unnamed license';
  }

  Future<CompanySelectResult> selectCompany(
    Map<String, dynamic> company,
  ) async {
    state = state.copyWith(
      isSelecting: true,
      clearErrorMessage: true,
      clearErrorTitle: true,
    );

    try {
      final repo = _ref.read(authRepositoryProvider);
      final companyId = company['id'] as String;
      final companyName = company['name'] as String;
      // tally-oauth's `startFrom` is a full ISO datetime string
      // ("2026-04-01T00:00:00.000Z"), but every screen that reads the
      // 'startfrom' prefs key expects legacy's compact `yyyyMMdd` via
      // parseCompactDate/DateFormat('yyyyMMdd'). Converted here, once, at
      // the source, rather than fixing every consumer's parse call.
      final rawStartFrom = company['startFrom']?.toString();
      final parsedStartFrom =
          rawStartFrom == null ? null : DateTime.tryParse(rawStartFrom);
      final startFrom = parsedStartFrom == null
          ? ''
          : DateFormat('yyyyMMdd').format(parsedStartFrom);
      // tally-oauth's `GET /company` response nests the owning license's
      // real `validUntil` here (CompanyResponseSchema). Dashboard.dart
      // treats a missing/unparseable `license_expiry` as already expired,
      // so this must be populated with the real value.
      final licenseExpiry =
          (company['license'] as Map<String, dynamic>?)?['validUntil']
              as String?;

      // The real Tally serial number (`$$LicenseInfo:SerialNumber`) this
      // license was bound to by a tally-connector, once it's synced one.
      // `GET /company`'s embedded `license` object doesn't expose this
      // field (only `GET /license/user` does), so read it off
      // `state.selectedLicense` - the license this company belongs to,
      // already fetched via `listLicenses()` in `loadData()` - instead.
      final tallySerialNumber =
          (state.selectedLicense?['tallySerialNumber'] as String?) ??
          (company['license'] as Map<String, dynamic>?)?['tallySerialNumber']
              as String? ??
          '';

      // The only auth tally-api gets for this session - awaited and
      // error-handled, not best-effort.
      await repo.selectCompanyById(companyId);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'company_name',
        normalizeCompanyName(companyName),
      );
      if (startFrom.isNotEmpty) {
        await prefs.setString('startfrom', startFrom);
      }
      if (licenseExpiry != null) {
        await prefs.setString('license_expiry', licenseExpiry);
      }
      await prefs.setString('serial_no', tallySerialNumber);
      await prefs.setString('base_currency', '');
      await prefs.setString('company_trn', '');
      await prefs.setString('company_address', '');
      await prefs.setString('company_emirate', '');
      await prefs.setString('company_country', '');

      // Real per-permission screen-visibility flags - see
      // legacy_permission_flags.dart for the mapping + fail-closed default.
      final permissions = await repo.currentCompanyUserPermissions();
      await applyPermissionFlags(prefs, permissions);

      return const CompanySelectResult(true);
    } on ApiException catch (e) {
      state = state.copyWith(isSelecting: false, errorMessage: e.message);
      return const CompanySelectResult(false);
    } catch (e) {
      state = state.copyWith(
        isSelecting: false,
        errorMessage: 'Could not sign in to this company. Please try again.',
      );
      return const CompanySelectResult(false);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _ref.read(authRepositoryProvider).logout();
    await prefs.clear();
  }
}

final companySelectNotifierProvider = StateNotifierProvider.autoDispose<
    CompanySelectNotifier, CompanySelectState>((ref) => CompanySelectNotifier(ref));
