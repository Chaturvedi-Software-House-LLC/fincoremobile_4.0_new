import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/entry_widgets.dart';
import 'providers/ageing_config_notifier.dart';

class AgeingConfig extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgeingConfig> createState() => _AgeingConfigState();
}

class _AgeingConfigState extends ConsumerState<AgeingConfig> {
  late final TextEditingController heading1txtController;
  late final TextEditingController heading2txtController;
  late final TextEditingController heading3txtController;
  late final TextEditingController heading4txtController;
  late final TextEditingController heading5txtController;

  final Color _pageColor = Colors.white;
  final Color _textColor = const Color(0xFF17202A);
  final Color _mutedTextColor = const Color(0xFF6B7280);
  final Color _borderColor = const Color(0xFFE7EAF0);

  @override
  void initState() {
    super.initState();
    final initial = ref.read(ageingConfigNotifierProvider);
    heading1txtController = TextEditingController(text: initial.heading1);
    heading2txtController = TextEditingController(text: initial.heading2);
    heading3txtController = TextEditingController(text: initial.heading3);
    heading4txtController = TextEditingController(text: initial.heading4);
    heading5txtController = TextEditingController(text: initial.heading5);
  }

  @override
  void dispose() {
    heading1txtController.dispose();
    heading2txtController.dispose();
    heading3txtController.dispose();
    heading4txtController.dispose();
    heading5txtController.dispose();
    super.dispose();
  }

  void _syncControllers(AgeingConfigState state) {
    heading1txtController.text = state.heading1;
    heading2txtController.text = state.heading2;
    heading3txtController.text = state.heading3;
    heading4txtController.text = state.heading4;
    heading5txtController.text = state.heading5;
  }

  void showToast(String message) {
    final bool isSuccess = message.toLowerCase().contains('saved');
    showAppMessage(context, message, isError: !isSuccess);
  }

  Future<void> savePreferences() async {
    final message = await ref.read(ageingConfigNotifierProvider.notifier).save();
    showToast(message);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AgeingConfigState>(ageingConfigNotifierProvider, (_, next) {
      _syncControllers(next);
    });
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.more,
        activeMoreItem: AppMoreItem.settings,
      ),
      backgroundColor: _pageColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50),
        child: AppBar(
          backgroundColor: app_color,
          elevation: 6,
          automaticallyImplyLeading: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              AppNavigation.backOrDashboard(context);
            },
          ),
          title: GestureDetector(
            onTap: () {},
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    "Ageing Config",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          centerTitle: true,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 18),
              _buildSectionLabel('Ageing Brackets'),
              _buildBracketCard(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: app_color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Icon(Icons.save_alt_outlined),
                  label: Text(
                    'Save Configuration',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                  ),
                  onPressed: savePreferences,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: app_color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: app_color.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.timeline_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configure Ageing Brackets',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set ordered day ranges for ageing reports.',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          color: _mutedTextColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildBracketCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildAgeingRow(
            index: 1,
            fromValue: () => '0',
            toLabel: 'To',
            controller: heading1txtController,
            onChanged: (value) =>
                ref.read(ageingConfigNotifierProvider.notifier).setHeading1(value),
          ),
          _buildDivider(),
          _buildAgeingRow(
            index: 2,
            fromValue: () => heading1txtController.text,
            toLabel: 'To',
            controller: heading2txtController,
            onChanged: (value) =>
                ref.read(ageingConfigNotifierProvider.notifier).setHeading2(value),
          ),
          _buildDivider(),
          _buildAgeingRow(
            index: 3,
            fromValue: () => heading2txtController.text,
            toLabel: 'To',
            controller: heading3txtController,
            onChanged: (value) =>
                ref.read(ageingConfigNotifierProvider.notifier).setHeading3(value),
          ),
          _buildDivider(),
          _buildAgeingRow(
            index: 4,
            fromValue: () => heading3txtController.text,
            toLabel: 'To',
            controller: heading4txtController,
            onChanged: (value) =>
                ref.read(ageingConfigNotifierProvider.notifier).setHeading4(value),
          ),
          _buildDivider(),
          _buildAgeingRow(
            index: 5,
            fromValue: () => heading4txtController.text,
            toLabel: 'To',
            controller: heading5txtController,
            onChanged: (value) =>
                ref.read(ageingConfigNotifierProvider.notifier).setHeading5(value),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 74),
      child: Divider(height: 1, thickness: 1, color: _borderColor),
    );
  }

  Widget _buildAgeingRow({
    required int index,
    required String Function() fromValue,
    required String toLabel,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: app_color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$index',
                style: GoogleFonts.poppins(
                  color: app_color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From',
                  style: GoogleFonts.poppins(
                    color: _mutedTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    fromValue().isEmpty ? '-' : fromValue(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  toLabel,
                  style: GoogleFonts.poppins(
                    color: _mutedTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    filled: true,
                    fillColor:
                        Theme.of(context).inputDecorationTheme.fillColor ??
                        Colors.white,
                    suffixText: 'days',
                    suffixStyle: GoogleFonts.poppins(
                      color: _mutedTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: app_color,
                        width: 1.4,
                      ),
                    ),
                  ),
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
