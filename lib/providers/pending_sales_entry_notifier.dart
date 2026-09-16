import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PendingSalesEntry.dart';
import '../api/api_exception.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Riverpod migration of `PendingSalesEntry.dart`'s
/// `_PendingSalesEntryPageState`. A much smaller/simpler screen than the
/// registration screens - a plain fetch/filter/delete list, no accumulator
/// logic - so this one moves entirely to a StateNotifier without the
/// alias-variable pattern needed elsewhere.
///
/// Dead fields dropped rather than ported (confirmed unreferenced beyond
/// their own declaration/assignment, or feeding only other dead fields):
/// `isDashEnable`, `isUserEnable`, `isRolesEnable`, `isRolesVisible`,
/// `isUserVisible`, `rolename_fetched`, `hostname`, `company`,
/// `company_lowercase`, `username`, `HttpURL`, `SecuritybtnAcessHolder`,
/// `name`, `email`, and the `isVanSalesSerial` getter (never called
/// anywhere). Only `serial_no` is genuinely read (by `build()`'s
/// `canActOnCard` check), so that's the only session field ported.
class PendingSalesEntryState {
  final List<SalesModel> salesEntries;
  final List<SalesModel> filteredSalesEntries;
  final bool isVisibleNoSalesEntryFound;
  final bool isLoading;
  final bool isLoadingMore;
  final String? serialNo;
  final DateTime? selectedSingleDate;
  final DateTimeRange? selectedDateRange;

  const PendingSalesEntryState({
    required this.salesEntries,
    required this.filteredSalesEntries,
    required this.isVisibleNoSalesEntryFound,
    required this.isLoading,
    required this.isLoadingMore,
    required this.serialNo,
    required this.selectedSingleDate,
    required this.selectedDateRange,
  });
}

class PendingSalesEntryNotifier extends StateNotifier<PendingSalesEntryState> {
  PendingSalesEntryNotifier()
    : super(
        const PendingSalesEntryState(
          salesEntries: [],
          filteredSalesEntries: [],
          isVisibleNoSalesEntryFound: false,
          isLoading: false,
          isLoadingMore: false,
          serialNo: '',
          selectedSingleDate: null,
          selectedDateRange: null,
        ),
      ) {
    _init();
  }

  void _commit(void Function() fn) {
    fn();
    state = _snapshot();
  }

  PendingSalesEntryState _snapshot() => PendingSalesEntryState(
    salesEntries: List.unmodifiable(salesentries),
    filteredSalesEntries: List.unmodifiable(filteredSalesEntries),
    isVisibleNoSalesEntryFound: isVisibleNoSalesEntryFound,
    isLoading: _isLoading,
    isLoadingMore: _isLoadingMore,
    serialNo: serial_no,
    selectedSingleDate: _selectedSingleDate,
    selectedDateRange: _selectedDateRange,
  );

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  final List<SalesModel> salesentries = [];
  List<SalesModel> filteredSalesEntries = [];
  bool isVisibleNoSalesEntryFound = false;
  bool _isLoading = false;
  String? serial_no = '';

  String _searchQuery = '';
  DateTime? _selectedSingleDate;
  DateTimeRange? _selectedDateRange;

  // ---- scroll-triggered pagination (server returns date DESC, id DESC -
  // pages append in the order the server already sorted, no client re-sort
  // needed between pages) ----
  static const int _pePageLimit = 20;
  int _peRequestGen = 0;
  bool _isLoadingMore = false;
  int? _peNextPage = 2;
  int _peTotalPages = 1;
  Set<int> _peSalesVoucherTypeMasterIds = {};
  String? _peVoucherTypeNameFilter;

  bool get canLoadMoreSalesEntries => _peNextPage != null;

  /// Verbatim port of `entrydelete`, minus the `showAppMessage`/context
  /// calls (the widget handles those based on this method's result).
  Future<String?> entrydelete(String entryId) async {
    _commit(() => _isLoading = true);
    String? error;
    try {
      await VoucherEntryRepository.instance.remove(entryId);
      await fetchSalesEntries();
      return null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Server Error!!!';
    }
    _commit(() => _isLoading = false);
    return error;
  }

  /// Verbatim port of `fetchSalesEntries`, minus the `showAppMessage`
  /// context call and the `_searchController.clear()`/`FocusManager`
  /// widget-local resets (the widget does those itself after calling this).
  SalesModel? _mapSalesEntry(Map<String, dynamic> json) {
    if (!_peSalesVoucherTypeMasterIds.contains(json['voucherTypeMasterId'])) {
      return null;
    }
    final model = SalesModel.fromVoucherEntry(json);
    final filterName = _peVoucherTypeNameFilter;
    if (filterName != null &&
        filterName.trim().isNotEmpty &&
        (model.data['VOUCHERTYPENAME'] ?? '').toString() != filterName) {
      return null;
    }
    return model;
  }

  Future<String?> fetchSalesEntries() async {
    final myGen = ++_peRequestGen;
    _commit(() => _isLoading = true);

    String? error;
    try {
      final prefs = await SharedPreferences.getInstance();

      String? voucherTypeName;

      final String? spectraAllocationsString = prefs.getString(
        'spectra_allocations',
      );

      if (spectraAllocationsString != null &&
          spectraAllocationsString.isNotEmpty) {
        final List<dynamic> spectraAllocations = jsonDecode(
          spectraAllocationsString,
        );

        if (spectraAllocations.isNotEmpty) {
          voucherTypeName = spectraAllocations.first['sales_voucher_type'];
        }
      }

      final salesVoucherTypes = await VoucherTypeRepository.instance
          .byReservedName('SALES');

      _peSalesVoucherTypeMasterIds = salesVoucherTypes
          .map<int>((v) => (v['masterId'] as num).toInt())
          .toSet();
      _peVoucherTypeNameFilter = voucherTypeName;

      final firstPage = await VoucherEntryRepository.instance.listPage(
        page: 1,
        limit: _pePageLimit,
      );
      if (myGen != _peRequestGen) return null; // superseded while awaiting

      _peTotalPages = firstPage.totalPages;
      _peNextPage = firstPage.totalPages > 1 ? 2 : null;

      final mapped = firstPage.items
          .map(_mapSalesEntry)
          .whereType<SalesModel>()
          .toList();

      salesentries.clear();
      filteredSalesEntries.clear();
      salesentries.addAll(mapped);
      filteredSalesEntries = List.from(salesentries);

      _commit(() {
        _searchQuery = '';
        _selectedSingleDate = null;
        _selectedDateRange = null;
        isVisibleNoSalesEntryFound =
            filteredSalesEntries.isEmpty && _peNextPage == null;
        _isLoading = false;
      });
      return null;
    } on ApiException catch (e) {
      error = e.message;
      _commit(() {
        if (filteredSalesEntries.isEmpty) {
          isVisibleNoSalesEntryFound = true;
        }
        _isLoading = false;
      });
    } catch (e) {
      _commit(() => _isLoading = false);
    }
    return error;
  }

  /// Fetches the next `/voucher-entries` page and appends the entries
  /// matching this screen's Sales-voucher-type filter - called by
  /// `PendingSalesEntry.dart`'s `ScrollController` listener when the user
  /// scrolls near the bottom.
  Future<void> loadMoreSalesEntries() async {
    if (_isLoadingMore) return;
    final page = _peNextPage;
    if (page == null || page > _peTotalPages) {
      _peNextPage = null;
      return;
    }

    final myGen = _peRequestGen;
    _commit(() => _isLoadingMore = true);
    try {
      final result = await VoucherEntryRepository.instance.listPage(
        page: page,
        limit: _pePageLimit,
      );
      if (myGen != _peRequestGen) {
        _commit(() => _isLoadingMore = false);
        return;
      }

      final mapped = result.items
          .map(_mapSalesEntry)
          .whereType<SalesModel>()
          .toList();
      salesentries.addAll(mapped);
      _peNextPage = page + 1 <= _peTotalPages ? page + 1 : null;

      _commit(() {
        filteredSalesEntries = _computeFilteredList();
        isVisibleNoSalesEntryFound =
            filteredSalesEntries.isEmpty && _peNextPage == null;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (myGen == _peRequestGen) {
        _commit(() => _isLoadingMore = false);
      }
    }
  }

  void searchSales(String query) {
    _searchQuery = query.trim().toLowerCase();
    _applyFilters();
  }

  List<SalesModel> _computeFilteredList() {
    final query = _searchQuery;
    return salesentries.where((entry) {
      final data = entry.data;

      final party = (data['PARTYLEDGERNAME'] ?? '').toString().toLowerCase();
      final vchno = (data['VOUCHERNUMBER'] ?? '').toString().toLowerCase();
      final vchtype = (data['VOUCHERTYPENAME'] ?? '')
          .toString()
          .toLowerCase();
      final amount = (data['totalAmount'] ?? '').toString().toLowerCase();

      final bool matchesSearch =
          query.isEmpty ||
          party.contains(query) ||
          vchno.contains(query) ||
          vchtype.contains(query) ||
          amount.contains(query);

      final bool matchesDate = _matchesDateFilter(entry);

      return matchesSearch && matchesDate;
    }).toList();
  }

  void _applyFilters() {
    _commit(() {
      filteredSalesEntries = _computeFilteredList();
      isVisibleNoSalesEntryFound = filteredSalesEntries.isEmpty;
    });
  }

  bool _matchesDateFilter(SalesModel entry) {
    final dateValue = entry.data['DATE'];

    if (dateValue == null) return false;

    final entryDate = DateTime.tryParse(dateValue.toString());

    if (entryDate == null) return false;

    final onlyEntryDate = DateTime(
      entryDate.year,
      entryDate.month,
      entryDate.day,
    );

    if (_selectedSingleDate != null) {
      final selected = DateTime(
        _selectedSingleDate!.year,
        _selectedSingleDate!.month,
        _selectedSingleDate!.day,
      );

      return onlyEntryDate == selected;
    }

    if (_selectedDateRange != null) {
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );

      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
      );

      return onlyEntryDate.isAtSameMomentAs(start) ||
          onlyEntryDate.isAtSameMomentAs(end) ||
          (onlyEntryDate.isAfter(start) && onlyEntryDate.isBefore(end));
    }

    return true;
  }

  void setSingleDateFilter(DateTime? date) {
    _selectedSingleDate = date;
    _selectedDateRange = null;
    _applyFilters();
  }

  void setDateRangeFilter(DateTimeRange? range) {
    _selectedDateRange = range;
    _selectedSingleDate = null;
    _applyFilters();
  }

  void clearDateFilter() {
    _selectedSingleDate = null;
    _selectedDateRange = null;
    _applyFilters();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    serial_no = prefs.getString('serial_no');
    _commit(() {});
    await fetchSalesEntries();
  }
}

final pendingSalesEntryNotifierProvider = StateNotifierProvider.autoDispose<
    PendingSalesEntryNotifier, PendingSalesEntryState>(
  (ref) => PendingSalesEntryNotifier(),
);
