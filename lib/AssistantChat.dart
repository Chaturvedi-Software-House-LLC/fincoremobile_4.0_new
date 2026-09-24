import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/assistant_chat_notifier.dart';

// Matches the brand gradient used elsewhere in the app (see the "Live Chat"
// card in Help.dart).
const _kBrandStart = Color(0xFF6D5BFF);
const _kBrandEnd = Color(0xFF00C2CB);

String _formatMessageTime(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _formatDateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
}

// -----------------------------------------------------------------------
// Screen
// -----------------------------------------------------------------------

/// The AI Assistant chat screen.
///
/// Talks to our own self-hosted Ollama model (`qwen3:1.7b`) through the Node
/// backend's `/api/assistant/query` and `/api/assistant/analyze-document`
/// endpoints - the app's own knowledge base drives every answer, there's no
/// third-party LLM API key or usage limit involved.
class AssistantChat extends ConsumerStatefulWidget {
  const AssistantChat({super.key});

  @override
  ConsumerState<AssistantChat> createState() => _AssistantChatState();
}

class _AssistantChatState extends ConsumerState<AssistantChat> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Identity (not length) comparison - a placeholder-to-answer swap keeps
  // the same message count but is still a new `messages` list instance
  // (see AssistantChatNotifier.send), and should still auto-scroll since
  // the taller answer text can push the bubble further down. Fields that
  // don't touch `messages` (isSending, attachedFile, ...) reuse the same
  // list instance via copyWith's default, so they correctly don't
  // re-trigger a scroll.
  List<ChatMessage>? _lastMessages;
  bool _hasScrolledOnce = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    ref.read(assistantChatNotifierProvider.notifier).pickAttachment(
          result.files.single,
        );
  }

  Future<void> _send() async {
    final question = _inputController.text;
    _inputController.clear();
    await ref.read(assistantChatNotifierProvider.notifier).send(question);
  }

  // -----------------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(assistantChatNotifierProvider);

    // Same auto-scroll-to-bottom behavior the old setState-driven version
    // got for free on every message-list mutation - triggered here since
    // this build already runs on every state change.
    if (!identical(state.messages, _lastMessages)) {
      _lastMessages = state.messages;
      if (state.messages.isNotEmpty) {
        // The very first time the list has content - whether that's a
        // restored session or a brand-new chat's first message - jumps
        // instantly rather than animating, same as the old
        // `_restoreOrStartSession`'s explicit `animate: false` call.
        _scrollToBottom(animate: _hasScrolledOnce);
        _hasScrolledOnce = true;
      }
    }

    final scaffoldBg = isDark
        ? const Color(0xFF0B1220)
        : const Color(0xFFF5F6FB);
    final llmBubbleColor = isDark ? const Color(0xFF161F32) : Colors.white;
    final inputBg = isDark ? const Color(0xFF141B2E) : Colors.white;
    final inputBorder = isDark
        ? const Color(0xFF2A3550)
        : const Color(0xFFE2E5F0);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1D29);
    final subTextColor = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? _buildWelcome(subTextColor, textColor)
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              itemCount: state.messages.length,
              itemBuilder: (context, index) {
                final entry = state.messages[index];
                final showDateDivider =
                    index == 0 ||
                        !_isSameDay(
                          state.messages[index - 1].timestamp,
                          entry.timestamp,
                        );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDateDivider)
                      _buildDateDivider(entry.timestamp, subTextColor),
                    _buildMessageBubble(
                      entry,
                      llmBubbleColor,
                      textColor,
                      subTextColor,
                      isDark,
                      state,
                    ),
                  ],
                );
              },
            ),
          ),
          _buildInputBar(inputBg, inputBorder, textColor, isDark, state),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kBrandStart, _kBrandEnd],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Fincore Go Assistant',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Ask about anything in the app',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'New chat',
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: () => ref
                      .read(assistantChatNotifierProvider.notifier)
                      .endChatSession(),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome(Color subTextColor, Color textColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [_kBrandStart, _kBrandEnd]),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Hi! I'm the Fincore Go assistant. Ask me anything about "
                  'using the app - navigation, entries, parties, settings, and '
                  'more. You can also attach a PDF and ask me about it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontSize: 14.5, height: 1.4),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                'How do I create a new Sales entry?',
                "Where do I check a party's balance?",
                'How do I open Analytics?',
                'How do I turn on Face ID login?',
              ].map(_suggestionChip).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        _inputController.text = text;
        _send();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _kBrandStart.withOpacity(0.08),
          border: Border.all(color: _kBrandStart.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: _kBrandStart,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDateDivider(DateTime date, Color subTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: subTextColor.withOpacity(0.2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _formatDateLabel(date),
              style: TextStyle(
                color: subTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: subTextColor.withOpacity(0.2))),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      ChatMessage entry,
      Color llmBubbleColor,
      Color textColor,
      Color subTextColor,
      bool isDark,
      AssistantChatState state,
      ) {
    final isUser = entry.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6, bottom: 2),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [_kBrandStart, _kBrandEnd]),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 15,
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (entry.isSupportForm)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82,
                    ),
                    child: _InlineSupportForm(
                      name: state.userName,
                      email: state.userEmail,
                      isDark: isDark,
                      onSend: ({
                        required name,
                        required email,
                        required phone,
                        required details,
                      }) =>
                          ref
                              .read(assistantChatNotifierProvider.notifier)
                              .sendSupportEmail(
                                name: name,
                                email: email,
                                phone: phone,
                                details: details,
                              ),
                    ),
                  )
                else
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.74,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      gradient: isUser
                          ? const LinearGradient(
                        colors: [_kBrandStart, _kBrandEnd],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                          : null,
                      color: isUser
                          ? null
                          : (entry.isError
                          ? Colors.red.withOpacity(isDark ? 0.15 : 0.06)
                          : llmBubbleColor),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      boxShadow: isUser
                          ? null
                          : [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                            isDark ? 0.25 : 0.05,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.attachedFileName != null) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.attach_file_rounded,
                                size: 15,
                                color: isUser
                                    ? Colors.white.withOpacity(0.9)
                                    : subTextColor,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  entry.attachedFileName!,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: isUser
                                        ? Colors.white.withOpacity(0.9)
                                        : subTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (entry.text.isEmpty && !isUser)
                          _TypingWaveDots(color: textColor)
                        else
                          Text(
                            entry.text,
                            style: TextStyle(
                              color: isUser
                                  ? Colors.white
                                  : (entry.isError ? Colors.red : textColor),
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!entry.isSupportForm)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Text(
                      _formatMessageTime(entry.timestamp),
                      style: TextStyle(color: subTextColor, fontSize: 10.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(
      Color inputBg,
      Color inputBorder,
      Color textColor,
      bool isDark,
      AssistantChatState state,
      ) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.attachedFile != null)
              _buildAttachmentPreview(textColor, state.attachedFile!),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Attach PDF',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: state.isSending ? null : _pickAttachment,
                  icon: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _kBrandStart.withOpacity(isDark ? 0.18 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: _kBrandStart,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: inputBg,
                      border: Border.all(width: 1.2, color: inputBorder),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: textColor, fontSize: 15),
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 13,
                        ),
                        hintText: 'Ask me anything...',
                        hintStyle: TextStyle(
                          color: textColor.withOpacity(0.4),
                          fontSize: 15,
                        ),
                        // The app's global InputDecorationTheme sets explicit
                        // enabledBorder/focusedBorder/disabledBorder (plus
                        // filled: true) - setting only `border` doesn't
                        // override those, so every border variant needs to
                        // be nulled out here to get a truly borderless field
                        // inside our own rounded pill container.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        fillColor: Colors.transparent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: state.isSending ? null : _send,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kBrandStart, _kBrandEnd],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _kBrandStart.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(Color textColor, PlatformFile attachedFile) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Row(
        children: [
          const Icon(Icons.attach_file_rounded, size: 15, color: _kBrandStart),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              attachedFile.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            color: textColor,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => ref
                .read(assistantChatNotifierProvider.notifier)
                .clearAttachment(),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Inline "Contact Support Team" card
// -----------------------------------------------------------------------

class _InlineSupportForm extends StatefulWidget {
  const _InlineSupportForm({
    required this.name,
    required this.email,
    required this.isDark,
    required this.onSend,
  });

  final String name;
  final String email;
  final bool isDark;
  final Future<void> Function({
  required String name,
  required String email,
  required String phone,
  required String details,
  })
  onSend;

  @override
  State<_InlineSupportForm> createState() => _InlineSupportFormState();
}

enum _SupportFormStatus { idle, sending, sent, failed }

class _InlineSupportFormState extends State<_InlineSupportForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  _SupportFormStatus _status = _SupportFormStatus.idle;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _emailController = TextEditingController(text: widget.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() => _status = _SupportFormStatus.sending);
    try {
      await widget.onSend(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text.trim(),
        details: message,
      );
      if (mounted) setState(() => _status = _SupportFormStatus.sent);
    } catch (_) {
      if (mounted) setState(() => _status = _SupportFormStatus.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? const Color(0xFF161F32) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1D29);
    final subTextColor = isDark ? Colors.white54 : Colors.black45;
    final fieldBg = isDark ? const Color(0xFF0F1626) : const Color(0xFFF5F6FB);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_kBrandStart, _kBrandEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Contact Support Team',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Looks like I couldn't fully help with that. Send our "
                      "support team a message below and we'll get back to you.",
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                if (_status == _SupportFormStatus.sent)
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Message sent - our team will reach out to you '
                              'shortly.',
                          style: TextStyle(color: textColor, fontSize: 13),
                        ),
                      ),
                    ],
                  )
                else ...[
                  _field(
                    'Name',
                    _nameController,
                    fieldBg,
                    textColor,
                    subTextColor,
                    enabled: false,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    'Email',
                    _emailController,
                    fieldBg,
                    textColor,
                    subTextColor,
                    enabled: false,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    'Contact Number',
                    _phoneController,
                    fieldBg,
                    textColor,
                    subTextColor,
                    enabled: _status != _SupportFormStatus.sending,
                    hint: 'Your phone number (optional)',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    'Message',
                    _messageController,
                    fieldBg,
                    textColor,
                    subTextColor,
                    enabled: _status != _SupportFormStatus.sending,
                    maxLines: 3,
                    hint: 'Describe what you need help with...',
                  ),
                  if (_status == _SupportFormStatus.failed) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Could not send the message. Please try again.',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _status == _SupportFormStatus.sending
                          ? null
                          : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandStart,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _status == _SupportFormStatus.sending
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            Colors.white,
                          ),
                        ),
                      )
                          : const Text(
                        'Send',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
      String label,
      TextEditingController controller,
      Color fieldBg,
      Color textColor,
      Color subTextColor, {
        required bool enabled,
        int maxLines = 1,
        String? hint,
        TextInputType? keyboardType,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: subTextColor,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(color: textColor, fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: subTextColor.withOpacity(0.6)),
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBrandStart, width: 1.4),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------
// Typing indicator
// -----------------------------------------------------------------------

class _TypingWaveDots extends StatefulWidget {
  const _TypingWaveDots({required this.color});
  final Color color;

  @override
  State<_TypingWaveDots> createState() => _TypingWaveDotsState();
}

class _TypingWaveDotsState extends State<_TypingWaveDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = (_controller.value + i * 0.2) % 1.0;
              final bounceHeight = 4.0;
              final bounce = (math.sin(phase * 2 * math.pi)).abs();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Transform.translate(
                  offset: Offset(0, -bounceHeight * bounce),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
