import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/price-levels` - replaces legacy's
/// `GET /api/item/getPriceLevelDetails/:company/:serial` used by
/// SalesRegistration.dart to resolve a stock item's price-level-specific
/// rate. tally-api's rows are keyed by `(stockMasterId, priceLevelName,
/// date)` rather than a single per-item lookup, so [ratesForItem] narrows
/// server-side by `stockMasterId` and returns every price-level row for
/// that item - the calling screen picks the one matching its selected
/// price level and effective date, same as the legacy response shape did.
class PriceLevelRepository {
  PriceLevelRepository._();
  static final PriceLevelRepository instance = PriceLevelRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/price-levels?page=$page&limit=100'),
      );

  Future<List<Map<String, dynamic>>> ratesForItem(int stockItemMasterId) =>
      fetchAllPages(
        (page) => _client.getForCompany(
          '/price-levels?page=$page&limit=100&stockMasterId=$stockItemMasterId',
        ),
      );
}
