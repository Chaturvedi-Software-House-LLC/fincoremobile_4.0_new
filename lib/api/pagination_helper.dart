import 'base_api_client.dart';

/// Every legacy screen fetches one full, unpaginated list per query and
/// does its own sorting/filtering/bucketing client-side (ageing buckets,
/// stock valuation ranking, search) - tally-api paginates every list
/// endpoint server-side instead (max 100/page). Rather than rework that
/// client-side logic across every screen, this transparently pages through
/// every page and returns the merged full list, preserving today's UX.
///
/// [fetchPage] must call the endpoint with the given 1-based page number
/// and a fixed limit (100, tally-api's max) and return the raw [ApiResult].
Future<List<Map<String, dynamic>>> fetchAllPages(
  Future<ApiResult> Function(int page) fetchPage,
) async {
  final items = <Map<String, dynamic>>[];
  var page = 1;
  var totalPages = 1;

  do {
    final result = await fetchPage(page);
    items.addAll((result.data as List).cast<Map<String, dynamic>>());
    // tally-api's pagination meta names this field `lastPage`, never
    // `totalPages` (see PaginatedResult on the backend) - reading the wrong
    // key here silently defaulted every "fetch all pages" call to just
    // page 1, capping every list at `limit` (100) items regardless of how
    // many actually exist. Invisible with a small test dataset (page 1 was
    // everything); a real bug against any list with more than 100 rows.
    totalPages = (result.meta?['lastPage'] as int?) ?? 1;
    page++;
  } while (page <= totalPages);

  return items;
}
