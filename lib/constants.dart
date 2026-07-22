import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'currencyFormat.dart';

const String prodServer = "https://fincorego.duckdns.org";
const String devServer = "http://192.168.2.185";

// Production Environment
const String BASE_URL_config = "$prodServer/main";

// uni gas serial number
const String uniGasSerialNumber = '772976358';

// Backend-supplied boolean flags (e.g. an allocation's "is_bulk" tag) come
// back from the login/spectra_allocations response as 1/0 rather than
// true/false, so a plain `== true` check silently reads as always-false.
// Handles bool, num (1/0), and String ("1"/"true") shapes.
bool parseBoolFlag(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' || normalized == 'true';
  }
  return false;
}

// Dev Environment
// const String BASE_URL_config = "$devServer:5000";
const String authTokenBase =
    'KSgqL2FzZGFzZGlvQ0VEQUZfX19fIUBBUyQlYXMxOTI4MzdfX18=';

// production socket url
const String SOCKET_URL = prodServer;
// development socket url
// const String SOCKET_URL = devServer;

const String serialNumbersConfigUrl =
    'https://mobile.chaturvedigroup.com/serial_no/serial_numbers.json';

/// Default/fallback serial numbers.
/// If internet/API fails, app will still use these values.
Set<String> vanSalesSerialNo = {
  /* '725463756',
  '767060064',*/
};

Future<void> fetchvanSalesSerialNumbers() async {
  try {
    debugPrint('Fetching serial numbers from cloud...');

    final url =
        'https://raw.githubusercontent.com/saadancsh/fincore-config/main/serial_numbers.json?v=${DateTime.now().millisecondsSinceEpoch}';

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 45));

    debugPrint('Serial config status -> ${response.statusCode}');
    debugPrint('Serial config body -> ${response.body}');

    if (response.statusCode == 200) {
      final decodedData = jsonDecode(response.body);

      final dynamic rawSerialList = decodedData['serial_no_van_deliverynote'];

      if (rawSerialList is List) {
        final Set<String> fetchedSerialNos = rawSerialList
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet();

        if (fetchedSerialNos.isNotEmpty) {
          vanSalesSerialNo = fetchedSerialNos;

          debugPrint('Updated vanSalesSerialNo -> $vanSalesSerialNo');
        }
      }
    }
  } catch (e) {
    debugPrint('Error fetching serial numbers -> $e');
  }
}

bool isVanSalesAccess(String? serialNo) {
  return serialNo != null && vanSalesSerialNo.contains(serialNo.trim());
}

bool isUniGasSerial(String? serialNo) {
  final currentSerial = serialNo?.trim() ?? '';
  return currentSerial == uniGasSerialNumber;
}

void closeKeyboard(BuildContext context) {
  FocusScope.of(context).unfocus();
}

const Color app_color = Colors.teal;

String formatAmount(String amount) {
  String amount_string = "";

  if (amount.contains("-")) {
    amount = amount.replaceAll("-", "");
    double amount_double = double.parse(amount);
    amount_string = CurrencyFormatter.formatCurrency_double(amount_double);
    amount_string = "$amount_string DR";
  } else {
    if (amount == "null") {
      amount = "0";
    }

    double amount_double = double.parse(amount);
    amount_string = CurrencyFormatter.formatCurrency_double(amount_double);
    amount_string = "$amount_string CR";
  }

  return amount_string;
}

String formatNullto0(String value) {
  String value_string = '0';

  if (value != 'null') {
    value_string = value;
  } else {
    value_string = '0';
  }

  return value_string;
}

String formatdate(String saledate) {
  String formated_saledate = "";

  if (saledate == '' || saledate == 'null') {
    formated_saledate = 'N/A';
  } else {
    DateTime saledate_date = DateTime.parse(saledate);
    formated_saledate = DateFormat("dd-MMM-yyyy").format(saledate_date);
  }

  return formated_saledate;
}

class AppLogoLoader extends StatefulWidget {
  const AppLogoLoader({
    super.key,
    this.size = 92,
    this.logoAsset = 'assets/fincorelogo_appicon.png',
  });

  final double size;
  final String logoAsset;

  @override
  State<AppLogoLoader> createState() => _AppLogoLoaderState();
}

class _AppLogoLoaderState extends State<AppLogoLoader>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 1, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _opacity = Tween<double>(begin: 1, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringSize = widget.size;
    final logoSize = widget.size * 0.72;

    return SizedBox.square(
      dimension: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: CurvedAnimation(
              parent: _spinController,
              curve: Curves.linear,
            ),
            child: CustomPaint(
              size: Size.square(ringSize),
              painter: _LogoLoaderRingPainter(),
            ),
          ),
          FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              child: ClipOval(
                child: Transform.scale(
                  scale: 1.05,
                  child: Image.asset(
                    widget.logoAsset,
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoLoaderRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 8) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = const Color(0x2427B58B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF27B58B), Color(0xFFF9A21A), Color(0xFF27B58B)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 0.7, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
