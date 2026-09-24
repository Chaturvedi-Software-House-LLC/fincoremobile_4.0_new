import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'api/feedback_repository.dart' show maxBugReportImages;
import 'constants.dart';
import 'providers/report_bug_notifier.dart';
import 'widgets/entry_widgets.dart';

/// `POST /bug-reports` (tally-api) - a lightweight way for testers/
/// management running a distributed APK to report issues without needing
/// their own bug-tracking access. Reachable from anywhere in the app (see
/// app_bottom_nav.dart's quick-actions sheet) since it uses the `user`-
/// scope token rather than a company-scoped one - see
/// FeedbackRepository's doc comment.
class ReportBug extends ConsumerStatefulWidget {
  const ReportBug({super.key});

  @override
  ConsumerState<ReportBug> createState() => _ReportBugState();
}

class _ReportBugState extends ConsumerState<ReportBug> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final result = await ref.read(reportBugNotifierProvider.notifier).submit(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          stepsToReproduce: _stepsController.text.trim().isEmpty
              ? null
              : _stepsController.text.trim(),
        );
    if (!mounted) return;

    showAppMessage(context, result.message, isError: !result.success);
    if (result.success) Navigator.of(context).pop();
  }

  InputDecoration _decoration(
    BuildContext context,
    String label, {
    String? hint,
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Icon(icon, size: 20, color: app_color),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      alignLabelWithHint: true,
      labelStyle: GoogleFonts.poppins(
        fontSize: 13.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      hintStyle: GoogleFonts.poppins(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
      ),
      floatingLabelStyle: GoogleFonts.poppins(
        color: app_color,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF10192B) : const Color(0xFFF6F8FB),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: app_color, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
      ),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.22 : 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportBugNotifierProvider);
    final notifier = ref.read(reportBugNotifierProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF5F6FB);

    return Scaffold(
      backgroundColor: screenBg,
      appBar: AppBar(
        backgroundColor: app_color,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        title: Text(
          'Report an Issue',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [app_color, app_color.withOpacity(0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: app_color.withOpacity(0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bug_report_outlined,
                          size: 26,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Found something wrong?',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tell us what happened and our team will look into '
                        'it. Your app version and device details are '
                        'included automatically.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Details card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: _cardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(context, 'ISSUE DETAILS'),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _titleController,
                        style: GoogleFonts.poppins(fontSize: 14.5),
                        decoration: _decoration(
                          context,
                          'Title',
                          hint: 'Short title',
                          icon: Icons.short_text_rounded,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter a short title'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _descriptionController,
                        style: GoogleFonts.poppins(fontSize: 14.5),
                        minLines: 3,
                        maxLines: 6,
                        decoration: _decoration(
                          context,
                          'What happened?',
                          hint: 'Describe the issue',
                          icon: Icons.notes_rounded,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please describe the issue'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _stepsController,
                        style: GoogleFonts.poppins(fontSize: 14.5),
                        minLines: 2,
                        maxLines: 4,
                        decoration: _decoration(
                          context,
                          'How to reproduce (optional)',
                          hint: 'What steps show the issue?',
                          icon: Icons.format_list_numbered_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Screenshots card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: _cardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _sectionLabel(context, 'SCREENSHOTS (OPTIONAL)'),
                          const Spacer(),
                          Text(
                            '${state.images.length}/$maxBugReportImages',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (int i = 0; i < state.images.length; i++)
                            _ImageThumbnail(
                              bytes: state.images[i].bytes!,
                              onRemove: () => notifier.removeImage(i),
                            ),
                          if (state.images.length < maxBugReportImages)
                            _AddImageTile(onTap: notifier.pickImages),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      // Disabled (while submitting) keeps the same solid
                      // color instead of ElevatedButton's default greyed-
                      // out disabled look - that greying is what made the
                      // spinner read as a flat, "static" circle instead of
                      // an active loading indicator.
                      disabledBackgroundColor: app_color,
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: state.isSubmitting ? null : _submit,
                    icon: state.isSubmitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            // Built explicitly per-platform rather than via
                            // CircularProgressIndicator.adaptive() - that
                            // shortcut doesn't forward `valueColor` to the
                            // iOS CupertinoActivityIndicator it renders,
                            // so it fell back to CupertinoActivityIndicator's
                            // default grey, which read as a flat dot
                            // against this button's background instead of
                            // a visibly spinning indicator.
                            child: Theme.of(context).platform ==
                                    TargetPlatform.iOS
                                ? const CupertinoActivityIndicator(
                                    color: Colors.white,
                                    animating: true,
                                  )
                                : const CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      state.isSubmitting ? 'Sending...' : 'Send Report',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddImageTile extends StatelessWidget {
  const _AddImageTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: app_color.withOpacity(isDark ? 0.12 : 0.06),
          border: Border.all(
            color: app_color.withOpacity(0.35),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              color: app_color,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              'Add',
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: app_color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            bytes,
            width: 76,
            height: 76,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
