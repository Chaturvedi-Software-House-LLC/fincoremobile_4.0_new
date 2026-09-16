import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../PendingDeliveryNoteEntry.dart';
import '../api/api_exception.dart';
import '../api/voucher_entry_repository.dart';
import '../api/voucher_type_repository.dart';

/// Riverpod migration of `PendingDeliveryNoteEntry.dart`'s
/// `_PendingDeliveryNoteEntryPageState` - same shape as the other Pending*
/// screens (plain fetch/filter/delete list), moved entirely to a
/// StateNotifier.
///
/// Dead fields dropped rather than ported (same pattern as the other
/// Pending* screens): `isDashEnable`, `isUserEnable`, `isRolesEnable`,
/// `isRolesVisible`, `isUserVisible`, `rolename_fetched`, `hostname`,
/// `company`, `company_lowercase`, `username`, `HttpURL`,
/// `SecuritybtnAcessHolder`, `name`, `email`. Only `serial_no` (read by
/// `build()`'s `canActOnCard` check) is a real session field.
class PendingDeliveryNoteEntryState {
  final List<SalesModel> deliveryNoteEntries;
  final List<SalesModel> filteredDeliveryNoteEntries;
  final bool isVisibleNoDeliveryNoteEntryFound;
  final bool isLoading;
  final bool isLoadingMore;
  final String? serialNo;
  final DateTime? selectedSingleDate;
  final DateTimeRange? selectedDateRange;

  const PendingDeliveryNoteEntryState({
    required this.deliveryNoteEntries,
    required this.filteredDeliveryNoteEntries,
    required this.isVisibleNoDeliveryNoteEntryFound,
    required this.isLoading,
    required this.isLoadingMore,
    required this.serialNo,
    required this.selectedSingleDate,
    required this.selectedDateRange,
  });
}

class PendingDeliveryNoteEntryNotifier
    extends StateNotifier<PendingDeliveryNoteEntryState> {
  PendingDeliveryNoteEntryNotifier()
    : super(
        const PendingDeliveryNoteEntryState(
          deliveryNoteEntries: [],
          filteredDeliveryNoteEntries: [],
          isVisibleNoDeliveryNoteEntryFound: false,
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

  PendingDeliveryNoteEntryState _snapshot() => PendingDeliveryNoteEntryState(
    deliveryNoteEntries: List.unmodifiable(deliverynoteentries),
    filteredDeliveryNoteEntries: List.unmodifiable(
      filteredDeliveryNoteEntries,
    ),
    isVisibleNoDeliveryNoteEntryFound: isVisibleNoDeliveryNoteEntryFound,
    isLoading: _isLoading,
    isLoadingMore: _isLoadingMore,
    serialNo: serial_no,
    selectedSingleDate: _selectedSingleDate,
    selectedDateRange: _selectedDateRange,
  );

  // ---- verbatim-ported mutable fields (same names as the original State) ----

  final List<SalesModel> deliverynoteentries = [];
  List<SalesModel> filteredDeliveryNoteEntries = [];
  bool isVisibleNoDeliveryNoteEntryFound = false;
  bool _isLoading = false;
  String? serial_no = '';

  String _searchQuery = '';
  DateTime? _selectedSingleDate;
  DateTimeRange? _selectedDateRange;

  // ---- scroll-triggered pagination (server returns date DESC, id DESC) ----
  static const int _pePageLimit = 20;
  int _peRequestGen = 0;
  bool _isLoadingMore = false;
  int? _peNextPage = 2;
  int _peTotalPages = 1;
  Set<int> _peDeliveryNoteVoucherTypeMasterIds = {};
  String? _peVoucherTypeNameFilter;

  bool get canLoadMoreDeliveryNoteEntries => _peNextPage != null;

  /// Verbatim port of `entrydelete`, minus the `showAppMessage`/context
  /// calls.
  Future<String?> entrydelete(String entryId) async {
    _commit(() => _isLoading = true);
    String? error;
    try {
      await VoucherEntryRepository.instance.remove(entryId);
      await fetchDeliveryNoteEntries();
      return null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Server Error!!!';
    }
    _commit(() => _isLoading = false);
    return error;
  }

  SalesModel? _mapDeliveryNoteEntry(Map<String, dynamic> json) {
    if (!_peDeliveryNoteVoucherTypeMasterIds.contains(
      json['voucherTypeMasterId'],
    )) {
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

  /// Verbatim port of `fetchDeliveryNoteEntries`, minus the
  /// `showAppMessage` context call and the `_searchController.clear()`/
  /// `FocusManager` widget-local resets - now fetches only page 1 up front
  /// (see [loadMoreDeliveryNoteEntries] for the rest).
  Future<String?> fetchDeliveryNoteEntries() async {
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
          voucherTypeName = spectraAllocations.first['voucher_type'];
        }
      }

      final deliveryNoteVoucherTypes = await VoucherTypeRepository.instance
          .byReservedName('DELIVERY_NOTE');

      _peDeliveryNoteVoucherTypeMasterIds = deliveryNoteVoucherTypes
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
          .map(_mapDeliveryNoteEntry)
          .whereType<SalesModel>()
          .toList();

      deliverynoteentries.clear();
      filteredDeliveryNoteEntries.clear();
      deliverynoteentries.addAll(mapped);
      filteredDeliveryNoteEntries = List.from(deliverynoteentries);

      _commit(() {
        _searchQuery = '';
        _selectedSingleDate = null;
        _selectedDateRange = null;
        isVisibleNoDeliveryNoteEntryFound =
            filteredDeliveryNoteEntries.isEmpty && _peNextPage == null;
        _isLoading = false;
      });
      return null;
    } on ApiException catch (e) {
      error = e.message;
      _commit(() {
        if (filteredDeliveryNoteEntries.isEmpty) {
          isVisibleNoDeliveryNoteEntryFound = true;
        }
        _isLoading = false;
      });
    } catch (e) {
      _commit(() => _isLoading = false);
    }
    return error;
  }

  /// Fetches the next `/voucher-entries` page and appends the entries
  /// matching this screen's Delivery-Note-voucher-type filter - called by
  /// `PendingDeliveryNoteEntry.dart`'s `ScrollController` listener.
  Future<void> loadMoreDeliveryNoteEntries() async {
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
          .map(_mapDeliveryNoteEntry)
          .whereType<SalesModel>()
          .toList();
      deliverynoteentries.addAll(mapped);
      _peNextPage = page + 1 <= _peTotalPages ? page + 1 : null;

      _commit(() {
        filteredDeliveryNoteEntries = _computeFilteredList();
        isVisibleNoDeliveryNoteEntryFound =
            filteredDeliveryNoteEntries.isEmpty && _peNextPage == null;
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
    return deliverynoteentries.where((entry) {
      final data = entry.data;

      final party = (data['PARTYLEDGERNAME'] ?? '').toString().toLowerCase();
      final vchno = (data['VOUCHERNUMBER'] ?? '').toString().toLowerCase();
      final vchtype = (data['VOUCHERTYPENAME'] ?? '')
          .toString()
          .toLowerCase();

      final bool matchesSearch =
          query.isEmpty ||
          party.contains(query) ||
          vchno.contains(query) ||
          vchtype.contains(query);

      final bool matchesDate = _matchesDateFilter(entry);

      return matchesSearch && matchesDate;
    }).toList();
  }

  void _applyFilters() {
    _commit(() {
      filteredDeliveryNoteEntries = _computeFilteredList();
      isVisibleNoDeliveryNoteEntryFound = filteredDeliveryNoteEntries.isEmpty;
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
    await fetchDeliveryNoteEntries();
  }
}

final pendingDeliveryNoteEntryNotifierProvider = StateNotifierProvider
    .autoDispose<
      PendingDeliveryNoteEntryNotifier,
      PendingDeliveryNoteEntryState
    >((ref) => PendingDeliveryNoteEntryNotifier());
