import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

/// Riverpod migration of `AssistantChat.dart`'s `_AssistantChatState`.
///
/// `TextEditingController`/`ScrollController` stay widget-local (unchanged,
/// in `AssistantChat.dart`) - everything else (messages, session
/// persistence/timeout, the send flow, intent detection) moved here so it
/// survives independent of the widget's own lifecycle concerns.
class ChatMessage {
  ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.attachedFileName,
    this.isSupportForm = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String text;
  final bool isUser;
  final bool isError;
  final String? attachedFileName;
  final bool isSupportForm;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'isError': isError,
    'attachedFileName': attachedFileName,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'] as String? ?? '',
    isUser: json['isUser'] as bool? ?? false,
    isError: json['isError'] as bool? ?? false,
    attachedFileName: json['attachedFileName'] as String?,
    // Support-form entries are never persisted/restored as a live form -
    // they collapse to a plain message so a restored session doesn't show a
    // stale, non-functional card.
    isSupportForm: false,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ??
        DateTime.now(),
  );
}

class AssistantChatState {
  final List<ChatMessage> messages;
  final bool hasActiveCompany;
  final String userName;
  final String userEmail;
  final PlatformFile? attachedFile;
  final bool isSending;
  final bool awaitingCloseConfirmation;

  const AssistantChatState({
    this.messages = const [],
    this.hasActiveCompany = false,
    this.userName = '',
    this.userEmail = '',
    this.attachedFile,
    this.isSending = false,
    this.awaitingCloseConfirmation = false,
  });

  AssistantChatState copyWith({
    List<ChatMessage>? messages,
    bool? hasActiveCompany,
    String? userName,
    String? userEmail,
    PlatformFile? attachedFile,
    bool clearAttachedFile = false,
    bool? isSending,
    bool? awaitingCloseConfirmation,
  }) {
    return AssistantChatState(
      messages: messages ?? this.messages,
      hasActiveCompany: hasActiveCompany ?? this.hasActiveCompany,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      attachedFile: clearAttachedFile
          ? null
          : (attachedFile ?? this.attachedFile),
      isSending: isSending ?? this.isSending,
      awaitingCloseConfirmation:
          awaitingCloseConfirmation ?? this.awaitingCloseConfirmation,
    );
  }
}

class AssistantChatNotifier extends StateNotifier<AssistantChatState> {
  final Ref _ref;

  AssistantChatNotifier(this._ref) : super(const AssistantChatState()) {
    _init();
  }

  Timer? _sessionTimer;

  // How long a chat session stays resumable after the user's last message -
  // both while the screen stays open (the idle auto-end timer) and after
  // leaving the screen entirely (re-entering within this window restores
  // the conversation; past it, a fresh chat starts instead).
  static const _sessionTimeout = Duration(minutes: 15);
  static const _prefsMessagesKey = 'assistant_chat_messages';
  static const _prefsLastInputKey = 'assistant_chat_last_input_at';

  // -----------------------------------------------------------------------
  // Bootstrap / session persistence
  // -----------------------------------------------------------------------

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final companyGuid = await _ref.read(tokenStoreProvider).activeCompanyGuid;
    state = state.copyWith(
      hasActiveCompany: companyGuid != null,
      userName: prefs.getString('name_nav') ?? '',
      userEmail: prefs.getString('email_nav') ?? '',
    );
    await _restoreOrStartSession(prefs);
  }

  Future<void> _restoreOrStartSession(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsMessagesKey);
    final lastInputIso = prefs.getString(_prefsLastInputKey);
    if (raw == null || lastInputIso == null) return;

    final lastInput = DateTime.tryParse(lastInputIso);
    if (lastInput == null) return;

    final elapsed = DateTime.now().difference(lastInput);
    if (elapsed >= _sessionTimeout) {
      await _clearPersistedSession(prefs);
      return;
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final restored = list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(messages: restored);
      _scheduleSessionTimeout(_sessionTimeout - elapsed);
    } catch (_) {
      // Corrupt persisted state - just start fresh.
      await _clearPersistedSession(prefs);
    }
  }

  void _scheduleSessionTimeout(Duration remaining) {
    _sessionTimer?.cancel();
    final delay = remaining.isNegative ? Duration.zero : remaining;
    _sessionTimer = Timer(delay, endChatSession);
  }

  Future<void> _persistSession({required bool isUserInput}) async {
    final prefs = await SharedPreferences.getInstance();
    final persistable = state.messages
        .where((m) => !m.isSupportForm)
        .toList();
    await prefs.setString(
      _prefsMessagesKey,
      jsonEncode(persistable.map((m) => m.toJson()).toList()),
    );
    if (isUserInput) {
      await prefs.setString(
        _prefsLastInputKey,
        DateTime.now().toIso8601String(),
      );
    }
  }

  Future<void> _clearPersistedSession(SharedPreferences prefs) async {
    await prefs.remove(_prefsMessagesKey);
    await prefs.remove(_prefsLastInputKey);
  }

  void endChatSession() {
    _sessionTimer?.cancel();
    state = state.copyWith(
      messages: [],
      isSending: false, // stop any stuck typing indicator
      awaitingCloseConfirmation: false,
    );
    SharedPreferences.getInstance().then(_clearPersistedSession);
  }

  @override
  void dispose() {
    // Deliberately does NOT clear the persisted session - leaving the
    // screen alone doesn't end the chat. Re-entering within
    // _sessionTimeout of the last reply (checked in
    // _restoreOrStartSession, against the persisted timestamp - not this
    // timer, which dies with the notifier) resumes the same conversation;
    // past that window it starts fresh. Only cancel the in-screen idle
    // timer itself, since it can't fire once this notifier is gone anyway.
    _sessionTimer?.cancel();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Intent detection helpers - word-based, not exact-phrase matching, so
  // natural variations in phrasing ("end this", "end this conversation",
  // "please end chat") are all recognized.
  // -----------------------------------------------------------------------

  static const _humanSupportMarkers = [
    'agent',
    'human',
    'contact support',
    'talk to someone',
    'real person',
    'customer support',
    'support team',
  ];

  bool _wantsHumanSupport(String text) {
    final lower = text.toLowerCase();
    return _humanSupportMarkers.any(lower.contains);
  }

  static const _deadEndMarkers = [
    'cannot provide',
    "can't help with that",
    "i'm not sure",
    'not sure about that',
    "don't have that information",
    'coming soon',
    // Deliberately NOT "contact support" - the backend's own correct,
    // complete answers for unsupported voucher types/features legitimately
    // end with "...please contact support (More -> Help) to request it."
    // Treating that phrase as a failure signal caused the escalation card
    // to double-trigger right after a perfectly good answer.
  ];

  bool _looksLikeDeadEnd(String answerText) {
    final lower = answerText.toLowerCase();
    return _deadEndMarkers.any(lower.contains);
  }

  static const _stuckMarkers = [
    "don't want",
    "doesn't work",
    'not helping',
    'not working',
    'still not',
    "that's not",
    'useless',
    "isn't helping",
  ];

  bool _userSeemsStuck(String text) {
    final lower = text.toLowerCase();
    return _stuckMarkers.any(lower.contains);
  }

  static const _endWords = ['end', 'stop', 'close', 'quit', 'exit', 'bye'];
  static const _targetWords = ['chat', 'conversation', 'session', 'this'];

  bool _isEndIntent(String text) {
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final hasEndWord = words.any(_endWords.contains);
    final hasTargetWord = words.any(_targetWords.contains);
    return hasEndWord && hasTargetWord;
  }

  bool _isBareEndWord(String text) {
    final trimmed = text.trim().toLowerCase();
    return _endWords.contains(trimmed);
  }

  static const _closingSmallTalkMarkers = [
    'thanks',
    'thank you',
    'that helped',
    'appreciate it',
    'ok bye',
    'goodbye',
  ];

  bool _isClosingSmallTalk(String text) {
    final lower = text.toLowerCase();
    return _closingSmallTalkMarkers.any(lower.contains);
  }

  static const _negativeWords = ['no', 'nope', 'nah'];
  bool _isNegativeReply(String text) {
    final trimmed = text.trim().toLowerCase();
    return _negativeWords.contains(trimmed);
  }

  static const _affirmativeWords = ['yes', 'yeah', 'yep', 'sure', 'ok', 'okay'];
  bool _isBareAffirmative(String text) {
    final trimmed = text.trim().toLowerCase();
    return _affirmativeWords.contains(trimmed);
  }

  // -----------------------------------------------------------------------
  // Sending
  // -----------------------------------------------------------------------

  void pickAttachment(PlatformFile file) {
    state = state.copyWith(attachedFile: file);
  }

  void clearAttachment() {
    state = state.copyWith(clearAttachedFile: true);
  }

  Future<void> send(String rawQuestion) async {
    final question = rawQuestion.trim();
    final file = state.attachedFile;
    if (question.isEmpty && file == null) return;

    _scheduleSessionTimeout(_sessionTimeout);

    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(text: question, isUser: true, attachedFileName: file?.name),
      ],
      clearAttachedFile: true,
    );
    await _persistSession(isUserInput: true);

    final wasAwaitingClose = state.awaitingCloseConfirmation;
    state = state.copyWith(awaitingCloseConfirmation: false);

    if (wasAwaitingClose) {
      if (_isNegativeReply(question) ||
          _isEndIntent(question) ||
          _isBareEndWord(question)) {
        endChatSession();
        return;
      }
      if (_isBareAffirmative(question)) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage(
              text: 'Sure - what would you like help with?',
              isUser: false,
            ),
          ],
        );
        await _persistSession(isUserInput: false);
        return;
      }
      // Otherwise fall through and treat it as a normal new question.
    }

    if (_wantsHumanSupport(question)) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(text: '', isUser: false, isSupportForm: true),
        ],
      );
      await _persistSession(isUserInput: false);
      return;
    }

    if (question.isNotEmpty && _isEndIntent(question)) {
      endChatSession();
      return;
    }

    if (question.isNotEmpty && _isClosingSmallTalk(question)) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            text: 'Happy to help! Want to ask something else, or should I '
                'end this chat?',
            isUser: false,
          ),
        ],
        awaitingCloseConfirmation: true,
      );
      await _persistSession(isUserInput: false);
      return;
    }

    // The assistant is scoped to the active company (tally-api's
    // `/tally-data/companies/:companyId/assistant/*`) - without one
    // selected there's no companyId to call it with.
    if (!state.hasActiveCompany) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            text: "The AI Assistant isn't available for your account yet.",
            isUser: false,
          ),
          ChatMessage(text: '', isUser: false, isSupportForm: true),
        ],
      );
      await _persistSession(isUserInput: false);
      return;
    }

    state = state.copyWith(isSending: true);
    final placeholder = ChatMessage(text: '', isUser: false);
    state = state.copyWith(messages: [...state.messages, placeholder]);

    try {
      final result = file != null
          ? await _ref.read(assistantRepositoryProvider).analyzeDocument(
                file,
                question,
              )
          : await _ref.read(assistantRepositoryProvider).askQuestion(
                question,
              );
      if (result.answer.trim().isEmpty) {
        throw Exception('Empty response from assistant');
      }
      final answerText = result.answer.trim();

      state = state.copyWith(
        messages: [
          ...state.messages.where((m) => m != placeholder),
          ChatMessage(text: answerText, isUser: false),
        ],
      );

      // requiresSupport is an explicit server-side flag (set only by the
      // unsupported-voucher-type guardrail) - more reliable than trying to
      // text-match "contact support" in the answer, which previously either
      // double-triggered on the guardrail's own answer or, after that was
      // fixed, never triggered at all for it.
      if (result.requiresSupport ||
          _looksLikeDeadEnd(answerText) ||
          _userSeemsStuck(question)) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage(text: '', isUser: false, isSupportForm: true),
          ],
        );
      }
    } catch (e) {
      // Couldn't reach the backend/model at all - don't just show a dead
      // error message, go straight to the "contact support" escalation
      // so the user has somewhere to go instead of a dead end.
      state = state.copyWith(
        messages: [
          ...state.messages.where((m) => m != placeholder),
          ChatMessage(text: '', isUser: false, isSupportForm: true),
        ],
      );
    } finally {
      state = state.copyWith(isSending: false);
      await _persistSession(isUserInput: false);
    }
  }

  /// Sent server-side now (see tally-api's `AssistantController.
  /// sendSupportRequest`) - this used to build and send the email
  /// directly from the app with the SMTP password hardcoded into the
  /// shipped client.
  Future<void> sendSupportEmail({
    required String name,
    required String email,
    required String phone,
    required String details,
  }) async {
    await _ref.read(assistantRepositoryProvider).sendSupportRequest(
          name: name,
          email: email,
          phone: phone,
          details: details,
        );
  }
}

final assistantChatNotifierProvider = StateNotifierProvider.autoDispose<
    AssistantChatNotifier, AssistantChatState>((ref) => AssistantChatNotifier(ref));
