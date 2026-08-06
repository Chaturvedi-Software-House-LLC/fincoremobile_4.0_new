import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants.dart';

// ─── Receiver Signature Capture ─────────────
// Draws the receiver's on-screen signature (finger/stylus) and hands back a
// PNG image of it, embedded directly into the printed UniGas document (Bulk
// Delivery Note, Tax Invoice, Receipt) in place of a blank pen-fill line.
// Shared across DeliveryNoteRegistration, SalesRegistration, and
// ReceiptRegistration.
class _SignatureStrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignatureStrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignatureStrokePainter oldDelegate) => true;
}

class SignatureCapturePage extends StatefulWidget {
  const SignatureCapturePage({super.key});

  @override
  State<SignatureCapturePage> createState() => _SignatureCapturePageState();
}

class _SignatureCapturePageState extends State<SignatureCapturePage> {
  final List<List<Offset>> _strokes = [];
  final GlobalKey _repaintKey = GlobalKey();
  bool _isSaving = false;

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _strokes.add([details.localPosition]);
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _strokes.last.add(details.localPosition);
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
    });
  }

  Future<void> _save() async {
    if (_strokes.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      debugPrint('SIGNATURE CAPTURE ERROR: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: app_color,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          "Receiver Signature",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Please hand the device to the receiver and ask "
                      "them to sign in the box below with their finger.",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade400, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: Container(
                        color: Colors.white,
                        width: double.infinity,
                        height: double.infinity,
                        child: Stack(
                          children: [
                            if (_strokes.isEmpty)
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.draw_outlined,
                                      size: 48,
                                      color: Colors.grey.shade300,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Sign here",
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey.shade400,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            GestureDetector(
                              onPanStart: _handlePanStart,
                              onPanUpdate: _handlePanUpdate,
                              child: CustomPaint(
                                painter: _SignatureStrokePainter(_strokes),
                                size: Size.infinite,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _strokes.isEmpty ? null : _clear,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        "Clear",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_strokes.isEmpty || _isSaving) ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, color: Colors.white),
                      label: Text(
                        "Save Signature",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: app_color,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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
  }
}

// Reusable "tap to capture signature" tile - shows a call-to-action until a
// signature is captured, then a thumbnail preview + "Retake" affordance.
// Used by the Receiver Information section in DeliveryNoteRegistration,
// SalesRegistration, and ReceiptRegistration.
class ReceiverSignatureTile extends StatelessWidget {
  final Uint8List? signatureBytes;
  final ValueChanged<Uint8List> onCaptured;

  const ReceiverSignatureTile({
    super.key,
    required this.signatureBytes,
    required this.onCaptured,
  });

  Future<void> _capture(BuildContext context) async {
    final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignatureCapturePage()),
    );
    if (bytes != null) onCaptured(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: GestureDetector(
        onTap: () => _capture(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: signatureBytes == null
                ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade100)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: signatureBytes == null
                  ? Colors.grey.shade400
                  : Colors.teal,
              width: 1.4,
              style: BorderStyle.solid,
            ),
          ),
          child: signatureBytes == null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.teal, Colors.tealAccent],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.draw_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Tap to Capture Receiver Signature",
                            softWrap: true,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            "Hand the device to the receiver to sign",
                            softWrap: true,
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
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                )
              : Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.grey.shade200,
                        width: 70,
                        height: 45,
                        child: Image.memory(signatureBytes!, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.teal,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              "Signature captured",
                              softWrap: true,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Retake",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: app_color,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
