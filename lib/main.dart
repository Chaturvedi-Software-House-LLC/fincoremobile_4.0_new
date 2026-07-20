import 'dart:io';

import 'package:FincoreGo/Constants.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SharedPreferencesService.dart';
import 'SplashScreen.dart';
import 'theme_controller.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferencesService.init();
  await themeController.loadThemeMode();

  runApp(const MyApp());
}

// ✅ Local notifications setup (for Android & iOS)
/*
Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsDarwin =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('🔔 Notification tapped → ${response.payload}');
    },
  );
}
*/

// ✅ Firebase Messaging setup
/*
Future<void> _setupFirebaseMessaging() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permission (iOS only)
  await requestPermission();

  // Handle background messages
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // When app is opened from a terminated state by tapping a notification
  FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
    if (message != null) {
      showNotification(message);
    }
  });

  // Foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    showNotification(message);
  });
}

// ✅ Display a local notification
Future<void> showNotification(RemoteMessage message) async {
  RemoteNotification? notification = message.notification;
  if (notification != null) {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      '1',
      'fincore',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      notification.title,
      notification.body,
      platformDetails,
      payload: 'item x',
    );
  }
}

// ✅ Background notification handler
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  showNotification(message);
}

// ✅ iOS permission request
Future<void> requestPermission() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    announcement: false,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    debugPrint('✅ User granted permission');
  } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
    debugPrint('⚠️ User granted provisional permission');
  } else {
    debugPrint('❌ User declined or has not accepted permission');
  }
}
*/

// ✅ App lifecycle tracking

@override
void didChangeAppLifecycleState(AppLifecycleState state) async {
  if (state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached ||
      state == AppLifecycleState.inactive) {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt('lastActive', DateTime.now().millisecondsSinceEpoch);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
              child: child!,
            );
          },
          title: 'Fincore Go',
          themeMode: themeController.themeMode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          home: SplashScreen(),
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    const Color lightSurface = Colors.white;
    const Color lightBackground = Colors.white;
    const Color lightField = Color(0xFFF7F9FC);
    const Color lightOutline = Color(0xFFE7EAF0);

    return ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.blue,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: lightBackground,
      cardColor: lightSurface,
      canvasColor: lightSurface,
      dividerColor: lightOutline,
      iconTheme: const IconThemeData(color: Color(0xFF17202A)),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: const Color(0xFF17202A),
        displayColor: const Color(0xFF17202A),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: app_color,
        circularTrackColor: Colors.white,
      ),
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ).copyWith(secondary: app_color, primary: app_color),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightField,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: app_color, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: lightOutline),
        ),
        labelStyle: TextStyle(color: Colors.black54),
        hintStyle: TextStyle(color: Colors.black54),
        prefixIconColor: Colors.black54,
        suffixIconColor: Colors.black54,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(fillColor: lightField),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: lightSurface,
        textStyle: TextStyle(color: Color(0xFF17202A)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        modalBackgroundColor: lightSurface,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFF17202A),
        iconColor: Color(0xFF6B7280),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: app_color,
        selectionColor: Color(0x332196F3),
        selectionHandleColor: app_color,
      ),
      splashColor: app_color.withOpacity(0.2),
      highlightColor: Colors.transparent,
    );
  }

  ThemeData _buildDarkTheme() {
    const Color darkSurface = Color(0xFF111827);
    const Color darkBackground = Color(0xFF0F172A);
    const Color darkField = Color(0xFF1F2937);
    const Color darkOutline = Color(0xFF374151);
    const Color darkText = Color(0xFFF9FAFB);
    const Color darkMutedText = Color(0xFFD1D5DB);

    return ThemeData(
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: darkBackground,
      cardColor: darkSurface,
      canvasColor: darkSurface,
      dividerColor: darkOutline,
      iconTheme: const IconThemeData(color: darkText),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: darkText,
        displayColor: darkText,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: app_color,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: app_color,
        circularTrackColor: darkSurface,
      ),
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: app_color,
            brightness: Brightness.dark,
          ).copyWith(
            primary: app_color,
            secondary: app_color,
            surface: darkSurface,
          ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: darkField,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: app_color, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: darkOutline),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: darkOutline),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.redAccent, width: 2),
        ),
        labelStyle: TextStyle(color: darkMutedText),
        hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
        prefixIconColor: darkMutedText,
        suffixIconColor: darkMutedText,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(fillColor: darkField),
        textStyle: TextStyle(color: darkText),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: darkSurface,
        textStyle: TextStyle(color: darkText),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        modalBackgroundColor: darkSurface,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: darkText,
        iconColor: darkMutedText,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: app_color,
        selectionColor: Color(0x552196F3),
        selectionHandleColor: app_color,
      ),
      splashColor: app_color.withOpacity(0.22),
      highlightColor: Colors.transparent,
      dialogTheme: const DialogThemeData(backgroundColor: darkSurface),
    );
  }
}
