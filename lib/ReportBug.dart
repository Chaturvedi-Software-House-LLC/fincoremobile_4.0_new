import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'api/api_exception.dart';
import 'api/feedback_repository.dart';
import 'constants.dart';
import 'widgets/entry_widgets.dart';

/// `POST /bug-reports` (tally-api) - a lightweight way for testers/
/// management running a distributed APK to report issues without needing
/// their own bug-tracking access. Reachable from anywhere in the app (see
/// app_bottom_nav.dart's quick-actions sheet) since it uses the `user`-
/// scope token rather than a company-scoped one - see
/// FeedbackRepository's doc comment.
class ReportBug extends StatefulWidget {
  const ReportBug({super.key});

  @override
  State<ReportBug> createState() => _ReportBugState();
}

class _ReportBugState extends State<ReportBug> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      await FeedbackRepository.instance.reportBug(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        stepsToReproduce: _stepsController.text.trim().isEmpty
            ? null
            : _stepsController.text.trim(),
      );
      if (!mounted) return;
      showAppMessage(
        context,
        'Thanks! Your bug report has been sent.',
        isError: false,
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppMessage(context, e.message);
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, 'Could not reach the server. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.poppins(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      floatingLabelStyle: GoogleFonts.poppins(
        color: app_color,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor:
          Theme.of(context).inputDecorationTheme.fillColor ?? Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: app_color, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: app_color,
        elevation: 6,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
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
                TextFormField(
                  controller: _titleController,
                  style: GoogleFonts.poppins(),
                  decoration: _decoration(
                    'Title',
                    hint: 'e.g. App crashes on Sales entry',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a short title'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  style: GoogleFonts.poppins(),
                  minLines: 3,
                  maxLines: 6,
                  decoration: _decoration(
                    'What happened?',
                    hint: 'Describe the issue in as much detail as you can',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please describe the issue'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _stepsController,
                  style: GoogleFonts.poppins(),
                  minLines: 2,
                  maxLines: 4,
                  decoration: _decoration(
                    'Steps to reproduce (optional)',
                    hint: '1. Open Sales entry\n2. Tap Save\n3. ...',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: app_color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isSubmitting ? 'Sending...' : 'Send Report',
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
