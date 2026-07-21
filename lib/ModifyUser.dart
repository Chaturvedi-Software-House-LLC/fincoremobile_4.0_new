import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SerialSelect.dart';
import 'UserView.dart';
import 'constants.dart';
import 'package:http/http.dart' as http;
import 'package:FincoreGo/widgets/app_bottom_nav.dart';
import 'widgets/entry_widgets.dart';

class ModifyUser extends StatefulWidget {
  final String user_name, email_address, rolename;

  const ModifyUser({
    required this.user_name,
    required this.email_address,
    required this.rolename,
  });

  @override
  _ModifyUserPageState createState() => _ModifyUserPageState(
    user_name: user_name,
    email_address: email_address,
    rolename: rolename,
  );
}

class _ModifyUserPageState extends State<ModifyUser>
    with TickerProviderStateMixin {
  final String user_name, email_address, rolename;

  _ModifyUserPageState({
    required this.user_name,
    required this.email_address,
    required this.rolename,
  });

  String? fetched_email, fetched_password, fetched_role, fetched_name;

  bool isDashEnable = true,
      isRolesVisible = true,
      isUserEnable = true,
      isUserVisible = true,
      isRolesEnable = true,
      _isLoading = false,
      isVisibleNoUserFound = false,
      _isFocused_email = false,
      _isFocus_name = false;

  List<dynamic> myData_roles = [];

  List<DropdownMenuItem<String>> dropdownRoles = [];

  dynamic _selectedrole = "";

  String user_email_fetched = "";

  late final TextEditingController controller_email = TextEditingController();
  late final TextEditingController controller_password =
      TextEditingController();
  late final TextEditingController controller_name = TextEditingController();

  bool _isFocused_password = false;
  bool _obscureText = true;

  String name = "", email = "";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;

  late SharedPreferences prefs;

  String? hostname = "",
      company = "",
      company_lowercase = "",
      serial_no = "",
      username = "",
      HttpURL = "",
      SecuritybtnAcessHolder = "";

  List<String> _selectedCompanies = [];
  List<String> myDataCompanies = [];

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
      controller_email.text = email_address;
      controller_name.text = user_name;

      fetchUsers(serial_no!, email_address);
      fetchRoles(serial_no!);
      fetchCompany(serial_no!);
    });
  }

  void _openMultiSelectDialog() async {
    final selectedValues = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Companies'),
          content: StatefulBuilder(
            builder: (context, setState) {
              bool isAllSelected =
                  _selectedCompanies.length == myDataCompanies.length;

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Select All Checkbox
                    CheckboxListTile(
                      title: const Text('Select All'),
                      value: isAllSelected,
                      onChanged: (bool? checked) {
                        setState(() {
                          if (checked == true) {
                            // Select all companies
                            _selectedCompanies = List.from(myDataCompanies);
                          } else {
                            // Deselect all companies
                            _selectedCompanies.clear();
                          }
                        });
                      },
                      activeColor: Colors.teal, // Customize the checkbox color
                    ),
                    const Divider(), // Optional: Separate "Select All" from individual options
                    // Individual Company Checkboxes
                    ...myDataCompanies.map((company) {
                      return CheckboxListTile(
                        title: Text(company),
                        value: _selectedCompanies.contains(company),
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedCompanies.add(company);
                            } else {
                              _selectedCompanies.remove(company);
                            }
                          });
                        },
                        activeColor:
                            Colors.teal, // Customize the checkbox color
                      );
                    }).toList(),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, null); // Cancel
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, _selectedCompanies); // Confirm
              },
              child: Text(
                'OK',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        );
      },
    );

    // Update the selected companies if dialog returns valid data
    if (selectedValues != null) {
      setState(() {
        _selectedCompanies = selectedValues;
      });
    }
  }

  Future<void> modifyAllowedCompanies(
    String email,
    String serialno,
    List<String> companies_list,
  ) async {
    final url = Uri.parse('$BASE_URL_config/api/roles/allowed_companies');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    print('$serialno, $email, $companies_list');

    var body = jsonEncode({
      'serial_no': serialno,
      'user_name': email,
      'companies': companies_list,
    });

    final response = await http.put(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => UserView()),
      );
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = 'Something went wrong!!!';
      }
      showAppMessage(context, error);

      /* setState(() {
        _isLoading = false;
      });*/
    }
  }

  Future<void> fetchCompany(String selectedserial) async {
    /*setState(()
    {
      _isLoading = true;
    });*/
    myDataCompanies.clear();
    final url = Uri.parse('$BASE_URL_config/api/admin/getCompany');

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    var body = jsonEncode({'serialno': selectedserial});

    final response = await http.post(url, body: body, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> responseData = jsonDecode(response.body);
      if (responseData != null) {
        setState(() {
          myDataCompanies = responseData.map<String>((item) {
            return item['company_name'] as String;
          }).toList();

          fetchAllowedCompany(selectedserial, email_address);
        });
      } else {
        throw Exception('Failed to fetch data');
      }
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
        });
      } else {
        error = 'Something went wrong!!!';
      }
      showAppMessage(context, error);

      /*setState(() {
        _isLoading = false;
      });*/
    }
  }

  Future<void> fetchAllowedCompany(String selectedserial, String email) async {
    /*setState(()
    {
      _isLoading = true;
    });*/

    final url = Uri.parse(
      '$BASE_URL_config/api/roles/allowed_companies?user_name=$email&serial_no=$selectedserial',
    );

    Map<String, String> headers = {
      'Authorization': 'Bearer $authTokenBase',
      "Content-Type": "application/json",
    };

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      print(response.body);
      final company_data = jsonDecode(response.body);
      if (company_data != null) {
        final List<String> allowedCompanies = company_data.map<String>((item) {
          return item['company_name'] as String;
        }).toList();

        setState(() {
          final normalizedAllowedCompanies = allowedCompanies
              .map((e) => e.toString().trim().toLowerCase())
              .toList();

          _selectedCompanies = myDataCompanies.where((company) {
            return normalizedAllowedCompanies.contains(
              company.toString().trim().toLowerCase(),
            );
          }).toList();
        });

        print('Allowed Companies: $allowedCompanies');
        print('Selected Companies: $_selectedCompanies');
      } else {
        /*setState(() {
          _isLoading = false;

        });*/

        throw Exception('Failed to fetch data');
      }
      /* setState(()
      {
        _isLoading = false;
      });*/
    } else {
      Map<String, dynamic> data = json.decode(response.body);
      String error = '';

      if (data.containsKey('error')) {
        setState(() {
          error = data['error'];
          /*_isLoading = false;*/
        });
      } else {
        error = 'Something went wrong!!!';
        setState(() {
          /*_isLoading = false;*/
        });
      }
      showAppMessage(context, error);
    }
  }

  Future<void> _showConfirmationDialogAndNavigate(BuildContext context) async {
    final AnimationController controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Modify User Confirmation",
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
                  // 🧑‍💼 Icon Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: app_color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.manage_accounts_rounded,
                      size: 42,
                      color: app_color,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 🧾 Title
                  Text(
                    'Modify User Confirmation',
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
                    'Are you sure you want to modify this user\'s details?\n'
                    'The updated information will be saved permanently.',
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
                      // Cancel Button
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

                      // Confirm Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            modifyUser(
                              serial_no!,
                              fetched_email!,
                              fetched_role!,
                              fetched_name!,
                              controller_password.text.trim(),
                            );
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
                            'Modify',
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

  bool isEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim());
  }

  Future<void> modifyUser(
    String selectedserial,
    String email,
    String rolename,
    String name,
    String? password,
  ) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse('$BASE_URL_config/api/login/modifyUser');

      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      Map<String, dynamic> requestBody = {
        "username": email,
        "serialno": selectedserial,
        "rolename": rolename,
        "name": name,
      };

      if (!isEmail(email)) {
        requestBody["password"] = password;
      }

      var body = jsonEncode(requestBody);

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        String responsee = response.body;

        if (responsee ==
            "Kindly Modify Atleast 1 Detail Against Selected User") {
          showAppMessage(
            context,
            "Please modify at least one detail",
            isError: false,
          );
        } else {
          showAppMessage(context, "User updated successfully", isError: false);
          modifyAllowedCompanies(email, serial_no!, _selectedCompanies);
        }
      } else {
        Map<String, dynamic> data = json.decode(response.body);
        String error = '';

        if (data.containsKey('error')) {
          setState(() {
            error = data['error'];
          });
        } else {
          error = 'Something went wrong!!!';
        }
        showAppMessage(context, error);
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print(e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> fetchRoles(String selectedserial) async {
    /*setState(()
    {
      _isLoading = true;
    });*/

    try {
      final url = Uri.parse('$BASE_URL_config/api/roles/get');

      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'serialno': selectedserial});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        myData_roles = jsonDecode(response.body);
        if (myData_roles != null) {
          setState(() {
            dropdownRoles = myData_roles.map((role) {
              return DropdownMenuItem<String>(
                value: role['role_name'],
                child: Text(role['role_name']),
              );
            }).toList();

            _selectedrole = rolename;
          });
        } else {
          throw Exception('Failed to fetch data');
        }
      }
    } catch (e) {
      print(e);
      /* setState(() {
      _isLoading = false;
    });*/
    }
  }

  Future<void> fetchUsers(String selectedserial, String username) async {
    /*  setState(()
    {
      _isLoading = true;
    });*/

    try {
      final url = Uri.parse('$BASE_URL_config/api/login/get');

      Map<String, String> headers = {
        'Authorization': 'Bearer $authTokenBase',
        "Content-Type": "application/json",
      };

      var body = jsonEncode({'serialno': selectedserial, 'username': username});

      final response = await http.post(url, body: body, headers: headers);

      if (response.statusCode == 200) {
        List<dynamic> parsedResponse = jsonDecode(response.body);

        if (!isEmail(controller_email.text)) {
          String userPassword = parsedResponse[0]['user_password'] ?? '';

          controller_password.text = userPassword;
        }
      }
    } catch (e) {
      print(e);
      /* setState(()
    {
      _isLoading = false;
    });*/
    }
  }

  @override
  void initState() {
    super.initState();
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    _initSharedPreferences();
  }

  bool isValidEmail(String email) {
    // Simple email validation pattern
    final RegExp emailRegex = RegExp(
      r'^[\w-]+(\.[\w-]+)*@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*(\.[a-zA-Z]{2,})$',
    );
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    final bool isUsernameUser =
        controller_email.text.isNotEmpty && !isEmail(controller_email.text);
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => UserView()),
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
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => UserView()),
                );
              },
            ),
            title: Text(
              "User Modification",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            actions: [],
          ),
        ),

        body: Stack(
          children: [
            if (_isLoading) const Center(child: AppLogoLoader()),

            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 50,
                    ),
                    child: IntrinsicHeight(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
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
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header Section
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: app_color.withOpacity(0.1),
                                radius: 22,
                                child: Icon(
                                  Icons.person,
                                  size: 24,
                                  color: app_color,
                                ),
                              ),
                              title: Text(
                                'Modify User',
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Update the information of this user.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Full Name Field
                            _modernTextField(
                              label: 'Full Name',
                              enable: true,
                              controller: controller_name,
                              icon: Icons.person_outline,
                              isFocused: _isFocus_name,
                              onFocus: () => _updateFocus(name: true),
                            ),

                            const SizedBox(height: 20),

                            // Email Field (Disabled)
                            _modernTextField(
                              label: 'Username or Email',
                              enable: false,
                              controller: controller_email,
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              isFocused: _isFocused_email,
                              onFocus: () => _updateFocus(email: true),
                            ),
                            if (isUsernameUser) ...[
                              const SizedBox(height: 20),

                              _modernTextField(
                                label: 'Change Password',
                                enable: true,
                                controller: controller_password,
                                icon: Icons.lock_outline,
                                isPassword: true,
                                obscureText: _obscureText,
                                isFocused: _isFocused_password,
                                onFocus: () => _updateFocus(password: true),
                                toggleObscure: () {
                                  setState(() {
                                    _obscureText = !_obscureText;
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 10),

                            // Role Dropdown
                            Text(
                              "Select Role",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<dynamic>(
                              value: _selectedrole,
                              dropdownColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              borderRadius: _formFieldBorderRadius,

                              isExpanded: true,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),

                              decoration: _modernDropdownDecoration(),
                              items: dropdownRoles,

                              onChanged: (value) =>
                                  setState(() => _selectedrole = value),
                              onTap: () => _updateFocus(),
                              hint: Text(
                                'Choose a role',
                                style: GoogleFonts.poppins(
                                  // 👈 Apply Poppins style to menu items
                                  fontSize: 15,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Company Multi-select
                            Text(
                              "Allowed Companies",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _openMultiSelectDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                constraints: const BoxConstraints(
                                  minHeight: 56,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: _formFieldBorderRadius,
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _selectedCompanies.isNotEmpty
                                      ? _selectedCompanies.join('\n')
                                      : 'Tap to select companies',
                                  style: GoogleFonts.poppins(fontSize: 14),
                                ),
                              ),
                            ),

                            SizedBox(height: 70),

                            // Submit Button
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: app_color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                              ),

                              onPressed: _isLoading ? null : _onModifyPressed,

                              child: _isLoading
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 20,
                                          width: 20,
                                          child:
                                              Theme.of(context).platform ==
                                                  TargetPlatform.iOS
                                              ? const CupertinoActivityIndicator(
                                                  radius: 10,
                                                  color: Colors.white,
                                                )
                                              : const CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.white),
                                                  backgroundColor:
                                                      Colors.transparent,
                                                ),
                                        ),

                                        const SizedBox(width: 12),

                                        Text(
                                          'Saving...',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.save_alt),

                                        const SizedBox(width: 10),

                                        Text(
                                          'MODIFY',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
    // TODO: implement build
  }

  BorderRadius get _formFieldBorderRadius => BorderRadius.circular(22);

  OutlineInputBorder _formFieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: _formFieldBorderRadius,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  InputDecoration _modernDropdownDecoration() => InputDecoration(
    filled: true,
    fillColor: Theme.of(context).cardColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: _formFieldBorder(Theme.of(context).dividerColor),
    enabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
    disabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
    focusedBorder: _formFieldBorder(app_color, width: 1.5),
    errorBorder: _formFieldBorder(Theme.of(context).colorScheme.error),
    focusedErrorBorder: _formFieldBorder(
      Theme.of(context).colorScheme.error,
      width: 1.5,
    ),
  );

  void _onModifyPressed() {
    setState(() {
      fetched_email = controller_email.text;
      fetched_name = controller_name.text;
      fetched_role = _selectedrole;

      if (fetched_name!.isEmpty) {
        showAppMessage(context, "Enter Name");
      } else if (fetched_email!.isEmpty) {
        showAppMessage(context, "Enter Username or Email");
      } else {
        _isFocused_email = false;
        _isFocus_name = false;
        if (!isEmail(fetched_email!)) {
          if (controller_password.text.trim().isEmpty) {
            showAppMessage(context, "Enter password");
            return;
          }

          if (controller_password.text.trim().length < 4) {
            showAppMessage(context, "Password too short");
            return;
          }
        }
        _showConfirmationDialogAndNavigate(context);
      }
    });
  }

  Widget _modernTextField({
    required String label,
    required TextEditingController controller,
    required bool enable,
    required IconData icon,
    required VoidCallback onFocus,
    bool isPassword = false,
    bool obscureText = false,
    bool isFocused = false,
    VoidCallback? toggleObscure,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enable,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onTap: onFocus,
      onChanged: (_) => onFocus(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          color: isFocused
              ? app_color
              : Theme.of(context).colorScheme.onSurface,
        ),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        prefixIcon: Icon(
          icon,
          color: isFocused
              ? app_color
              : Theme.of(context).colorScheme.onSurface,
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: isFocused
                      ? app_color
                      : Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: toggleObscure,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _formFieldBorder(Theme.of(context).dividerColor),
        enabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
        disabledBorder: _formFieldBorder(Theme.of(context).dividerColor),
        focusedBorder: _formFieldBorder(app_color, width: 1.5),
        errorBorder: _formFieldBorder(Theme.of(context).colorScheme.error),
        focusedErrorBorder: _formFieldBorder(
          Theme.of(context).colorScheme.error,
          width: 1.5,
        ),
      ),
    );
  }

  void _updateFocus({
    bool name = false,
    bool email = false,
    bool password = false,
  }) {
    setState(() {
      _isFocus_name = name;
      _isFocused_email = email;
      _isFocused_password = password;
    });
  }
}
