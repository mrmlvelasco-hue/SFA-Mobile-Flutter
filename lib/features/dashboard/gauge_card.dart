import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import 'dashboard_state.dart';

/// One semicircle gauge with the percentage inside and "MTD" / "Target" figures below -- the RN
/// app's GaugeComponent.
class GaugeCard extends StatelessWidget {
  const GaugeCard({super.key, required this.gauge});
  final DashboardGauge gauge;

  @override
  Widget build(BuildContext context) {
    final fraction = ((double.tryParse(gauge.percentage) ?? 0) / 100).clamp(0.0, 1.0);
    // The RN component shows `percentage == 0.0 ? 0 : percentage` -- '0.0' displays as '0'.
    final pctText = double.tryParse(gauge.percentage) == 0 ? '0' : gauge.percentage;
    const textColor = AppColors.gray3;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(
        children: [
          SizedBox(
            width: 220,
            height: 120,
            child: CustomPaint(
              painter: _GaugePainter(fraction: fraction),
              child: Align(
                alignment: const Alignment(0, 0.75),
                child: Text('$pctText%', style: const TextStyle(fontSize: 32, color: AppColors.blue)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(gauge.label, style: const TextStyle(color: textColor)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Figure(value: gauge.actual, caption: 'MTD'),
              _Figure(value: gauge.target, caption: gauge.targetLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.caption});
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.gray3, fontWeight: FontWeight.bold);
    return Column(children: [Text(value, style: style), Text(caption, style: style)]);
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.fraction});
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final radius = math.min(size.width / 2, size.height) - stroke / 2;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height), radius: radius);
    final track = Paint()
      ..color = AppColors.gray
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = AppColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, track);
    if (fraction > 0) canvas.drawArc(rect, math.pi, math.pi * fraction, false, progress);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.fraction != fraction;
}
