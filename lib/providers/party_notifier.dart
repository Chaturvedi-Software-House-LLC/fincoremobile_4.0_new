import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Party.dart';
import '../api/api_exception.dart';
import 'repository_providers.dart';

class PartyState {
  final bool isLoading;
  final bool isLoadingMoreParties;
  final bool isVisibleNoDataFound;
  final bool isAllList;
  final bool isClickedAllParties;
  final bool isClickedInactiveParties;
  final String selectedParty;
  final List<String> spinnerList;
  final List<party> partiesList;
  final List<party> filteredItemsParties;
  final String partyCount;
  final String partyText;
  final String company;
  final String? errorMessage;

  const PartyState({
    this.isLoading = false,
    this.isLoadingMoreParties = false,
    this.isVisibleNoDataFound = false,
    this.isAllList = false,
    this.isClickedAllParties = false,
    this.isClickedInactiveParties = false,
    this.selectedParty = 'All Parties',
    this.spinnerList = const ['All Parties'],
    this.partiesList = const [],
    this.filteredItemsParties = const [],
    this.partyCount = '0',
    this.partyText = 'Party',
    this.company = '',
    this.errorMessage,
  });

  PartyState copyWith({
    bool? isLoading,
    bool? isLoadingMoreParties,
    bool? isVisibleNoDataFound,
    bool? isAllList,
    bool? isClickedAllParties,
    bool? isClickedInactiveParties,
    String? selectedParty,
    List<String>? spinnerList,
    List<party>? partiesList,
    List<party>? filteredItemsParties,
    String? partyCount,
    String? partyText,
    String? company,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PartyState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMoreParties: isLoadingMoreParties ?? this.isLoadingMoreParties,
      isVisibleNoDataFound: isVisibleNoDataFound ?? this.isVisibleNoDataFound,
      isAllList: isAllList ?? this.isAllList,
      isClickedAllParties: isClickedAllParties ?? this.isClickedAllParties,
      isClickedInactiveParties:
          isClickedInactiveParties ?? this.isClickedInactiveParties,
      selectedParty: selectedParty ?? this.selectedParty,
      spinnerList: spinnerList ?? this.spinnerList,
      partiesList: partiesList ?? this.partiesList,
      filteredItemsParties: filteredItemsParties ?? this.filteredItemsParties,
      partyCount: partyCount ?? this.partyCount,
      partyText: partyText ?? this.partyText,
      company: company ?? this.company,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PartyNotifier extends StateNotifier<PartyState> {
  final Ref _ref;

  static const int _partyPageLimit = 30;

  // Populated by fetchParentData from tally-api's party-like groups (see
  // LedgerRepository's doc comment on the group-name/reservedName match it
  // uses in place of the legacy `ledGroups` server-side filter). Not part of
  // PartyState - never read directly in build(), only consulted by the
  // fetch/paging methods below.
  final Map<String, int> _groupMasterIdByName = {};

  // --- Incremental (infinite-scroll) paging state for the "All Parties"
  // tab, mirroring the pre-migration State fields of the same name. Kept as
  // plain notifier fields (not PartyState) since none of them is read
  // directly in build() - only isLoadingMoreParties (which IS in
  // PartyState) drives a rebuild.
  List<int> _pagingGroupIds = [];
  int _pagingGroupIndex = 0;
  int _pagingPage = 1;
  bool _pagingHasMore = false;

  // Bumped every time `_startPartyPaging` (re)starts (e.g. switching the
  // group-filter dropdown while a previous filter's page-walk is still in
  // flight) - every page-load result below is stamped with the generation
  // active when it *started* and discarded on arrival if a newer one has
  // since begun, same pattern as Transactions.dart's `_txRequestGen`.
  int _partyRequestGen = 0;

  bool _isAutoSearchLoadingParties = false;

  // Mirrors the live text of the widget's search box. `applyFilter` is
  // called on every onChanged, so this always tracks what the widget's
  // TextEditingController currently holds - the search-box controller
  // itself stays widget-local (see Party.dart), but the background
  // auto-load loop below needs to re-check the "current" query while it
  // awaits a page load, same as the pre-migration code re-read
  // `searchController.text` live.
  String _searchQuery = '';

  PartyNotifier(this._ref) : super(const PartyState()) {
    _init();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('company_name') ?? '';
    state = state.copyWith(company: company);
    await fetchParentData();
  }

  /// Populates the "parent" dropdown from tally-api's party-like groups.
  Future<void> fetchParentData() async {
    state = state.copyWith(isLoading: true);
    try {
      final groups =
          await _ref.read(ledgerRepositoryProvider).listPartyGroups();
      _groupMasterIdByName.clear();
      final spinner = <String>['All Parties'];
      for (final group in groups) {
        final name = group['name'] as String;
        _groupMasterIdByName[name] = group['masterId'] as int;
        spinner.add(name);
      }
      state = state.copyWith(
        spinnerList: spinner,
        selectedParty: spinner[0],
        isClickedAllParties: true,
        isClickedInactiveParties: false,
      );
      fetchPartyData(state.selectedParty);
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }
  }

  void fetchPartyData(String partyGroup) {
    final groupIds = partyGroup == 'All Parties'
        ? _groupMasterIdByName.values.toList()
        : (_groupMasterIdByName[partyGroup] == null
              ? <int>[]
              : [_groupMasterIdByName[partyGroup]!]);
    _startPartyPaging(groupIds);
  }

  void fetchInactivePartyData(String partyGroup, String date) {
    fetchInactiveParties(
      partyGroup == 'All Parties' ? null : _groupMasterIdByName[partyGroup],
      date,
    );
  }

  /// Selecting a group from the dropdown - sets the active tab + selected
  /// group, then (re)starts paging for it.
  void selectPartyGroup(String value) {
    state = state.copyWith(
      selectedParty: value,
      isClickedAllParties: true,
      isClickedInactiveParties: false,
    );
    fetchPartyData(value);
  }

  /// "All Parties" toggle tapped.
  void showAllPartiesTab() {
    state = state.copyWith(
      isClickedAllParties: true,
      isClickedInactiveParties: false,
    );
    fetchPartyData(state.selectedParty);
  }

  /// "Inactive Parties" toggle tapped - clears the current list/counts
  /// before the "how many days" dialog is shown; the actual fetch happens
  /// once the user submits that dialog, via [fetchInactivePartyData].
  void prepareInactiveTab() {
    state = state.copyWith(
      isClickedAllParties: false,
      isClickedInactiveParties: true,
      filteredItemsParties: const [],
      partiesList: const [],
      partyCount: '0',
      partyText: 'Party',
    );
  }

  /// Re-applies the search box's filter over whatever has been loaded so
  /// far. **Narrower than a full-list search**: tally-api's `/ledgers` list
  /// has no server-side name-search query param, so this only searches the
  /// pages already fetched by infinite scroll, not the whole company's
  /// parties - matching more of them as the user scrolls further (or
  /// searches after scrolling down) rather than all at once.
  ///
  /// The background auto-load loop below keeps loading pages while a query
  /// has zero matches so far and more pages remain (`_pagingHasMore`), so a
  /// party that exists but sits on a page not yet loaded isn't wrongly
  /// reported as "no match". Naturally a no-op on the Inactive Parties tab,
  /// which never sets `_pagingHasMore` true (its full result set is already
  /// loaded up front).
  void applyFilter(String query) {
    _searchQuery = query.toLowerCase();
    _recomputeFilter();
    if (_searchQuery.isNotEmpty &&
        state.filteredItemsParties.isEmpty &&
        _pagingHasMore) {
      _autoLoadPartyPagesForSearch();
    }
  }

  void _recomputeFilter() {
    final value = _searchQuery;
    final filtered = value.isEmpty
        ? state.partiesList
        : state.partiesList
              .where((item) => item.partyname.toLowerCase().contains(value))
              .toList();
    state = state.copyWith(
      filteredItemsParties: filtered,
      partyCount: filtered.length.toString(),
      partyText: filtered.length == 1 ? 'Party' : 'Parties',
    );
  }

  Future<void> _autoLoadPartyPagesForSearch() async {
    if (_isAutoSearchLoadingParties) return;
    _isAutoSearchLoadingParties = true;
    try {
      while (true) {
        final query = _searchQuery;
        if (query.isEmpty || !_pagingHasMore) break;
        final hasMatch = state.partiesList.any(
          (item) => item.partyname.toLowerCase().contains(query),
        );
        if (hasMatch) break;

        await loadNextPartyPage();

        final stillQuery = _searchQuery;
        if (stillQuery.isEmpty) break;
        final filtered = state.partiesList
            .where((item) => item.partyname.toLowerCase().contains(stillQuery))
            .toList();
        state = state.copyWith(
          filteredItemsParties: filtered,
          partyCount: filtered.length.toString(),
          partyText: filtered.length == 1 ? 'Party' : 'Parties',
          isVisibleNoDataFound: filtered.isEmpty && !_pagingHasMore,
        );
      }
    } finally {
      _isAutoSearchLoadingParties = false;
    }
  }

  /// Resets and starts (or restarts) the "All Parties" tab's incremental
  /// paging queue over [groupIds], then loads the first page. Bumps
  /// [_partyRequestGen] so a still-in-flight older filter's page load can
  /// never land after this one - see that field's doc comment.
  Future<void> _startPartyPaging(List<int> groupIds) async {
    _partyRequestGen++;
    _searchQuery = '';
    state = state.copyWith(
      partyCount: '0',
      partyText: 'Party',
      isLoading: true,
      isAllList: false,
      isVisibleNoDataFound: false,
      partiesList: const [],
      filteredItemsParties: const [],
    );

    _pagingGroupIds = groupIds;
    _pagingGroupIndex = 0;
    _pagingPage = 1;
    _pagingHasMore = groupIds.isNotEmpty;

    await loadNextPartyPage();
  }

  /// Loads one more page of parties (30 rows), moving on to the next group
  /// in [_pagingGroupIds] once the current one is exhausted. Called for the
  /// first page by [_startPartyPaging] and for every subsequent page by the
  /// widget's scroll-near-bottom listener.
  ///
  /// Auto-chains through any number of consecutive EMPTY groups (bounded by
  /// [_pagingGroupIds]'s length) rather than stopping after the first one -
  /// real party ledgers are often nested under a sub-group ("Local
  /// Customers" under "Sundry Debtors") rather than sitting directly in the
  /// top-level reserved group, so the very first group in the queue coming
  /// back empty is a normal, expected case, not "no data".
  Future<void> loadNextPartyPage() async {
    if (state.isLoadingMoreParties || !_pagingHasMore) return;
    if (_pagingGroupIndex >= _pagingGroupIds.length) {
      _pagingHasMore = false;
      return;
    }

    final myGen = _partyRequestGen;
    state = state.copyWith(isLoadingMoreParties: true);
    final updatedParties = List<party>.from(state.partiesList);

    try {
      while (_pagingGroupIndex < _pagingGroupIds.length) {
        final groupId = _pagingGroupIds[_pagingGroupIndex];
        final result = await _ref
            .read(ledgerRepositoryProvider)
            .listLedgersPage(
              page: _pagingPage,
              limit: _partyPageLimit,
              groupMasterId: groupId,
            );
        if (myGen != _partyRequestGen) {
          // Superseded while awaiting - a newer filter selection already
          // cleared/restarted the list; don't apply this stale page.
          state = state.copyWith(isLoadingMoreParties: false);
          return;
        }
        updatedParties.addAll(result.items.map(party.fromJson));

        if (result.hasMore) {
          _pagingPage++;
          break;
        } else {
          _pagingGroupIndex++;
          _pagingPage = 1;
          if (result.items.isNotEmpty) break;
          // Empty page from this group - keep walking the queue instead of
          // stopping here, so a party-less top-level group doesn't hide
          // every other group's parties.
        }
      }
      _pagingHasMore = _pagingGroupIndex < _pagingGroupIds.length;

      state = state.copyWith(partiesList: updatedParties);
      _recomputeFilter();
      state = state.copyWith(
        isAllList: true,
        isLoading: false,
        isLoadingMoreParties: false,
        isVisibleNoDataFound: updatedParties.isEmpty,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isAllList: updatedParties.isNotEmpty,
        isLoading: false,
        isLoadingMoreParties: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isAllList: updatedParties.isNotEmpty,
        isLoading: false,
        isLoadingMoreParties: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }
  }

  Future<void> fetchInactiveParties(int? groupMasterId, String date) async {
    state = state.copyWith(
      partyCount: '0',
      isLoading: true,
      isAllList: false,
      isVisibleNoDataFound: false,
      filteredItemsParties: const [],
      partiesList: const [],
    );

    try {
      final rows = await _ref
          .read(ledgerRepositoryProvider)
          .listInactiveLedgers(
            asOf: DateTime.parse(date),
            groupMasterId: groupMasterId,
          );
      final list = rows.map(party.fromJson).toList();

      // A ledger with no voucher activity ever has a null lastVoucherDate
      // (party.fromJson maps that to '') - sorts last rather than throwing,
      // unlike a bare DateTime.parse would on an empty string.
      list.sort((a, b) {
        final dateA = DateTime.tryParse(a.maxdate);
        final dateB = DateTime.tryParse(b.maxdate);
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });

      state = state.copyWith(
        partiesList: list,
        filteredItemsParties: list,
        partyCount: list.length.toString(),
        partyText: list.length == 1 ? 'Party' : 'Parties',
        isAllList: true,
        isLoading: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        isAllList: false,
        isLoading: false,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isAllList: false,
        isLoading: false,
        errorMessage: 'Could not reach the server. Please try again.',
      );
    }

    if (state.partiesList.isEmpty) {
      state = state.copyWith(
        partyCount: '0',
        partyText: 'Party',
        isAllList: false,
        isVisibleNoDataFound: true,
        isLoading: false,
      );
    }
  }

  /// Fetches the full, unpaginated party list on demand for PDF/CSV export
  /// - export is an occasional explicit action (not the initial screen
  /// render infinite-scroll is optimizing), so it's fine for it to fetch
  /// everything rather than being limited to whatever's been scrolled into
  /// view so far. [query] is the widget search box's current text (kept
  /// widget-local - see Party.dart), lowercased and applied the same way
  /// [applyFilter] applies it.
  Future<List<party>> fullPartiesForExport(String query) async {
    if (state.isClickedInactiveParties) {
      // Inactive Parties never uses incremental paging (see
      // fetchInactiveParties) - filteredItemsParties already holds its
      // full, sorted result set.
      return state.filteredItemsParties;
    }
    final groupMasterId = state.selectedParty == 'All Parties'
        ? null
        : _groupMasterIdByName[state.selectedParty];
    final rows = await _ref
        .read(ledgerRepositoryProvider)
        .listLedgers(groupMasterId: groupMasterId);
    final all = rows.map(party.fromJson).toList();
    final value = query.toLowerCase();
    return value.isEmpty
        ? all
        : all
              .where((item) => item.partyname.toLowerCase().contains(value))
              .toList();
  }
}

final partyNotifierProvider =
    StateNotifierProvider.autoDispose<PartyNotifier, PartyState>(
  (ref) => PartyNotifier(ref),
);
