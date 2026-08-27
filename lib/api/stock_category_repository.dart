import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/stock-categories` - a master with no
/// legacy-backend equivalent (Tally's Stock Category classification,
/// separate from Stock Group). Nothing in the app surfaces this today;
/// added so a screen can opt into showing/filtering by it once needed.
class StockCategoryRepository {
  StockCategoryRepository._();
  static final StockCategoryRepository instance = StockCategoryRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) =>
            _client.getForCompany('/stock-categories?page=$page&limit=100'),
      );
}
