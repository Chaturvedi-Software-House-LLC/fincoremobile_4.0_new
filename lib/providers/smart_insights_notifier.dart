import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dashboard_repository.dart';

/// State for the Dashboard's "Smart Insights" card - a short list of
/// AI-narrated bullet points (`narrative`) grounded in server-computed
/// figures (`facts`, kept around for a "View details" expansion, not
/// currently rendered directly). See `smart-insights.service.ts` for how
/// `facts` are computed (plain SQL, never the model) and `narrative`
/// generated (the model paraphrasing those exact numbers).
class SmartInsightsState {
  final bool isLoading;
  final String? error;
  final List<String> narrative;
  final Map<String, dynamic>? facts;

  const SmartInsightsState({
    required this.isLoading,
    required this.error,
    required this.narrative,
    required this.facts,
  });

  const SmartInsightsState.initial()
    : isLoading = false,
      error = null,
      narrative = const [],
      facts = null;

  SmartInsightsState copyWith({
    bool? isLoading,
    String? error,
    List<String>? narrative,
    Map<String, dynamic>? facts,
  }) => SmartInsightsState(
    isLoading: isLoading ?? this.isLoading,
    error: error,
    narrative: narrative ?? this.narrative,
    facts: facts ?? this.facts,
  );
}

/// Fetches and holds the Dashboard's Smart Insights card state.
/// `autoDispose` - re-fetches fresh every time the Dashboard is opened,
/// same as this app's other per-screen notifiers, rather than caching
/// stale figures across visits.
class SmartInsightsNotifier extends StateNotifier<SmartInsightsState> {
  SmartInsightsNotifier() : super(const SmartInsightsState.initial());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await DashboardRepository.instance.insights();
      final narrative = (data['narrative'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        narrative: narrative,
        facts: data['facts'] as Map<String, dynamic>?,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load insights right now.',
      );
    }
  }
}

final smartInsightsNotifierProvider =
    StateNotifierProvider.autoDispose<SmartInsightsNotifier, SmartInsightsState>(
      (ref) => SmartInsightsNotifier(),
    );
