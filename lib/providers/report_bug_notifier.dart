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

  Future<void> pickImages() async {
    final remaining = maxBugReportImages - state.images.length;
    if (remaining <= 0) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    // Silently capped - the picker has no native "limit to N selections"
    // option, and popping a message right after the user already made
    // their picks felt like a scold. The remaining slot count is visible
    // in the grid itself (the "add" tile disappears once
    // maxBugReportImages is reached), so the cap is self-explanatory.
    state = state.copyWith(
      images: [...state.images, ...result.files.take(remaining)],
    );
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
