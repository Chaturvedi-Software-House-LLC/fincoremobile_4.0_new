import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/feedback_repository.dart';
import 'repository_providers.dart';

class ReportBugState {
  final List<PlatformFile> images;
  final bool isSubmitting;

  const ReportBugState({this.images = const [], this.isSubmitting = false});

  ReportBugState copyWith({List<PlatformFile>? images, bool? isSubmitting}) {
    return ReportBugState(
      images: images ?? this.images,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

/// Result of a submit attempt, so the widget can show a message/pop without
/// the notifier reaching into `BuildContext`.
class ReportBugResult {
  final bool success;
  final String message;

  const ReportBugResult(this.success, this.message);
}

class ReportBugNotifier extends StateNotifier<ReportBugState> {
  final Ref _ref;

  ReportBugNotifier(this._ref) : super(const ReportBugState());

  /// Returns a message to show the user only when their selection had to
  /// be truncated - the native picker has no "limit to N selections"
  /// option, so it happily lets someone tick a 6th photo, but the app
  /// still only keeps the first [remaining] of them. Without this, a
  /// truncated pick looked like a silent bug ("I picked 6, why are there
  /// only 5?") rather than an enforced cap.
  Future<String?> pickImages() async {
    final remaining = maxBugReportImages - state.images.length;
    if (remaining <= 0) return null;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    state = state.copyWith(
      images: [...state.images, ...result.files.take(remaining)],
    );

    if (result.files.length > remaining) {
      return 'Only $remaining of ${result.files.length} photos were added '
          '- up to $maxBugReportImages screenshots are allowed.';
    }
    return null;
  }

  void removeImage(int index) {
    final updated = [...state.images]..removeAt(index);
    state = state.copyWith(images: updated);
  }

  Future<ReportBugResult> submit({
    required String title,
    required String description,
    String? stepsToReproduce,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _ref.read(feedbackRepositoryProvider).reportBug(
            title: title,
            description: description,
            stepsToReproduce: stepsToReproduce,
            images: state.images,
          );
      state = state.copyWith(isSubmitting: false);
      return const ReportBugResult(
        true,
        'Thanks! Your bug report has been sent.',
      );
    } on ApiException catch (e) {
      state = state.copyWith(isSubmitting: false);
      return ReportBugResult(false, e.message);
    } catch (e) {
      state = state.copyWith(isSubmitting: false);
      return const ReportBugResult(
        false,
        'Could not reach the server. Please try again.',
      );
    }
  }
}

final reportBugNotifierProvider =
    StateNotifierProvider.autoDispose<ReportBugNotifier, ReportBugState>(
  (ref) => ReportBugNotifier(ref),
);
