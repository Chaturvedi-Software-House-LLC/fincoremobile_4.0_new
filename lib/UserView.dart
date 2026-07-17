import 'dart:convert';
import 'package:FincoreGo/Dashboard.dart';
import 'package:FincoreGo/ModifyUser.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'CreateUser.dart';
import 'SerialSelect.dart';
import 'constants.dart';
import 'package:http/http.dart' as http;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'package:FincoreGo/widgets/app_navigation.dart';

class UserModel {
  final String role_name;
  final String name;
  final String email;

  UserModel({required this.role_name, required this.name, required this.email});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      role_name: json['role_name'],
      name: json['customer_name'],
      email: json['user_name'],
    );
  }
}

class UserView extends StatefulWidget {
  const UserView({Key? key}) : super(key: key);
  @override
  _UserViewPageState createState() => _UserViewPageState();
}

class _UserViewPageState extends State<UserView> with TickerProviderStateMixin {
  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = false,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = false,
      isVisibleNoUserFound = false;

  final TextEditingController searchController = TextEditingController();

  List<UserModel> filteredUsers = [];

  String user_email_fetched = "";

  final List<UserModel> users = [];

  String name = "", email = "";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late SharedPreferences prefs;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  void filterUsers(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        filteredUsers = List.from(users);
      } else {
        filteredUsers = users.where((user) {
          return user.name.toLowerCase().contains(query.toLowerCase()) ||
              user.email.toLowerCase().contains(query.toLowerCase()) ||
              user.role_name.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _initSharedPreferences() async {
    prefs = await SharedPreferences.getInstance();

    setState(() {
      hostname = prefs.getString('hostname');
      company = prefs.getString('company_name');
      company_lowercase = company!.replaceAll(' ', '').toLowerCase();
      serial_no = prefs.getString('serial_no');
      username = prefs.getString('username');

      SecuritybtnAcessHolder = prefs.getString('secbtnaccess');

      String? email_nav = prefs.getString('email_nav');
      String? name_nav = prefs.getString('name_nav');

      if (email_nav != null && name_nav != null) {
        name = name_nav;
        email = email_nav;
      }
      if (SecuritybtnAcessHolder == "True") {
        isRolesVisible = true;
        isUserVisible = true;
      } else {
        isRolesVisible = false;
        isUserVisible = false;
      }
    });
    fetchUsers(serial_no!);
  }

  Future<void> _showConfirmationDialogAndNavigate(BuildContext context) async {
    final AnimationController controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Delete User Confirmation",
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: controller..forward(),
            curve: Curves.easeOutBack,
          ),
          child: Dialog(
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
                  // 🔴 Warning Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_remove_rounded,
                      size: 42,
                      color: Colors.redAccent,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 🧾 Title
                  Text(
                    'Delete User Confirmation',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 10),

                  // 💬 Description
                  Text(
                    'Are you sure you want to permanently delete this user?\n'
                    'This action cannot be undone.',
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 26),

                  // 🔘 Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Cancel
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: app_color, width: 1.5),
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

                      // Delete
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            userdelete(serial_no!, user_email_fetched);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'Delete',
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
          ),
        );
      },
    );
  }

  Future<void> userdelete(String selectedserial, String email) async {
    setState(() {
      _isLoading = true;
    });
    final url = Uri.parse('$BASE_URL_config/api/login/deleteUser');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({'serialno': selectedserial, 'username': email});

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      final responsee = response.body;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(responsee)));
      setState(() {
        _isLoading = true;
        fetchUsers(serial_no!);
      });
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = "Something went wrong!!!";
      }
      Fluttertoast.showToast(msg: error);
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> fetchUsers(String selectedserial) async {
    setState(() {
      _isLoading = true;
    });
    final url = Uri.parse('$BASE_URL_config/api/login/getRole');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({'serialno': selectedserial});

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      users.clear();
      try {
        final List<dynamic> jsonList = json.decode(response.body);

        isVisibleNoUserFound = false;

        users.addAll(jsonList.map((json) => UserModel.fromJson(json)).toList());
        filteredUsers = List.from(users);

        users.sort(compareDataObjects);
        filteredUsers.sort(compareDataObjects);

        setState(() {
          if (users.isEmpty) {
            isVisibleNoUserFound = true;
          }
          _isLoading = false;
        });
      } catch (e) {
        print(e);
      }
    }

    setState(() {
      if (users.isEmpty) {
        isVisibleNoUserFound = true;
      }
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  Future<void> _refresh() async {
    setState(() {
      fetchUsers(serial_no!);
    });
  }

  int compareDataObjects(UserModel a, UserModel b) {
    return a.name.compareTo(b.name);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => Dashboard()),
        );
        return true;
      },
      child: Scaffold(
        bottomNavigationBar: const AppBottomNav(
          activeTab: AppBottomNavTab.more,
          activeMoreItem: AppMoreItem.users,
        ),
        key: _scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => SerialSelect()),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      company ?? '',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Colors.white),
                ],
              ),
            ),
            centerTitle: true,
            actions: [],
          ),
        ),

        body: RefreshIndicator(
          onRefresh: _refresh,
          child: Stack(
            children: [
              if (isVisibleNoUserFound)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No User Found',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

              Column(
                children: [
                  // SEARCH BAR
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: searchController,
                      onChanged: filterUsers,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search users...',
                        hintStyle: GoogleFonts.poppins(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: app_color,
                          size: 24,
                        ),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  searchController.clear();
                                  filterUsers('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.18)
                                : Theme.of(context).dividerColor,
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: app_color, width: 1.5),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      itemCount: filteredUsers.length,

                      itemBuilder: (context, index) {
                        final card = filteredUsers[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).cardColor.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Theme.of(context).brightness == Brightness.dark
                                ? Border.all(
                                    color: Colors.white.withOpacity(0.10),
                                    width: 1,
                                  )
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12.withOpacity(0.08),
                                blurRadius: 20,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                /// Left Column (Avatar + Info)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      /// Name
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor: app_color
                                                .withOpacity(0.2),
                                            child: Icon(
                                              Icons.person,
                                              color: app_color,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              card.name,
                                              style: GoogleFonts.poppins(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),

                                      /// Email
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.email_outlined,
                                            size: 18,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              card.email,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 10),

                                      /// Role
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.security_outlined,
                                            size: 18,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              card.role_name,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                /// Right Column (Edit/Delete)
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ModifyUser(
                                                email_address: card.email,
                                                user_name: card.name,
                                                rolename: card.role_name,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Tooltip(
                                          message: 'Edit User',
                                          child: CircleAvatar(
                                            backgroundColor: Colors.blue
                                                .withOpacity(
                                                  Theme.of(
                                                            context,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? 0.2
                                                      : 0.1,
                                                ),
                                            radius: 16,
                                            child: Icon(
                                              Icons.edit,
                                              size: 18,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 15),
                                      GestureDetector(
                                        onTap: () {
                                          user_email_fetched = card.email;
                                          _showConfirmationDialogAndNavigate(
                                            context,
                                          );
                                        },
                                        child: Tooltip(
                                          message: 'Delete User',
                                          child: CircleAvatar(
                                            backgroundColor: Colors.red
                                                .withOpacity(
                                                  Theme.of(
                                                            context,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? 0.2
                                                      : 0.1,
                                                ),
                                            radius: 16,
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                          ),
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
                ],
              ),

              if (_isLoading) const Center(child: AppLogoLoader()),

              Positioned(
                bottom: 30,
                right: 30,
                child: FloatingActionButton(
                  backgroundColor: app_color,
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => CreateUser()),
                    );
                  },
                  child: Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 26,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
