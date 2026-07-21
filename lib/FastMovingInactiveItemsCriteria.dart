import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';
import 'widgets/entry_widgets.dart';

class FastMovingInactiveItemsCriteria extends StatefulWidget {
  final bool fastmoving_visible, slowmoving_visible, inactive_visible;

  const FastMovingInactiveItemsCriteria({
    required this.fastmoving_visible,
    required this.slowmoving_visible,
    required this.inactive_visible,
  });

  @override
  _FastMovingInactiveItemsState createState() => _FastMovingInactiveItemsState(
    fastmoving_visible: fastmoving_visible,
    slowmoving_visible: slowmoving_visible,
    inactive_visible: inactive_visible,
  );
}

class _FastMovingInactiveItemsState
    extends State<FastMovingInactiveItemsCriteria> {
  late TextEditingController fastmovingitemsdayscontroller;
  late TextEditingController inactiveitemsdayscontroller;
  late TextEditingController fastmovingitemsqtycontroller;
  late TextEditingController fastmovingitemsvaluecontroller;
  late TextEditingController slowmovingitemsqtycontroller;
  late TextEditingController slowmovingitemsvaluecontroller;
  late TextEditingController slowmovingitemsdayscontroller;

  bool fastmoving_visible, slowmoving_visible, inactive_visible;

  String fastmovingitems = '';
  String slowmovingitems = '';

  String inactiveitems = '';
  String fastmovingqtyitems = '';
  String fastmovingvalueitems = '';
  String slowmovingvalueitems = '';
  String slowmovingqtyitems = '';

  final Color _pageColor = Colors.white;
  final Color _textColor = const Color(0xFF17202A);
  final Color _mutedTextColor = const Color(0xFF6B7280);
  final Color _borderColor = const Color(0xFFE7EAF0);

  _FastMovingInactiveItemsState({
    required this.fastmoving_visible,
    required this.slowmoving_visible,
    required this.inactive_visible,
  });

  @override
  void initState() {
    super.initState();
    initializeControllers();
    loadPreferences();
  }

  @override
  void dispose() {
    fastmovingitemsdayscontroller.dispose();
    inactiveitemsdayscontroller.dispose();
    fastmovingitemsqtycontroller.dispose();
    fastmovingitemsvaluecontroller.dispose();
    slowmovingitemsqtycontroller.dispose();
    slowmovingitemsvaluecontroller.dispose();
    slowmovingitemsdayscontroller.dispose();
    super.dispose();
  }

  void initializeControllers() {
    fastmovingitemsdayscontroller = TextEditingController();
    fastmovingitemsqtycontroller = TextEditingController();
    inactiveitemsdayscontroller = TextEditingController();
    fastmovingitemsvaluecontroller = TextEditingController();
    slowmovingitemsqtycontroller = TextEditingController();
    slowmovingitemsvaluecontroller = TextEditingController();
    slowmovingitemsdayscontroller = TextEditingController();
  }

  void loadPreferences() async {
    SharedPreferences criteria = await SharedPreferences.getInstance();
    setState(() {
      fastmovingitems = criteria.getString('fastmovingdays') ?? '180';
      fastmovingqtyitems = criteria.getString('fastmovingqty') ?? '1000';
      fastmovingvalueitems = criteria.getString('fastmovingvalue') ?? '10000';

      slowmovingitems = criteria.getString('slowmovingdays') ?? '181';
      slowmovingqtyitems = criteria.getString('slowmovingqty') ?? '1000';
      slowmovingvalueitems = criteria.getString('slowmovingvalue') ?? '10000';

      inactiveitems = criteria.getString('inactivedays') ?? '182';
    });
    setControllerValues();
  }

  void setControllerValues() {
    fastmovingitemsdayscontroller.text = fastmovingitems;
    fastmovingitemsqtycontroller.text = fastmovingqtyitems;
    fastmovingitemsvaluecontroller.text = fastmovingvalueitems;

    slowmovingitemsvaluecontroller.text = slowmovingvalueitems;
    slowmovingitemsqtycontroller.text = slowmovingqtyitems;
    slowmovingitemsdayscontroller.text = slowmovingitems;

    inactiveitemsdayscontroller.text = inactiveitems;
  }

  void showToast(String message) {
    final bool isSuccess = message.toLowerCase().contains('saved');
    showAppMessage(context, message, isError: !isSuccess);
  }

  void savePreferences() async {
    SharedPreferences criteria = await SharedPreferences.getInstance();
    if (fastmovingitemsdayscontroller.text.isNotEmpty &&
        fastmovingitemsqtycontroller.text.isNotEmpty &&
        fastmovingitemsvaluecontroller.text.isNotEmpty &&
        slowmovingitemsdayscontroller.text.isNotEmpty &&
        slowmovingitemsqtycontroller.text.isNotEmpty &&
        slowmovingitemsvaluecontroller.text.isNotEmpty &&
        inactiveitemsdayscontroller.text.isNotEmpty) {
      int fastmovingdays = int.parse(fastmovingitemsdayscontroller.text);
      int slowmovingdays = int.parse(slowmovingitemsdayscontroller.text);
      int inactivedays = int.parse(inactiveitemsdayscontroller.text);

      if (inactivedays <= slowmovingdays || inactivedays <= fastmovingdays) {
        showToast('Inactive days must be greater than fast/slow moving days');
      } else {
        String fastmovingitemsdays = fastmovingitemsdayscontroller.text;
        String fastmovingitemsqty = fastmovingitemsqtycontroller.text;
        String fastmovingitemsvalue = fastmovingitemsvaluecontroller.text;
        String slowmovingitemsvalue = slowmovingitemsvaluecontroller.text;
        String slowmovingitemsdays = slowmovingitemsdayscontroller.text;
        String slowmovingitemsqty = slowmovingitemsqtycontroller.text;
        String inactiveitemsdays = inactiveitemsdayscontroller.text;

        criteria
          ..setString('fastmovingdays', fastmovingitemsdays)
          ..setString('fastmovingqty', fastmovingitemsqty)
          ..setString('fastmovingvalue', fastmovingitemsvalue)
          ..setString('slowmovingdays', slowmovingitemsdays)
          ..setString('slowmovingqty', slowmovingitemsqty)
          ..setString('slowmovingvalue', slowmovingitemsvalue)
          ..setString('inactivedays', inactiveitemsdays)
          ..commit();

        print(
          '$fastmovingitemsdays  $fastmovingitemsqty  $fastmovingitemsvalue  $slowmovingitemsdays  $slowmovingitemsqty  $slowmovingitemsvalue  $inactiveitemsdays',
        );

        showToast('Criteria Saved');
      }
    } else {
      showToast('Fields cannot be empty');
    }
  }

  int get _visibleSectionCount {
    return [
      fastmoving_visible,
      slowmoving_visible,
      inactive_visible,
    ].where((visible) => visible).length;
  }

  @override
  Widget build(BuildContext context) {
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
                    "Items Criteria",
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 640;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // _buildHeaderCard(),
                  //const SizedBox(height: 18),
                  const SizedBox(height: 9),
                  _buildSectionLabel('Criteria Rules'),
                  if (fastmoving_visible)
                    _buildCriteriaCard(
                      title: 'Fast Moving Criteria',
                      subtitle:
                          'Items that move quickly within the selected range.',
                      icon: Icons.flash_on_rounded,
                      color: const Color(0xFF0F766E),
                      isWide: isWide,
                      fields: [
                        _buildValidatedField(
                          label: 'No. of Days',
                          controller: fastmovingitemsdayscontroller,
                          errorText: fastmovingitemsdayscontroller.text.isEmpty
                              ? 'Required'
                              : null,
                          onChanged: (val) {
                            fastmovingitems = val;
                          },
                        ),
                        _buildValidatedField(
                          label: 'Min Qty',
                          controller: fastmovingitemsqtycontroller,
                          errorText: fastmovingitemsqtycontroller.text.isEmpty
                              ? 'Required'
                              : null,
                          onChanged: (val) {
                            fastmovingqtyitems = val;
                          },
                        ),
                        _buildValidatedField(
                          label: 'Min Value',
                          controller: fastmovingitemsvaluecontroller,
                          errorText: fastmovingitemsvaluecontroller.text.isEmpty
                              ? 'Required'
                              : null,
                          onChanged: (val) {
                            fastmovingvalueitems = val;
                          },
                        ),
                      ],
                    ),
                  if (slowmoving_visible)
                    _buildCriteriaCard(
                      title: 'Slow Moving Criteria',
                      subtitle: 'Items with lower quantity or value movement.',
                      icon: Icons.slow_motion_video_rounded,
                      color: const Color(0xFFB45309),
                      isWide: isWide,
                      fields: [
                        _buildValidatedField(
                          label: 'No. of Days',
                          controller: slowmovingitemsdayscontroller,
                          errorText: slowmovingitemsdayscontroller.text.isEmpty
                              ? 'Required'
                              : null,
                          onChanged: (val) {
                            slowmovingitems = val;
                          },
                        ),
                        _buildValidatedField(
                          label: 'Max Qty',
                          controller: slowmovingitemsqtycontroller,
                          errorText: slowmovingitemsqtycontroller.text.isEmpty
                              ? 'Required'
                              : null,
                          onChanged: (val) {
                            slowmovingqtyitems = val;
                          },
                        ),
                        _buildValidatedField(
                          label: 'Max Value',
                          controller: slowmovingitemsvaluecontroller,
                          errorText: slowmovingitemsvaluecontroller.text.isEmpty
                              ? 'Required'
                              : null,
                          onChanged: (val) {
                            slowmovingvalueitems = val;
                          },
                        ),
                      ],
                    ),
                  if (inactive_visible)
                    _buildCriteriaCard(
                      title: 'Inactive Criteria',
                      subtitle: 'Items older than active movement limits.',
                      icon: Icons.block_rounded,
                      color: const Color(0xFFB42318),
                      isWide: isWide,
                      fields: [
                        _buildValidatedField(
                          label: 'No. of Days',
                          controller: inactiveitemsdayscontroller,
                          errorText: inactiveitemsdayscontroller.text.isEmpty
                              ? 'Required'
                              : null,
                          onChanged: (val) {
                            inactiveitems = val;
                          },
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {});
                        savePreferences();
                      },
                      icon: const Icon(Icons.save_alt_rounded),
                      label: Text(
                        'Save Criteria',
                        style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: app_color,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Movement Criteria',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure $_visibleSectionCount visible item rule${_visibleSectionCount == 1 ? '' : 's'} for reports.',
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

  Widget _buildCriteriaCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Widget> fields,
    required bool isWide,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: _mutedTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: fields
                  .map(
                    (field) => SizedBox(
                      width: isWide ? 220 : double.infinity,
                      child: field,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValidatedField({
    required String label,
    required TextEditingController controller,
    required String? errorText,
    required ValueChanged<String> onChanged,
    String? tooltipText,
    int maxLength = 10,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                color: _mutedTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (tooltipText != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: tooltipText,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                textStyle: GoogleFonts.poppins(color: Colors.white),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          maxLength: maxLength,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF7F9FC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: app_color, width: 1.4),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFB42318),
                width: 1.1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFB42318),
                width: 1.4,
              ),
            ),
            errorText: errorText,
            errorStyle: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            counterText: '',
          ),
          style: GoogleFonts.poppins(
            color: _textColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
