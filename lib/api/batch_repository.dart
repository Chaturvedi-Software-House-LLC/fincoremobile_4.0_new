import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/batches` - Tally's batch/serial
/// tracking per stock item (expiry date, manufacturing date, godown). Used
/// by entry screens for stock items that are batch-tracked, to populate
/// the batch-selection dropdown the same way legacy's batch lookup did.
class BatchRepository {
  BatchRepository._();
  static final BatchRepository instance = BatchRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/batches?page=$page&limit=100'),
      );

  Future<List<Map<String, dynamic>>> forItem(int stockItemMasterId) =>
      fetchAllPages(
        (page) => _client.getForCompany(
          '/batches?page=$page&limit=100&stockMasterId=$stockItemMasterId',
        ),
      );
}
