import 'dart:convert';
import 'dart:io';
import 'package:FincoreGo/viewVanAllocations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';

class VanAllocationScreen extends StatefulWidget {
  const VanAllocationScreen({super.key});

  @override
  State<VanAllocationScreen> createState() => _VanAllocationScreenState();
}

class UserModel {
  final String role_name;
  final String name;
  final String email;
  final bool isAdmin;

  UserModel({
    required this.role_name,
    required this.name,
    required this.email,
    required this.isAdmin,
  });

  factory UserModel.fromNormalUserJson(Map<String, dynamic> json) {
    return UserModel(
      role_name:
          json['role_name']?.toString() ??
          json['worker_role']?.toString() ??
          'User',
      name: json['customer_name']?.toString() ?? '',
      email: json['user_name']?.toString() ?? '',
      isAdmin: false,
    );
  }

  factory UserModel.fromAdminJson(Map<String, dynamic> json) {
    return UserModel(
      role_name:
          json['role_name']?.toString() ??
          json['worker_role']?.toString() ??
          'Admin',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isAdmin: true,
    );
  }
}

class _VanAllocationScreenState extends State<VanAllocationScreen> {
  final Color primaryColor = app_color;
  final Color secondaryColor = const Color(0xFF14B8A6);
  final Color backgroundColor = const Color(0xFFF5F7FA);
  final Color textColor = const Color(0xFF1F2937);

  String? hostname = "",
      company = "",
      serial_no = "",
      company_lowercase = "",
      username = "",
      base_currency = "",
      token = '';

  final TextEditingController searchController = TextEditingController();
  final TextEditingController serialController = TextEditingController();

  String? selectedLocation;
  String? selectedDeliveryNoteVchType;
  String? selectedSalesLedger;
  String? selectedCashLedger;
  String? selectedSalesVchType;
  String? selectedReceiptVchType;
  UserModel? selectedUser;
  String? selectedCompany;

  List<UserModel> users = [];

  List<String> locations = [];

  List<String> deliveryNoteVchTypes = [];

  List<String> salesVchTypes = [];
  List<String> receiptVchTypes = [];

  List<String> salesLedgers = [];

  List<String> cashLedgers = [];

  List<Map<String, dynamic>> allocations = [];
  bool isSaving = false;
  bool isLoading = true;
  late SharedPreferences prefs;
  String email = "";
  int formResetKey = 0;

  Future<void> fetchUsers(String selectedserial) async {
    final usersUrl = Uri.parse('$BASE_URL_config/api/login/get');

    // Replace this with your actual get allocations API
    final allocationsUrl = Uri.parse(
      '$BASE_URL_config/api/spectra/Allocations?serial_no=$serial_no&company_name=$company',
    );

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    try {
      users.clear();

      // -----------------------------------------
      // STEP 1: Fetch existing allocations
      // -----------------------------------------
      final allocationResponse = await http.get(
        allocationsUrl,
        headers: headers,
      );

      print("Allocations Status: ${allocationResponse.statusCode}");
      print("Allocations Response: ${allocationResponse.body}");

      final Set<String> allocatedUserNames = {};

      if (allocationResponse.statusCode == 200) {
        final List<dynamic> allocationJsonList = json.decode(
          allocationResponse.body,
        );

        for (final item in allocationJsonList) {
          final map = item as Map<String, dynamic>;

          // Only check allocation for selected serial
          final serialNo = map['serial_no']?.toString().trim();
          final userName = map['user_name']?.toString().trim().toLowerCase();

          if (serialNo == selectedserial &&
              userName != null &&
              userName.isNotEmpty) {
            allocatedUserNames.add(userName);
          }
        }
      }

      print("Already Allocated User Names: $allocatedUserNames");

      // -----------------------------------------
      // STEP 2: Fetch normal users
      // -----------------------------------------
      final normalResponse = await http.post(
        usersUrl,
        body: jsonEncode({'serialno': selectedserial, 'admin': false}),
        headers: headers,
      );

      print("Normal Users Status: ${normalResponse.statusCode}");
      print("Normal Users Response: ${normalResponse.body}");

      if (normalResponse.statusCode == 200) {
        final List<dynamic> normalJsonList = json.decode(normalResponse.body);

        users.addAll(
          normalJsonList
              .where((json) {
                final map = json as Map<String, dynamic>;

                final userName = map['user_name']
                    ?.toString()
                    .trim()
                    .toLowerCase();

                // If user_name is null, keep user
                if (userName == null || userName.isEmpty) {
                  return true;
                }

                // If user already allocated, don't add user
                return !allocatedUserNames.contains(userName);
              })
              .map((json) {
                return UserModel.fromNormalUserJson(
                  json as Map<String, dynamic>,
                );
              })
              .toList(),
        );
      }
      if (users.isEmpty) {
        selectedUser = null;
      }
      setState(() {});
    } catch (e) {
      print("Fetch Users Error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  Future<void> fetchInitialData() async {
    prefs = await SharedPreferences.getInstance();

    try {
      setState(() {
        isLoading = true;
      });
      serial_no = prefs.getString('serial_no')!;
      email = prefs.getString('username')!;
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      token = prefs.getString('token')!;
      base_currency = prefs.getString('base_currency')!;
      await Future.wait([
        fetchUsers(serial_no!),

        fetchVanAllocationData(),
        /*fetchLocations(),
        fetchVchTypes(),
        fetchSalesLedgers(),
        fetchCashLedgers(),*/

        // fetchAllocations(),
      ]);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchAllocations() async {
    try {
      final response = await http.get(Uri.parse('YOUR_VIEW_ALLOCATION_API'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          allocations = List<Map<String, dynamic>>.from(data['data'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('ALLOCATION ERROR: $e');
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    serialController.dispose();
    super.dispose();
  }

  bool get isFormValid =>
      selectedUser != null &&
      selectedLocation != null &&
      selectedDeliveryNoteVchType != null &&
      selectedSalesVchType != null &&
      selectedReceiptVchType != null &&
      selectedSalesLedger != null &&
      selectedCashLedger != null;

  Future<void> fetchVanAllocationData() async {
    try {
      final url = Uri.parse(
        '$hostname/api/entry/getSpectra/$company_lowercase/$serial_no',
      );

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );

      debugPrint("VAN ALLOCATION RESPONSE: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final allocationsUrl = Uri.parse(
          '$BASE_URL_config/api/spectra/Allocations?serial_no=$serial_no&company_name=$company',
        );

        final allocationResponse = await http.get(
          allocationsUrl,
          headers: {
            'Authorization': 'Bearer $authTokenBase',
            'Content-Type': 'application/json',
          },
        );

        final Set<String> allocatedDeliveryNoteVchTypes = {};
        final Set<String> allocatedSalesVchTypes = {};
        final Set<String> allocatedReceiptVchTypes = {};
        final Set<String> allocatedLocations = {};

        if (allocationResponse.statusCode == 200) {
          final List<dynamic> allocationJsonList = jsonDecode(
            allocationResponse.body,
          );

          for (final item in allocationJsonList) {
            final map = item as Map<String, dynamic>;

            final serialNo = map['serial_no']?.toString().trim();

            if (serialNo == serial_no) {
              final deliveryNoteVchType = map['voucher_type_name']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              final salesVchType = map['sales_voucher_type']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              final receiptVchType = map['receipt_voucher_type']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              final godownName = map['godown_name']
                  ?.toString()
                  .trim()
                  .toLowerCase();

              if (godownName != null && godownName.isNotEmpty) {
                allocatedLocations.add(godownName);
              }

              if (deliveryNoteVchType != null &&
                  deliveryNoteVchType.isNotEmpty) {
                allocatedDeliveryNoteVchTypes.add(deliveryNoteVchType);
              }

              if (salesVchType != null && salesVchType.isNotEmpty) {
                allocatedSalesVchTypes.add(salesVchType);
              }

              if (receiptVchType != null && receiptVchType.isNotEmpty) {
                allocatedReceiptVchTypes.add(receiptVchType);
              }
            }
          }
        }

        debugPrint(
          "Allocated Delivery Note Vch Types: $allocatedDeliveryNoteVchTypes",
        );
        debugPrint("Allocated Sales Vch Types: $allocatedSalesVchTypes");
        debugPrint("Allocated Receipt Vch Types: $allocatedReceiptVchTypes");

        final List<dynamic> apiVchTypes = data['vchTypes'] ?? [];

        List<String> getVchTypesByParent(String parentName) {
          for (final item in apiVchTypes) {
            final map = item as Map<String, dynamic>;

            final parent = map['parent']?.toString().trim().toLowerCase() ?? '';

            if (parent == parentName.toLowerCase()) {
              return List<String>.from(map['name'] ?? [])
                  .where((vch) => vch.toString().trim().isNotEmpty)
                  .toSet()
                  .toList();
            }
          }

          return [];
        }

        setState(() {
          deliveryNoteVchTypes = getVchTypesByParent('delivery note').where((
            vch,
          ) {
            final vchName = vch.toString().trim().toLowerCase();
            return !allocatedDeliveryNoteVchTypes.contains(vchName);
          }).toList();

          salesVchTypes = getVchTypesByParent('sales').where((vch) {
            final vchName = vch.toString().trim().toLowerCase();
            return !allocatedSalesVchTypes.contains(vchName);
          }).toList();

          receiptVchTypes = getVchTypesByParent('receipt').where((vch) {
            final vchName = vch.toString().trim().toLowerCase();
            return !allocatedReceiptVchTypes.contains(vchName);
          }).toList();

          salesLedgers = List<String>.from(data['salesLedgers'] ?? []);

          cashLedgers = List<String>.from(data['cashLedgers'] ?? []);

          locations = List<String>.from(data['locations'] ?? [])
              .where((location) {
                final locationName = location.toString().trim().toLowerCase();
                return locationName.isNotEmpty &&
                    !allocatedLocations.contains(locationName);
              })
              .toSet()
              .toList();

          if (selectedLocation != null &&
              !locations.contains(selectedLocation)) {
            selectedLocation = null;
          }
          debugPrint("Allocated Locations: $allocatedLocations");

          if (selectedDeliveryNoteVchType != null &&
              !deliveryNoteVchTypes.contains(selectedDeliveryNoteVchType)) {
            selectedDeliveryNoteVchType = null;
          }

          if (selectedSalesVchType != null &&
              !salesVchTypes.contains(selectedSalesVchType)) {
            selectedSalesVchType = null;
          }

          if (selectedReceiptVchType != null &&
              !receiptVchTypes.contains(selectedReceiptVchType)) {
            selectedReceiptVchType = null;
          }
        });
      }
    } catch (e) {
      debugPrint('VAN ALLOCATION FETCH ERROR: $e');
    }
  }

  void _resetForm() {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      selectedUser = null;
      selectedLocation = null;
      selectedDeliveryNoteVchType = null;
      selectedSalesLedger = null;
      selectedCashLedger = null;
      selectedReceiptVchType = null;
      selectedSalesVchType = null;

      // This will reset Autocomplete field also
      formResetKey++;

      // If no users are available after allocation filtering,
      // selectedUser should always remain null
      if (users.isEmpty) {
        selectedUser = null;
      }
    });
  }

  Future<void> _saveAllocation() async {
    if (!isFormValid) {
      showAppMessage(context, 'Please fill all fields');
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final url = Uri.parse('$BASE_URL_config/api/spectra/Allocations');
      final body = {
        "user_name": selectedUser!.email,
        "serial_no": serial_no ?? "",
        "company_name": company ?? "",
        "godown_name": selectedLocation!,
        "voucher_type_name": selectedDeliveryNoteVchType!,
        "sales_voucher_type": selectedSalesVchType!,
        "receipt_voucher_type": selectedReceiptVchType!,
        "sales_ledger":
            (selectedSalesLedger == null || selectedSalesLedger!.isEmpty)
            ? null
            : selectedSalesLedger,

        "cash_ledger":
            (selectedCashLedger == null || selectedCashLedger!.isEmpty)
            ? null
            : selectedCashLedger,
      };

      debugPrint("SAVE ALLOCATION URL: '$url'");

      debugPrint("SAVE ALLOCATION BODY: ${jsonEncode(body)}");

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $authTokenBase',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      debugPrint("SAVE ALLOCATION RESPONSE: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        /*showAppMessage(context, 'Allocation saved successfully', isError: false);*/

        fetchUsers(serial_no!);
        fetchVanAllocationData();

        _resetForm();

        // fetchAllocations();
      } else {
        String errorMessage = 'Something went wrong';

        try {
          final responseData = jsonDecode(response.body);

          if (responseData is Map<String, dynamic>) {
            errorMessage =
                responseData['message'] ??
                responseData['error'] ??
                responseData['detail'] ??
                responseData['msg'] ??
                errorMessage;
          } else if (responseData is String) {
            errorMessage = responseData;
          }
        } catch (_) {
          errorMessage = response.body.toString();
        }

        showAppMessage(context, errorMessage);
      }
    } catch (e) {
      debugPrint("SAVE ALLOCATION ERROR: $e");

      showAppMessage(context, 'Error: $e');
    } finally {
      setState(() {
        isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    /* if (isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }*/

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(
        activeTab: AppBottomNavTab.more,
        activeMoreItem: AppMoreItem.vanAllocation,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: primaryColor,
        centerTitle: true,
        automaticallyImplyLeading: false,

        leadingWidth: 70,

        leading: Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),

            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const ViewVanAllocationScreen(),
                ),
              );
            },

            child: Container(
              decoration: BoxDecoration(),

              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),

        actions: [],

        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),

            const SizedBox(width: 12),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Van Allocation',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),

                Text(
                  'Add user allocations',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: isLoading
          ? Center(child: AppLogoLoader())
          : LayoutBuilder(
              builder: (context, constraints) {
                final bool isMobile = constraints.maxWidth < 700;

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(isMobile ? 14 : 22),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                //  _buildSearchBar(),
                                /*const SizedBox(height: 14),
                            _buildSummaryCards(isMobile),*/
                                _buildAllocationForm(isMobile),

                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: TextField(
        controller: searchController,
        onChanged: (_) => setState(() {}),
        style: GoogleFonts.poppins(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Search user, location, voucher type...',
          hintStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),

          prefixIcon: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.search_rounded, color: primaryColor, size: 22),
          ),

          suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    searchController.clear();
                    setState(() {});
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : null,

          filled: true,
          fillColor:
              Theme.of(context).inputDecorationTheme.fillColor ?? Colors.white,

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),

          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),

          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: Theme.of(context).dividerColor),
          ),

          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: primaryColor.withOpacity(0.4),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAllocationForm(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.settings_outlined, 'Allocation Configuration'),
          const SizedBox(height: 18),
          _responsiveWrap(
            isMobile: isMobile,
            children: [
              _searchableUserDropdown(),
              _searchableDropdownField(
                title: 'Location',
                value: selectedLocation,
                items: locations,
                icon: Icons.location_on_outlined,
                hint: 'Search and select location',
                onSelected: (val) {
                  closeKeyboard(context);
                  setState(() {
                    selectedLocation = val;
                  });
                },
              ),
              _searchableDropdownField(
                title: 'Delivery Note Voucher Type',
                value: selectedDeliveryNoteVchType,
                items: deliveryNoteVchTypes,
                icon: Icons.receipt_long_outlined,
                hint: 'Search and select delivery note voucher type',
                onSelected: (val) {
                  closeKeyboard(context);
                  setState(() {
                    selectedDeliveryNoteVchType = val;
                  });
                },
              ),

              _searchableDropdownField(
                title: 'Sales Voucher Type',
                value: selectedSalesVchType,
                items: salesVchTypes,
                icon: Icons.point_of_sale_outlined,
                hint: 'Search and select sales voucher type',
                onSelected: (val) {
                  closeKeyboard(context);
                  setState(() {
                    selectedSalesVchType = val;
                  });
                },
              ),

              _searchableDropdownField(
                title: 'Receipt Voucher Type',
                value: selectedReceiptVchType,
                items: receiptVchTypes,
                icon: Icons.payments_outlined,
                hint: 'Search and select receipt voucher type',
                onSelected: (val) {
                  closeKeyboard(context);
                  setState(() {
                    selectedReceiptVchType = val;
                  });
                },
              ),
              _searchableDropdownField(
                title: 'Sales Ledger',
                value: selectedSalesLedger,
                items: salesLedgers,
                icon: Icons.account_balance_wallet_outlined,
                hint: 'Search and select sales ledger',
                onSelected: (val) {
                  closeKeyboard(context);
                  setState(() {
                    selectedSalesLedger = val;
                  });
                },
              ),
              _searchableDropdownField(
                title: 'Cash Ledger',
                value: selectedCashLedger,
                items: cashLedgers,
                icon: Icons.payments_outlined,
                hint: 'Search and select cash ledger',
                onSelected: (val) {
                  closeKeyboard(context);
                  setState(() {
                    selectedCashLedger = val;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetForm,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: BorderSide(color: primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Reset',
                    style: GoogleFonts.poppins(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isSaving ? null : _saveAllocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isSaving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 18,
                              width: 18,
                              child: Platform.isIOS
                                  ? CupertinoActivityIndicator(
                                      color: Colors.white,
                                      radius: 10,
                                    )
                                  : CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Saving...',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.save_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Save Allocation',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _responsiveWrap({
    required bool isMobile,
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemWidth = isMobile
            ? constraints.maxWidth
            : (constraints.maxWidth - 18) / 2;

        return Wrap(
          spacing: 18,
          runSpacing: 16,
          children: children.map((child) {
            return SizedBox(width: itemWidth, child: child);
          }).toList(),
        );
      },
    );
  }

  Widget _searchableUserDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('User Name'),
        const SizedBox(height: 8),

        if (users.isEmpty)
          TextField(
            enabled: false,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            decoration: _inputDecoration(
              Icons.person_off_outlined,
              'No user available',
            ).copyWith(hintText: 'No user available'),
          )
        else
          Autocomplete<UserModel>(
            key: ValueKey('user_$formResetKey'),

            displayStringForOption: (UserModel option) => option.name,

            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return users;
              }

              final query = textEditingValue.text.toLowerCase();

              return users.where(
                (user) =>
                    user.name.toLowerCase().contains(query) ||
                    user.email.toLowerCase().contains(query),
              );
            },

            initialValue: TextEditingValue(text: selectedUser?.name ?? ''),

            onSelected: (value) {
              closeKeyboard(context);
              setState(() {
                selectedUser = value;
              });
            },

            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: _inputDecoration(
                      Icons.person_search_outlined,
                      'Search and select user',
                      showClear:
                          controller.text.isNotEmpty || selectedUser != null,
                      onClear: () {
                        controller.clear();

                        setState(() {
                          selectedUser = null;
                        });
                      },
                    ),
                  );
                },

            optionsViewBuilder: (context, onSelected, options) {
              final optionList = options.toList();

              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 300),
                    width: MediaQuery.of(context).size.width * 0.9,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),

                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: optionList.length,
                      itemBuilder: (context, index) {
                        final option = optionList[index];

                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onSelected(option),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withOpacity(0.5)
                                  : const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  height: 42,
                                  width: 42,
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.person_outline,
                                    color: primaryColor,
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.name,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),

                                      const SizedBox(height: 3),

                                      Text(
                                        option.email,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _searchableDropdownField({
    required String title,
    required String? value,
    required List<String> items,
    required IconData icon,
    required String hint,
    required Function(String?) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(title),
        const SizedBox(height: 8),

        if (items.isEmpty)
          TextField(
            enabled: false,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            decoration: _inputDecoration(
              icon,
              'No $title available',
            ).copyWith(hintText: 'No $title available'),
          )
        else
          Autocomplete<String>(
            key: ValueKey('${title}_$formResetKey'),
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return items;
              }

              return items.where(
                (item) => item.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                ),
              );
            },
            initialValue: TextEditingValue(text: value ?? ''),
            onSelected: onSelected,
            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
                  controller.text = value ?? controller.text;

                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: _inputDecoration(
                      icon,
                      hint,
                      showClear: controller.text.isNotEmpty || value != null,
                      onClear: () {
                        controller.clear();

                        onSelected(null);

                        setState(() {});
                      },
                    ),
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 260),
                    width: MediaQuery.of(context).size.width * 0.9,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);

                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onSelected(option),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withOpacity(0.5)
                                  : const Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  height: 40,
                                  width: 40,
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    icon,
                                    color: primaryColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    option,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _textField({
    required String title,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(title),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: _inputDecoration(icon, hint),
        ),
      ],
    );
  }

  Widget _dropdownField({
    required String title,
    required String? value,
    required List<String> items,
    required IconData icon,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(title),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
          decoration: _inputDecoration(icon, 'Select $title'),
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: items.map((e) {
            return DropdownMenuItem(
              value: e,
              child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _disabledField(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(title),
        const SizedBox(height: 8),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(0.5)
                : const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Coming Soon',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(
    IconData icon,
    String hint, {
    VoidCallback? onClear,
    bool showClear = false,
  }) {
    return InputDecoration(
      hintText: hint,

      hintStyle: GoogleFonts.poppins(
        fontSize: 12.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),

      prefixIcon: Icon(icon, color: primaryColor, size: 21),

      suffixIcon: showClear
          ? IconButton(
              onPressed: onClear,
              icon: Icon(
                Icons.close_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            )
          : null,

      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.5)
          : const Color(0xFFF5F7FA),

      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: primaryColor, width: 1.4),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: primaryColor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _statusPill(String text, bool success) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: success
            ? Colors.green.withOpacity(0.12)
            : Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: success ? Colors.green.shade700 : Colors.red.shade700,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickFilterChip(String title, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? primaryColor : primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Center(
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : primaryColor,
          ),
        ),
      ),
    );
  }

  Widget _miniActionButton(String title, IconData icon, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({double radius = 22}) {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(radius),
      border: Theme.of(context).brightness == Brightness.dark
          ? Border.all(color: Colors.white.withOpacity(0.10), width: 1)
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.045),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }
}
