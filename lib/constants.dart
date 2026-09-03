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
// const String BASE_URL_config = "$prodServer/main";

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
// const String authTokenBase ='KSgqL2FzZGFzZGlvQ0VEQUZfX19fIUBBUyQlYXMxOTI4MzdfX18=';

// production socket url
// const String SOCKET_URL = prodServer;
// development socket url
// const String SOCKET_URL = devServer;

const String serialNumbersConfigUrl = 'https://mobile.chaturvedigroup.com/serial_no/serial_numbers.json';

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
      final decodedData = jsonDecode(utf8.decode(response.bodyBytes));

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

// New official UAE Dirham symbol (capital "D" split by two horizontal
// lines), shipped as a single glyph in the bundled `Dirham` font by the
// uae_dirham_symbol package. It must stay in its own TextSpan/Text - mixing
// it into the same style as the amount digits would render the digits in
// the Dirham font's own (unstyled) glyphs instead of the app's normal font.
const String dirhamGlyph = 'ê';
const String _dirhamFontFamily = 'packages/uae_dirham_symbol/Dirham';

// The Dirham font's glyph occupies a visually larger box than the app's
// normal font at the same nominal fontSize (different font metrics), so an
// identical fontSize number does not produce a matching *visual* size. The
// central bank guideline that the symbol always match the amount's size
// means visually, not just the property value - this factor compensates.
const double _dirhamSizeScale = 0.89;

// The glyph's own vertical anchor sits lower within its font em-box than
// the digits' do, so even correct baseline alignment makes it visually
// "hang" below the amount text. Nudge it upward to compensate. Expressed
// as a ratio of fontSize (not a fixed pixel amount) so the correction
// scales correctly across screens that use different font sizes - a fixed
// pixel offset tuned for one size looks wrong at another.
const double _dirhamVerticalOffsetRatio = -0.10;

/// Builds the currency-symbol span for a Text.rich: the new Dirham glyph
/// for AED (theme-aware since it just inherits `style`'s color), or the
/// plain symbol text for every other currency - unchanged either way.
InlineSpan currencySymbolSpan(String currencyCode, String symbol, TextStyle style) {
  if (currencyCode.toUpperCase() == 'AED') {
    final baseFontSize = style.fontSize ?? 14;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(0, baseFontSize * _dirhamVerticalOffsetRatio),
        child: Text(
          dirhamGlyph,
          style: style.copyWith(
            fontFamily: _dirhamFontFamily,
            fontFamilyFallback: [
              if (style.fontFamily != null) style.fontFamily!,
            ],
            fontSize: baseFontSize * _dirhamSizeScale,
          ),
        ),
      ),
    );
  }
  return TextSpan(text: symbol, style: style);
}

/// Drop-in replacement for `Text(symbol, style: style)` where only the bare
/// currency symbol is shown on its own (e.g. as a TextField prefix or a
/// standalone label next to an amount rendered separately) - renders the
/// Dirham glyph for AED, plain symbol text for everything else.
Widget currencySymbolWidget(
  String currencyCode,
  String symbol,
  TextStyle style,
) {
  return Text.rich(currencySymbolSpan(currencyCode, symbol, style));
}

/// Drop-in replacement for `Text('$symbol $amountText', style: style)` that
/// renders the new Dirham glyph for AED (light/dark aware via `style`'s
/// color) while leaving every other currency exactly as plain text.
Widget currencyAmountText({
  required String currencyCode,
  required String symbol,
  required String amountText,
  required TextStyle style,
  int? maxLines,
  TextOverflow? overflow,
  TextAlign? textAlign,
  bool? softWrap,
}) {
  return Text.rich(
    TextSpan(
      children: [
        currencySymbolSpan(currencyCode, symbol, style),
        // Non-breaking space so the symbol can never wrap/truncate away
        // from the amount it belongs to (a plain space is a valid line
        // break point, which can strand the symbol on its own line).
        TextSpan(text: ' $amountText', style: style),
      ],
    ),
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
    softWrap: softWrap,
  );
}

String formatAmount(String amount) {
  String amount_string = "";
  amount = amount.replaceAll(',', '');

  if (amount.contains("-")) {
    amount = amount.replaceAll("-", "");
    double amount_double = double.tryParse(amount) ?? 0.0;
    amount_string = CurrencyFormatter.formatCurrency_double(amount_double);
    amount_string = "$amount_string DR";
  } else {
    if (amount == "null") {
      amount = "0";
    }

    double amount_double = double.tryParse(amount) ?? 0.0;
    amount_string = CurrencyFormatter.formatCurrency_double(amount_double);
    amount_string = "$amount_string CR";
  }

  return amount_string;
}

/// Widget counterpart to `formatAmount` - same DR/CR logic, but renders the
/// currency symbol in its own span so AED can show the new Dirham glyph
/// (other currencies render identically to `formatAmount`'s plain string).
/// `formatAmount` itself is left untouched for String-only contexts (CSV/PDF
/// export, etc.) where a Widget can't be used.
Widget formatAmountRich(
  String amount, {
  required TextStyle style,
  int? maxLines,
  TextOverflow? overflow,
  TextAlign? textAlign,
  bool? softWrap,
}) {
  String cleanAmount = amount.replaceAll(',', '');
  String suffix;

  if (cleanAmount.contains("-")) {
    cleanAmount = cleanAmount.replaceAll("-", "");
    suffix = "DR";
  } else {
    cleanAmount = cleanAmount == "null" ? "0" : cleanAmount;
    suffix = "CR";
  }

  final amountDouble = double.tryParse(cleanAmount) ?? 0.0;
  final parts = CurrencyFormatter.formatCurrencyParts(amountDouble);
  final currencyCode = CurrencyFormatter.getCurrencyCode();

  return currencyAmountText(
    currencyCode: currencyCode,
    symbol: parts.symbol,
    amountText: '${parts.number} $suffix',
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
    softWrap: softWrap,
  );
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

/// Gate around a subtree of [ShimmerBox] placeholders - each box animates
/// its own shimmer sweep independently, this widget just switches between
/// the skeleton and the real content based on [isLoading].
class ShimmerLoading extends StatelessWidget {
  const ShimmerLoading({super.key, required this.child, this.isLoading = true});

  final Widget child;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => child;
}

/// A single skeleton placeholder rectangle with its own independent
/// sweeping-gradient shimmer animation - a lightweight, dependency-free
/// stand-in for the `shimmer` package. Each box runs its own animation
/// (rather than one sweep shared across a whole subtree), so a screen full
/// of these shimmers as a field of independently-pulsing tiles.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white10 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.white24 : Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            // Sweep right-to-left with no dead time: the highlight's
            // midpoint moves linearly from the right edge (alignment 1) at
            // slide=0 straight to the left edge (alignment -1) at slide=1,
            // covering the whole cycle instead of pausing off-screen first.
            final slide = _controller.value;
            return LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(-slide * 2, 0),
              end: Alignment(2 - slide * 2, 0),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}
