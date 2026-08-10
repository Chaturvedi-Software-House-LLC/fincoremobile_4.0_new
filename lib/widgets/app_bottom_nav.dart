import 'dart:convert';
import 'dart:io';

import 'package:FincoreGo/ChangePassword.dart';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/Help.dart';
import 'package:FincoreGo/Items.dart';
import 'package:FincoreGo/Login.dart';
import 'package:FincoreGo/Party.dart';
import 'package:FincoreGo/PendingDeliveryNoteEntry.dart';
import 'package:FincoreGo/PendingReceiptEntry.dart';
import 'package:FincoreGo/PendingSalesEntry.dart';
import 'package:FincoreGo/PendingSalesOrderEntry.dart';
import 'package:FincoreGo/RolesView.dart';
import 'package:FincoreGo/SerialSelect.dart';
import 'package:FincoreGo/widgets/company_switcher.dart';
import 'package:FincoreGo/Settings.dart';
import 'package:FincoreGo/Transactions.dart';
import 'package:FincoreGo/UserView.dart';
import 'package:FincoreGo/constants.dart';
import 'package:FincoreGo/viewVanAllocations.dart';
import 'package:FincoreGo/l10n/app_localizations.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum AppBottomNavTab {
  none,
  dashboard,
  items,
  party,
  transactions,
  entries,
  more,
}

enum AppMoreItem {
  none,
  dashboard,
  roles,
  users,
  vanAllocation,
  settings,
  changePassword,
  help,
}

enum AppEntryType { none, sales, receipt, salesOrder, deliveryNote }

class AppBottomNav extends StatefulWidget {
  const AppBottomNav({
    super.key,
    this.activeTab = AppBottomNavTab.none,
    this.activeMoreItem = AppMoreItem.none,
    this.activeEntryType = AppEntryType.none,
  });

  final AppBottomNavTab activeTab;
  final AppMoreItem activeMoreItem;
  final AppEntryType activeEntryType;

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  bool showItems = false;
  bool showParty = false;
  bool showRegister = false;
  bool showEntries = false;

  bool isSalesEntryVisible = false;
  bool isReceiptEntryVisible = false;
  bool isSalesOrderEntryVisible = false;
  bool isDeliveryNoteEntryVisible = false;

  String activeMenu = '';

  bool isDashEnable = true;
  bool isRolesVisible = false;
  bool isUserVisible = false;
  bool isRolesEnable = true;
  bool isUserEnable = true;

  bool isVanAllocationVisible = false;
  bool isVanAllocationEnable = true;

  String usernamePrefs = '';
  String passwordPrefs = '';
  String serialNo = '';
  String companyName = '';
  String assignedGodown = '';
  String nameNav = '';
  String emailNav = '';

  String? socketId = '';
  String? deviceIdentifier = '';

  IO.Socket? socket;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _getDeviceIdentifier();
    _initSocket();
    _awaitPoppinsForLabelSizing();
  }

  // The per-label font-size measurement in _navLabelFontSize builds a
  // TextPainter styled with GoogleFonts.poppins() - on the very first
  // frame after a fresh install/cache clear, that font can still be
  // downloading, so the measurement (and the real Text widget alongside
  // it) briefly falls back to the platform default font. Once Poppins
  // finishes loading, the Text widget's later paint picks it up
  // automatically, but nothing re-runs the font-size calculation to
  // match - it's stuck with whatever the fallback font's (usually
  // narrower) metrics predicted, which is exactly how a label like
  // "Parties" could measure as fitting on one line yet still wrap with
  // an orphan character once real Poppins paints. Awaiting the pending
  // fonts and rebuilding once guarantees the calculation and the render
  // always use the same, final font.
  Future<void> _awaitPoppinsForLabelSizing() async {
    try {
      await GoogleFonts.pendingFonts();
    } catch (e) {
      debugPrint('Error awaiting Poppins font load for bottom nav: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadPermissions() async {
    final prefs = await SharedPreferences.getInstance();

    final allitems = prefs.getString("allitems") ?? 'False';
    final activeitems = prefs.getString("activeitems") ?? 'False';
    final inactiveitems = prefs.getString("inactiveitems") ?? 'False';

    final ledgerentries = prefs.getString("ledgerentries") ?? 'False';
    final inventoryentries = prefs.getString("inventoryentries") ?? 'False';
    final billsentries = prefs.getString("billsentries") ?? 'False';
    final costcentreentries = prefs.getString("costcentreentries") ?? 'False';

    final partySuppliers = prefs.getString("party_suppliers") ?? 'False';
    final partyCustomers = prefs.getString("party_customers") ?? 'False';

    final salesentry = prefs.getString('salesentry') ?? "False";
    final receiptentry = prefs.getString('receiptentry') ?? "False";
    final salesorderentry = prefs.getString('salesorderentry') ?? "False";
    final deliverynoteentry = prefs.getString('deliverynoteentry') ?? "False";

    final vanAllocation = prefs.getString("vanallocation") ?? "False";
    final secBtnAccess = prefs.getString('secbtnaccess') ?? 'False';

    String godown = '';
    final allocationString = prefs.getString('spectra_allocations');

    if (allocationString != null && allocationString.isNotEmpty) {
      try {
        final List<dynamic> allocations = jsonDecode(allocationString);

        if (allocations.isNotEmpty) {
          final Map<String, dynamic> allocation = Map<String, dynamic>.from(
            allocations.first,
          );

          godown = allocation['godown']?.toString().trim() ?? '';
        }
      } catch (e) {
        debugPrint('Error reading assigned godown in bottom nav -> $e');
      }
    }

    if (!mounted) return;

    setState(() {
      usernamePrefs = prefs.getString('username') ?? '';
      passwordPrefs = prefs.getString('password') ?? '';
      serialNo = prefs.getString('serial_no') ?? '';
      companyName = prefs.getString('company_name') ?? '';

      nameNav = prefs.getString('name') ?? usernamePrefs;
      emailNav = usernamePrefs;

      assignedGodown = godown;

      isSalesEntryVisible = salesentry == 'True';
      isReceiptEntryVisible = receiptentry == 'True';
      isSalesOrderEntryVisible = salesorderentry == 'True';
      isDeliveryNoteEntryVisible = deliverynoteentry == 'True';

      isVanAllocationVisible = vanAllocation == 'True';

      showItems =
          allitems == 'True' ||
          activeitems == 'True' ||
          inactiveitems == 'True';

      showParty = partySuppliers == 'True' || partyCustomers == 'True';

      showRegister =
          ledgerentries == 'True' ||
          inventoryentries == 'True' ||
          billsentries == 'True' ||
          costcentreentries == 'True';

      showEntries =
          isSalesEntryVisible ||
          isReceiptEntryVisible ||
          isSalesOrderEntryVisible ||
          isDeliveryNoteEntryVisible;

      if (secBtnAccess == 'True') {
        isRolesVisible = true;
        isUserVisible = true;
      } else {
        isRolesVisible = false;
        isUserVisible = false;
      }

      isDashEnable = true;
      isRolesEnable = true;
      isUserEnable = true;
      isVanAllocationEnable = true;
    });
  }

  Future<void> _getDeviceIdentifier() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceIdentifier = androidInfo.id;
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceIdentifier = iosInfo.identifierForVendor;
      }
    } catch (e) {
      debugPrint('Error getting device identifier: $e');
    }
  }

  void _initSocket() {
    socket = IO.io(SOCKET_URL, <String, dynamic>{
      'transports': ['websocket'],
      'path': '/main/socket.io',
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 1500,
      'timeout': 20000,
      'forceNew': true,
      'auth': {'token': authTokenBase},
    });

    socket?.on('connect', (_) {
      socketId = socket?.id;
    });

    socket?.connect();
  }

  void emitDeleteMyId(Map<String, dynamic> jsonPayload, Function() onComplete) {
    socket?.emit('deleteMyId', jsonPayload);
    onComplete();
  }

  @override
  void dispose() {
    socket?.dispose();
    super.dispose();
  }

  void _replaceWith(Widget page) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            _navTile(
              AppLocalizations.of(context).navDashboard,
              Icons.dashboard_rounded,
              true,
              AppBottomNavTab.dashboard,
              () {
                _replaceWith(const Dashboard());
              },
            ),
            _navTile(
              AppLocalizations.of(context).navItems,
              Icons.inventory_outlined,
              showItems,
              AppBottomNavTab.items,
              () {
                _replaceWith(Items());
              },
            ),
            _navTile(
              AppLocalizations.of(context).navParties,
              Icons.groups_outlined,
              showParty,
              AppBottomNavTab.party,
              () {
                _replaceWith(Party());
              },
            ),
            _navTile(
              AppLocalizations.of(context).navTransactions,
              Icons.payment_outlined,
              showRegister,
              AppBottomNavTab.transactions,
              () {
                _replaceWith(Transactions());
              },
            ),
            _navTile(
              AppLocalizations.of(context).navEntries,
              Icons.receipt_long,
              showEntries,
              AppBottomNavTab.entries,
              () {
                _showEntriesBottomSheet(context);
              },
            ),
            _navTile(
              AppLocalizations.of(context).navMore,
              Icons.grid_view_rounded,
              true,
              AppBottomNavTab.more,
              () {
                _showQuickActionsSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile(
    String label,
    IconData icon,
    bool visible,
    AppBottomNavTab tab,
    VoidCallback onTap,
  ) {
    if (!visible) return const SizedBox.shrink();

    final isCurrentRouteTab = widget.activeTab == tab;
    final isActive = isCurrentRouteTab;
    final shouldIgnoreTap =
        isCurrentRouteTab &&
        tab != AppBottomNavTab.more &&
        tab != AppBottomNavTab.entries;
    final textColor = isActive
        ? app_color
        : Theme.of(context).colorScheme.onSurface;

    return Expanded(
      child: InkWell(
        onTap: shouldIgnoreTap ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? app_color.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive
                  ? app_color.withOpacity(0.36)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: textColor),
              const SizedBox(height: 4),
              AdaptiveNavLabel(
                label: label,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: textColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickActionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,

      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            // margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),

            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _quickProfileCard(context),

                  const SizedBox(height: 18),

                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.05,
                    children: [
                      _quickActionTile(
                        icon: Icons.business_rounded,
                        title: "Companies",
                        onTap: () {
                          Navigator.pop(context);
                          _replaceWith(SerialSelect());
                        },
                      ),

                      if (isRolesVisible)
                        _quickActionTile(
                          icon: Icons.group_rounded,
                          title: "Roles",
                          moreItem: AppMoreItem.roles,
                          enabled: isRolesEnable,
                          onTap: () {
                            Navigator.pop(context);
                            _replaceWith(RolesView());
                          },
                        ),

                      if (isUserVisible)
                        _quickActionTile(
                          icon: Icons.person_rounded,
                          title: "Users",
                          moreItem: AppMoreItem.users,
                          enabled: isUserEnable,
                          onTap: () {
                            Navigator.pop(context);
                            _replaceWith(UserView());
                          },
                        ),

                      if (vanSalesSerialNo.contains(serialNo.trim()) &&
                          isVanAllocationVisible)
                        _quickActionTile(
                          icon: Icons.local_shipping_outlined,
                          title: "Van Allocation",
                          moreItem: AppMoreItem.vanAllocation,
                          enabled: isVanAllocationEnable,
                          onTap: () {
                            Navigator.pop(context);
                            _replaceWith(const ViewVanAllocationScreen());
                          },
                        ),

                      _quickActionTile(
                        icon: Icons.settings_rounded,
                        title: "Settings",
                        moreItem: AppMoreItem.settings,
                        onTap: () {
                          Navigator.pop(context);
                          _replaceWith(Settings());
                        },
                      ),

                      _quickActionTile(
                        icon: Icons.lock_outline_rounded,
                        title: "Change Password",
                        moreItem: AppMoreItem.changePassword,
                        onTap: () {
                          Navigator.pop(context);
                          _replaceWith(ChangePassword());
                        },
                      ),

                      _quickActionTile(
                        icon: Icons.help_outline_rounded,
                        title: "Help",
                        moreItem: AppMoreItem.help,
                        onTap: () {
                          Navigator.pop(context);
                          _replaceWith(Help());
                        },
                      ),

                      _quickActionTile(
                        icon: Icons.logout_rounded,
                        title: "Logout",
                        isDanger: true,
                        onTap: () {
                          // Navigator.pop(context);
                          _showConfirmationDialogAndNavigate(context);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Text(
                    '© CSH LLC 2023-2026 • Version 5.0.1',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _quickProfileCard(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          backgroundColor: app_color.withOpacity(0.10),
          radius: 32,
          child: Icon(Icons.person_rounded, color: app_color, size: 34),
        ),

        const SizedBox(height: 10),

        Text(
          nameNav,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          emailNav,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 10),

        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _profileChip(Icons.confirmation_number_outlined, serialNo),
            _profileChip(
              Icons.business_outlined,
              companyName,
              onTap: () => showQuickCompanySwitcher(context),
              trailingIcon: Icons.swap_horiz_rounded,
            ),
            if (vanSalesSerialNo.contains(serialNo.trim()) &&
                assignedGodown.isNotEmpty)
              _profileChip(Icons.local_shipping_outlined, assignedGodown),
          ],
        ),

        const SizedBox(height: 14),

        Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
      ],
    );
  }

  Widget _profileChip(
    IconData icon,
    String text, {
    VoidCallback? onTap,
    IconData? trailingIcon,
  }) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: app_color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: app_color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: app_color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 5),
            Icon(trailingIcon, size: 14, color: app_color),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: chip,
    );
  }

  Widget _profileInfoRow(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 6),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            text,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
            softWrap: true,
          ),
        ),
      ],
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    AppMoreItem moreItem = AppMoreItem.none,
    bool enabled = true,
    bool isDanger = false,
  }) {
    final isActive =
        moreItem != AppMoreItem.none && widget.activeMoreItem == moreItem;
    final canTap = enabled && !isActive;
    final tileColor = isDanger
        ? Colors.redAccent
        : isActive
        ? app_color
        : app_color;

    return InkWell(
      onTap: canTap ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isDanger
                ? Colors.redAccent.withOpacity(0.06)
                : isActive
                ? app_color.withOpacity(0.14)
                : app_color.withOpacity(0.055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDanger
                  ? Colors.redAccent.withOpacity(0.18)
                  : isActive
                  ? app_color.withOpacity(0.38)
                  : app_color.withOpacity(0.16),
              width: isActive ? 1.2 : 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: tileColor),
              const SizedBox(height: 5),
              Text(
                title,
                textAlign: TextAlign.center,
                // 1 line, not 2 - wrapping to a 2nd line was what
                // overflowed the tile's fixed height for longer titles
                // ("Companies", "Change Password"). Ellipsis instead.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isDanger
                      ? Colors.redAccent
                      : isActive
                      ? app_color
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEntriesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [app_color.withOpacity(0.9), app_color],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: app_color.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Entry Type",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(thickness: 1, color: Colors.grey.shade300),
                ],
              ),

              const SizedBox(height: 20),

              if (isSalesEntryVisible)
                _buildEntryOption(
                  icon: Icons.point_of_sale,
                  label: "Sales",
                  gradient: [Colors.blue.shade400, Colors.blue.shade700],
                  isActive: widget.activeEntryType == AppEntryType.sales,
                  onTap: () {
                    Navigator.pop(context);
                    if (widget.activeEntryType != AppEntryType.sales) {
                      _replaceWith(PendingSalesEntry());
                    }
                  },
                ),

              if (isReceiptEntryVisible)
                _buildEntryOption(
                  icon: Icons.receipt_long,
                  label: "Receipts",
                  gradient: [Colors.green.shade400, Colors.green.shade700],
                  isActive: widget.activeEntryType == AppEntryType.receipt,
                  onTap: () {
                    Navigator.pop(context);
                    if (widget.activeEntryType != AppEntryType.receipt) {
                      _replaceWith(PendingReceiptEntry());
                    }
                  },
                ),

              if (isSalesOrderEntryVisible)
                _buildEntryOption(
                  icon: Icons.assignment,
                  label: "Sales Order",
                  gradient: [
                    Colors.orange.shade400,
                    Colors.deepOrange.shade600,
                  ],
                  isActive: widget.activeEntryType == AppEntryType.salesOrder,
                  onTap: () {
                    Navigator.pop(context);
                    if (widget.activeEntryType != AppEntryType.salesOrder) {
                      _replaceWith(PendingSalesOrderEntry());
                    }
                  },
                ),

              if (vanSalesSerialNo.contains(serialNo.trim()) &&
                  isDeliveryNoteEntryVisible)
                _buildEntryOption(
                  icon: Icons.local_shipping,
                  label: "Delivery Note",
                  gradient: [Colors.blue.shade400, Colors.indigo.shade600],
                  isActive: widget.activeEntryType == AppEntryType.deliveryNote,
                  onTap: () {
                    Navigator.pop(context);
                    if (widget.activeEntryType != AppEntryType.deliveryNote) {
                      _replaceWith(PendingDeliveryNoteEntry());
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntryOption({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isActive
              ? gradient.first.withOpacity(0.10)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? gradient.last.withOpacity(0.8)
                : gradient.last.withOpacity(0.5),
            width: isActive ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: gradient.last.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive
                    ? gradient.last
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (isActive)
              Icon(Icons.check_circle_rounded, size: 20, color: gradient.last)
            else
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConfirmationDialogAndNavigate(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: app_color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    size: 40,
                    color: app_color,
                  ),
                ),
                const SizedBox(height: 18),

                Text(
                  'Logout Confirmation',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                Text(
                  'Are you sure you want to log out of your account?',
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: app_color),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: app_color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();

                          final jsonPayload = {
                            'username': usernamePrefs,
                            'password': passwordPrefs,
                            'macId': deviceIdentifier,
                          };

                          Navigator.of(context).pop();

                          emitDeleteMyId(jsonPayload, () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    Login(username: '', password: ''),
                              ),
                            );
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: app_color,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Logout',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Wrapping to a 2nd line is fine when more than one character spills over
// (e.g. "Sales Order" breaking after a word) - but for a single long word
// wrapping onto 2 lines can leave just one orphan character alone on line
// 2 ("Parties" -> "Partie" / "s"), which reads as a layout glitch rather
// than a real wrap.
//
// A prior version tried to predict this ahead of time with a parallel
// TextPainter measurement, but that measurement can disagree with the
// real render for reasons outside this widget's control (font-loading
// timing, text-scale settings, subpixel rounding) - it kept mispredicting
// "fits" for labels that still wrapped with an orphan character. This
// version instead inspects the ACTUAL rendered paragraph after each frame
// (via the same RenderParagraph Flutter itself just laid out - not a
// separate guess) and only shrinks, one small step at a time, for as long
// as the real render still shows exactly one trailing character alone on
// its own line.
class AdaptiveNavLabel extends StatefulWidget {
  final String label;
  final FontWeight fontWeight;
  final Color color;

  const AdaptiveNavLabel({
    required this.label,
    required this.fontWeight,
    required this.color,
  });

  @override
  State<AdaptiveNavLabel> createState() => AdaptiveNavLabelState();
}

class AdaptiveNavLabelState extends State<AdaptiveNavLabel> {
  static const double _baseFontSize = 11;
  static const double _minFontSize = 8.5;

  final GlobalKey _key = GlobalKey();
  double _fontSize = _baseFontSize;
  String? _resolvedFor;

  @override
  void didUpdateWidget(covariant AdaptiveNavLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label ||
        oldWidget.fontWeight != widget.fontWeight) {
      // A different label (or weight, e.g. active-tab change) needs its
      // own fresh check - the previous label's resolved size doesn't
      // necessarily apply.
      _fontSize = _baseFontSize;
      _resolvedFor = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedFor != '${widget.label}_${_fontSize}_${widget.fontWeight}') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkWrap());
    }
    return Text(
      widget.label,
      key: _key,
      maxLines: 2,
      softWrap: true,
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(
        fontSize: _fontSize,
        fontWeight: widget.fontWeight,
        color: widget.color,
        height: 1.2,
      ),
    );
  }

  void _checkWrap() {
    if (!mounted) return;
    final markResolved = '${widget.label}_${_fontSize}_${widget.fontWeight}';
    final renderObject = _key.currentContext?.findRenderObject();
    if (renderObject is! RenderParagraph || widget.label.length < 2) {
      _resolvedFor = markResolved;
      return;
    }

    // Compare which line the last two characters actually landed on, in
    // the real, already-painted paragraph. Same line (whether that's line
    // 1 - no wrap at all - or line 2 with 2+ characters together) is
    // fine, either way. Different lines means the very last character is
    // stranded alone - shrink one step and let the next frame re-check.
    final lastCharBoxes = renderObject.getBoxesForSelection(
      TextSelection(
        baseOffset: widget.label.length - 1,
        extentOffset: widget.label.length,
      ),
    );
    final secondLastCharBoxes = renderObject.getBoxesForSelection(
      TextSelection(
        baseOffset: widget.label.length - 2,
        extentOffset: widget.label.length - 1,
      ),
    );
    if (lastCharBoxes.isEmpty || secondLastCharBoxes.isEmpty) {
      _resolvedFor = markResolved;
      return;
    }

    final bool orphaned =
        lastCharBoxes.first.top > secondLastCharBoxes.first.top;

    if (!orphaned || _fontSize <= _minFontSize) {
      _resolvedFor = markResolved;
      return;
    }

    setState(() {
      _fontSize = (_fontSize - 0.5).clamp(_minFontSize, _baseFontSize);
    });
  }
}
