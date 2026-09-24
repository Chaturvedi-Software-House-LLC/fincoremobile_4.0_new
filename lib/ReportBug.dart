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

  Future<void> _pickImages() async {
    final message =
        await ref.read(reportBugNotifierProvider.notifier).pickImages();
    if (!mounted || message == null) return;
    showAppMessage(context, message);
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

  // White (dark-mode: a touch lighter than the card) rather than the app's
  // global grey-tinted field fill (`lightField`/`darkField` in main.dart) -
  // on this screen's plain background that grey read as dull/washed out,
  // so the field itself is white/near-card with just a crisp border to
  // define its edges instead of a fill-color difference doing the work.
  // The icon lives in [_fieldLabel] above the field, not as a
  // `prefixIcon` - Flutter vertically centers a `prefixIcon` in the whole
  // decorated box, which looks fine on a single-line field but drifts
  // away from the label/text once a field spans multiple lines
  // (description/steps), landing at the box's vertical center instead of
  // by the label.
  Widget _fieldLabel(
    BuildContext context,
    IconData icon,
    String label, {
    String? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: app_color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Borderless with a soft drop shadow (via [_fieldShadow]) instead of an
  // outlined box - a floating-card look reads as more modern than a flat
  // bordered rectangle, while staying a plain single-column field (no
  // structural change to the form itself).
  InputDecoration _decoration(BuildContext context, {String? hint}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: isDark ? const Color(0xFF1B2436) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: app_color, width: 1.6),
      ),
    );
  }

  Widget _fieldShadow(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportBugNotifierProvider);
    final notifier = ref.read(reportBugNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: app_color,
        elevation: 4,
        // A tinted shadow (vs. the default flat black) reads softer/more
        // modern under the rounded bottom edge.
        shadowColor: app_color.withOpacity(0.45),
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
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: app_color.withOpacity(0.1),
                    boxShadow: [
                      BoxShadow(
                        color: app_color.withOpacity(0.18),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.bug_report_outlined,
                    size: 32,
                    color: app_color,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Found something wrong?',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Describe the issue below and our team will look into it. '
                  'Your app version and device details are included '
                  'automatically.',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                _fieldLabel(context, Icons.short_text_rounded, 'Title'),
                _fieldShadow(
                  context,
                  child: TextFormField(
                    controller: _titleController,
                    style: GoogleFonts.poppins(),
                    decoration: _decoration(context, hint: 'Short title'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please enter a short title'
                        : null,
                  ),
                ),
                const SizedBox(height: 18),
                _fieldLabel(
                  context,
                  Icons.notes_rounded,
                  'What happened?',
                ),
                _fieldShadow(
                  context,
                  child: TextFormField(
                    controller: _descriptionController,
                    style: GoogleFonts.poppins(),
                    minLines: 3,
                    maxLines: 6,
                    decoration: _decoration(
                      context,
                      hint: 'Describe the issue',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please describe the issue'
                        : null,
                  ),
                ),
                const SizedBox(height: 18),
                _fieldLabel(
                  context,
                  Icons.format_list_numbered_rounded,
                  'How to reproduce (optional)',
                ),
                _fieldShadow(
                  context,
                  child: TextFormField(
                    controller: _stepsController,
                    style: GoogleFonts.poppins(),
                    minLines: 2,
                    maxLines: 4,
                    decoration: _decoration(
                      context,
                      hint: 'What steps show the issue?',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _fieldLabel(
                  context,
                  Icons.photo_camera_back_outlined,
                  'Screenshots (optional)',
                  trailing: '${state.images.length}/$maxBugReportImages',
                ),
                const SizedBox(height: 2),
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
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickImages,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: app_color.withOpacity(
                              Theme.of(context).brightness == Brightness.dark
                                  ? 0.14
                                  : 0.07,
                            ),
                            border: Border.all(
                              color: app_color.withOpacity(0.35),
                            ),
                          ),
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: app_color,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      foregroundColor: Colors.white,
                      elevation: 3,
                      shadowColor: app_color.withOpacity(0.5),
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
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      state.isSubmitting ? 'Sending...' : 'Send Report',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
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
          borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
