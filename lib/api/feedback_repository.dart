import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'base_api_client.dart';
import 'tally_api_client.dart';

const int maxBugReportImages = 5;

/// `POST /bug-reports` - deliberately not company-scoped (unlike
/// [TallyApiClient]'s other calls) so it works for any logged-in user,
/// including before a company is ever selected. Uses [TallyApiClient.
/// postAsUser] (the `user`-scope token, saved right after tally-oauth
/// login - see auth_repository.dart's loginToTallyOauth) rather than the
/// company-user one every other call on this client uses, since that's
/// the one token guaranteed to exist regardless of company-selection
/// state.
class FeedbackRepository {
  FeedbackRepository._();
  static final FeedbackRepository instance = FeedbackRepository._();

  final TallyApiClient _client = TallyApiClient();

  Future<void> reportBug({
    required String title,
    required String description,
    String? stepsToReproduce,
    List<PlatformFile> images = const [],
  }) async {
    final deviceInfo = await _describeDevice();
    final packageInfo = await PackageInfo.fromPlatform();

    // Always multipart, even with zero images - tally-api's controller
    // parses this endpoint's body as multipart/form-data unconditionally
    // (see FeedbackController), so a plain JSON postAsUser would fail to
    // reach the fields at all.
    await _client.postMultipartFilesAsUser(
      '/bug-reports',
      fields: {
        'title': title,
        'description': description,
        if (stepsToReproduce != null && stepsToReproduce.trim().isNotEmpty)
          'stepsToReproduce': stepsToReproduce.trim(),
        'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
        'platform': Platform.operatingSystem,
        'deviceInfo': deviceInfo,
      },
      files: images
          .where((f) => f.bytes != null)
          .map(
            (f) => MultipartFileInput(bytes: f.bytes!, fileName: f.name),
          )
          .toList(),
    );
  }

  Future<String> _describeDevice() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return '${info.manufacturer} ${info.model} (Android ${info.version.release})';
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return '${info.name} (iOS ${info.systemVersion})';
      }
    } catch (_) {
      // Best-effort context only - a device-info lookup failure shouldn't
      // block submitting the report itself.
    }
    return Platform.operatingSystemVersion;
  }
}
