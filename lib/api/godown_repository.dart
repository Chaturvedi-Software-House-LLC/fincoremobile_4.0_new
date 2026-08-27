import 'pagination_helper.dart';
import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/godowns` - Tally's stock-location
/// list, used by the entry-registration screens' location dropdown and to
/// resolve the `godownMasterId` a [VoucherEntryRepository.create] call's
/// inventory batch allocations need.
class GodownRepository {
  GodownRepository._();
  static final GodownRepository instance = GodownRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<List<Map<String, dynamic>>> listAll() => fetchAllPages(
        (page) => _client.getForCompany('/godowns?page=$page&limit=100'),
      );
}
