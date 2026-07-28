import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'Login.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

// What to do once real loading (prefs + the update check) is resolved -
// deciding this is separated from *acting* on it so the decision work can
// run concurrently with the loading animation instead of after it.
enum _PostLoadAction { goToLogin, showIosForceDialog, androidImmediateUpdate }

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late SharedPreferences prefs;
  String? _pendingUsername;
  String? _pendingPassword;

  // _loopController: continuous "loading" visual (orbiting particles +
  // breathing logo) that runs for exactly as long as the real async work
  // (prefs + update-check network call) takes - this replaces the old
  // fixed-length spinner so the splash is genuinely synced with loading
  // instead of a canned short animation.
  // _burstController: one-shot exit burst, plays once loading is done.
  late final AnimationController _loopController;
  late final AnimationController _burstController;
  late final List<_Particle> _particles;
  bool _isBursting = false;
  double _burstStartAngle = 0;

  static const _minimumLoadingDisplay = Duration(milliseconds: 2000);
  static const _burstDuration = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    _particles = _generateParticles(46);
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _burstController = AnimationController(
      vsync: this,
      duration: _burstDuration,
    );
    _init();
  }

  Future<void> _init() async {
    prefs = await SharedPreferences.getInstance();

    _pendingUsername = prefs.getString('username_remember');
    _pendingPassword = prefs.getString('password_remember');

    // The loading loop above keeps playing while the real update-check
    // network call runs, so the loading is genuinely synced with real
    // work - if that call is slow, the loop just keeps orbiting until
    // it resolves, instead of cutting to a canned animation length.
    final results = await Future.wait([
      Future.delayed(_minimumLoadingDisplay),
      _resolvePostLoadAction(),
    ]);
    final action = results[1] as _PostLoadAction;

    if (!mounted) return;
    setState(() {
      _burstStartAngle = _loopController.value * 2 * math.pi;
      _isBursting = true;
    });
    _loopController.stop();
    await _burstController.forward();
    if (!mounted) return;
    await _applyPostLoadAction(action);
  }

  @override
  void dispose() {
    _loopController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  // -------------------------------
  // MANDATORY UPDATE CHECK — decide only, no navigation/dialogs here so
  // this can run concurrently with the loading animation.
  // -------------------------------
  Future<_PostLoadAction> _resolvePostLoadAction() async {
    if (Platform.isAndroid) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable &&
            info.immediateUpdateAllowed) {
          return _PostLoadAction.androidImmediateUpdate;
        }
        return _PostLoadAction.goToLogin;
      } catch (e) {
        return _PostLoadAction.goToLogin;
      }
    } else if (Platform.isIOS) {
      final updateAvailable = await AppUpdateService.isIOSUpdateAvailable();
      return updateAvailable
          ? _PostLoadAction.showIosForceDialog
          : _PostLoadAction.goToLogin;
    }
    return _PostLoadAction.goToLogin;
  }

  // -------------------------------
  // ACT ON THE DECISION — runs after the exit burst finishes.
  // -------------------------------
  Future<void> _applyPostLoadAction(_PostLoadAction action) async {
    switch (action) {
      case _PostLoadAction.androidImmediateUpdate:
        try {
          final result = await InAppUpdate.performImmediateUpdate();
          if (result == AppUpdateResult.success) {
            _goToLogin(_pendingUsername, _pendingPassword);
          } else {
            SystemNavigator.pop(); // user cannot skip
          }
        } catch (e) {
          _goToLogin(_pendingUsername, _pendingPassword);
        }
        break;
      case _PostLoadAction.showIosForceDialog:
        _showForcedIOSDialog();
        break;
      case _PostLoadAction.goToLogin:
        _goToLogin(_pendingUsername, _pendingPassword);
        break;
    }
  }

  // -------------------------------
  // iOS — FORCE UPDATE POPUP
  // -------------------------------
  void _showForcedIOSDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App Icon Circle
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [app_color, app_color.withOpacity(0.6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.system_update,
                    color: Colors.white,
                    size: 40,
                  ),
                ),

                const SizedBox(height: 18),

                // Title
                Text(
                  "Update Required",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 10),

                // Message
                Text(
                  "A new version of FINCORE GO is available.\nYou must update to continue using the app.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 25),

                // Update Button (Gradient)
                GestureDetector(
                  onTap: () async {
                    final url = Uri.parse(
                      "https://apps.apple.com/app/id${AppUpdateService.iosAppId}",
                    );

                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [app_color, app_color.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        "Update Now",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------
  // NAVIGATE TO LOGIN
  // -------------------------------
  void _goToLogin(String? username, String? password) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (context, animation, secondaryAnimation) =>
            Login(username: username ?? '', password: password ?? ''),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AnimatedBuilder(
        animation: Listenable.merge([_loopController, _burstController]),
        builder: (context, _) {
          final loop = _loopController.value; // 0..1, repeats while loading
          final t = _burstController.value; // 0..1, only once loading is done

          // Logo: stays still while loading, then punches outward and
          // fades once the burst kicks off.
          final logoPhase = (t / 0.5).clamp(0.0, 1.0);
          final logoScale = _isBursting
              ? 1.0 + Curves.easeIn.transform(logoPhase) * 0.35
              : 1.0;
          final logoOpacity = 1.0 - Curves.easeIn.transform(logoPhase);

          // Shockwave ring only appears during the exit burst.
          final ringPhase = (t / 0.75).clamp(0.0, 1.0);
          final ringRadius = Curves.easeOutCubic.transform(ringPhase) * 260;
          final ringOpacity = (1.0 - ringPhase) * 0.55;

          return Stack(
            children: [
              // subtle radial glow behind everything
              Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        app_color.withOpacity(isDark ? 0.12 : 0.07),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Expanding shockwave ring (exit burst only)
              if (_isBursting && ringOpacity > 0)
                Center(
                  child: Container(
                    width: ringRadius,
                    height: ringRadius,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: app_color.withOpacity(ringOpacity),
                        width: 2,
                      ),
                    ),
                  ),
                ),

              // Orbiting bubbles - loading indicator, hugging the whole
              // logo. Fade out fast once the burst starts so the particle
              // burst below reads as a continuation.
              if (!_isBursting || t < 0.25)
                Positioned.fill(
                  child: Opacity(
                    opacity: _isBursting
                        ? 1.0 - Curves.easeIn.transform((t / 0.25).clamp(0.0, 1.0))
                        : 1.0,
                    child: CustomPaint(
                      painter: _LoadingBubblesPainter(
                        loop: loop,
                        primaryColor: app_color,
                        accentColor: const Color(0xFFF5A623),
                      ),
                    ),
                  ),
                ),

              // Particle burst - launches once loading is done.
              if (_isBursting)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ParticleBurstPainter(
                      particles: _particles,
                      startAngleOffset: _burstStartAngle,
                      burst: t,
                    ),
                  ),
                ),

              // Logo (no more spinner - the orbiting particles above are
              // the loading indicator now)
              Center(
                child: Opacity(
                  opacity: logoOpacity,
                  child: Transform.scale(
                    scale: logoScale,
                    child: Image.asset(
                      'assets/fincorego_logo_transparent.png',
                      width: 200,
                      height: 200,
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    "© 2023-2026 CSH LLC. All Rights Reserved.",
                    style: GoogleFonts.poppins(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
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
}

// -------------------------------
// PARTICLE BURST EFFECT
// -------------------------------

class _Particle {
  final double angle;
  final double distance;
  final double size;
  final double delay;
  final Color color;

  const _Particle(this.angle, this.distance, this.size, this.delay, this.color);
}

List<_Particle> _generateParticles(int count) {
  final rnd = math.Random(7); // fixed seed - same burst pattern every launch
  return List.generate(count, (i) {
    final angle = (2 * math.pi * i / count) + rnd.nextDouble() * 0.3;
    final distance = 130.0 + rnd.nextDouble() * 110.0;
    final size = 2.0 + rnd.nextDouble() * 3.0;
    final delay = rnd.nextDouble() * 0.3;
    final useAccent = i % 3 == 0;
    return _Particle(
      angle,
      distance,
      size,
      delay,
      useAccent ? const Color(0xFFF5A623) : app_color,
    );
  });
}

// A ring of small bubbles orbiting the whole logo (icon + "FINCORE GO"
// text) - each one gently pulses in size/opacity as it travels, so it
// reads as a lively loading indicator rather than a rigid spinner.
class _LoadingBubblesPainter extends CustomPainter {
  final double loop; // 0..1, repeats while the real loading is in progress
  final Color primaryColor;
  final Color accentColor;

  static const int bubbleCount = 12;
  // Sized to sit just outside the full 200x200 logo box (icon + text),
  // matching the burst's launch radius so the two effects feel continuous.
  static const double radius = 108;
  static const double baseSize = 5.0;
  static const double pulseAmplitude = 3.0;

  _LoadingBubblesPainter({
    required this.loop,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Slightly lower than dead-center so the ring sits a touch below the
    // logo's midpoint rather than exactly straddling it.
    final center = Offset(size.width / 2, size.height / 2 + 10);

    for (int i = 0; i < bubbleCount; i++) {
      final angle = (2 * math.pi * i / bubbleCount) + loop * 2 * math.pi;
      final pulse = (math.sin(loop * 2 * math.pi * 2 + i * 1.3) + 1) / 2;
      final bubbleSize = baseSize + pulseAmplitude * pulse;
      final opacity = (0.45 + 0.4 * pulse).clamp(0.0, 1.0);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final color = i.isEven ? primaryColor : accentColor;

      final paint = Paint()..color = color.withOpacity(opacity);
      canvas.drawCircle(pos, bubbleSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LoadingBubblesPainter oldDelegate) =>
      oldDelegate.loop != loop;
}

class _ParticleBurstPainter extends CustomPainter {
  final List<_Particle> particles;
  final double startAngleOffset; // ring rotation frozen at burst start
  final double burst; // 0..1

  // Launches from the same radius the loading ring sat at, so the burst
  // feels like a continuation of the ring rather than a separate effect.
  static const double _orbitRadius = 108;

  _ParticleBurstPainter({
    required this.particles,
    required this.startAngleOffset,
    required this.burst,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final p in particles) {
      final orbitAngle = p.angle + startAngleOffset;
      final local = ((burst - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final eased = Curves.easeOutCubic.transform(local);
      final dist = _orbitRadius + p.distance * eased;
      final opacity = (1 - eased).clamp(0.0, 1.0);
      final pos =
          center + Offset(math.cos(orbitAngle), math.sin(orbitAngle)) * dist;

      final paint = Paint()..color = p.color.withOpacity(opacity);
      canvas.drawCircle(pos, p.size * (1 - eased * 0.4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleBurstPainter oldDelegate) =>
      oldDelegate.startAngleOffset != startAngleOffset ||
      oldDelegate.burst != burst;
}

class AppUpdateService {
  // CHANGE THIS to your real iOS App ID
  static const String iosAppId = "6451186057";

  // Check if an update is available on the App Store
  static Future<bool> isIOSUpdateAvailable() async {
    try {
      if (!Platform.isIOS) return false;

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final url = Uri.parse("https://itunes.apple.com/lookup?id=$iosAppId");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

        if (jsonData["resultCount"] > 0) {
          final storeVersion = jsonData["results"][0]["version"];
          return _isVersionGreater(storeVersion, currentVersion);
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Compare store version with installed version
  static bool _isVersionGreater(String store, String current) {
    final s = store.split('.').map(int.parse).toList();
    final c = current.split('.').map(int.parse).toList();

    for (int i = 0; i < s.length; i++) {
      if (s[i] > c[i]) return true;
      if (s[i] < c[i]) return false;
    }
    return false;
  }
}
