import 'package:file_picker/file_picker.dart';

import 'tally_api_client.dart';

/// `tally-data/companies/:companyId/assistant/*` - the in-app AI assistant
/// (`AssistantChat.dart`). Backed by a rule-based stub today (see tally-api's
/// `assistant.service.ts`), not a real model yet - `requiresSupport` is an
/// explicit server-side flag rather than something the client infers from
/// the answer text.
class AssistantAnswer {
  const AssistantAnswer({required this.answer, required this.requiresSupport});

  final String answer;
  final bool requiresSupport;

  factory AssistantAnswer.fromJson(Map<String, dynamic> json) {
    return AssistantAnswer(
      answer: json['answer'] as String? ?? '',
      requiresSupport: json['requiresSupport'] as bool? ?? false,
    );
  }
}

class AssistantRepository {
  AssistantRepository._();
  static final AssistantRepository instance = AssistantRepository._();

  final TallyApiClient _client = TallyApiClient();

  // The backend runs real LLM inference (self-hosted Ollama, CPU-only - see
  // tally-api's assistant.module.ts) rather than a fast lookup, so this
  // needs a much longer budget than BaseApiClient's normal 20s default -
  // a real request was clocked at 20.4s server-side and got cut off by
  // that default, so the app showed a dead-end error even though the
  // backend had actually succeeded.
  static const _queryTimeout = Duration(seconds: 75);
  static const _analyzeDocumentTimeout = Duration(seconds: 90);

  Future<AssistantAnswer> askQuestion(String question) async {
    final result = await _client.postForCompany(
      '/assistant/query',
      body: {'question': question},
      timeout: _queryTimeout,
    );
    return AssistantAnswer.fromJson(result.data as Map<String, dynamic>);
  }

  Future<AssistantAnswer> analyzeDocument(
    PlatformFile file,
    String question,
  ) async {
    final result = await _client.postMultipartForCompany(
      '/assistant/analyze-document',
      fileBytes: file.bytes ?? const [],
      fileFieldName: 'file',
      fileName: file.name,
      fields: {'question': question},
      timeout: _analyzeDocumentTimeout,
    );
    return AssistantAnswer.fromJson(result.data as Map<String, dynamic>);
  }

  /// Used to be sent client-side (SMTP credentials hardcoded into the
  /// shipped app) via AssistantChat.dart's own `_sendSupportEmail` -
  /// moved server-side (see tally-api's `AssistantController.
  /// sendSupportRequest`) for exactly that reason.
  Future<void> sendSupportRequest({
    required String name,
    String? email,
    String? phone,
    required String details,
  }) async {
    await _client.postForCompany(
      '/assistant/support',
      body: {
        'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'details': details,
      },
    );
  }
}
