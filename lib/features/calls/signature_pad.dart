import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Holds the strokes drawn on a [SignaturePad] and turns them into a PNG.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];
  Size _size = Size.zero;

  bool get isEmpty => strokes.every((s) => s.isEmpty);

  void _start(Offset p) {
    strokes.add([p]);
    notifyListeners();
  }

  void _extend(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.add(p);
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  /// The signature as a 'data:image/png;base64,...' URL -- what the RN signature canvas sends as
  /// customer_signature. Null when nothing was drawn.
  Future<String?> toDataUrl({double pixelRatio = 1.5}) async {
    if (isEmpty || _size.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
    _SignaturePainter.paintStrokes(canvas, strokes);
    final image = await recorder
        .endRecording()
        .toImage((_size.width * pixelRatio).round(), (_size.height * pixelRatio).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
  }
}

/// A box to sign in with a finger (no package needed).
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 220});
  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      controller._size = Size(constraints.maxWidth, height);
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => controller._start(d.localPosition),
            onPanUpdate: (d) => controller._extend(d.localPosition),
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, __) => CustomPaint(painter: _SignaturePainter(controller.strokes), size: Size.infinite),
            ),
          ),
        ),
      );
    });
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  static void paintStrokes(Canvas canvas, List<List<Offset>> strokes) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, strokes);

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
