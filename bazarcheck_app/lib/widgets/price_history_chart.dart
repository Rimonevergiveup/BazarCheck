import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../l10n/app_strings.dart';
import '../models/best_deal.dart';
import '../theme/app_theme.dart';

/// Line chart of the cheapest price over time, with a shaded min–max band.
///
/// Hand-painted rather than pulling in a charting package: this needs one line,
/// one band and two labels, and a dependency for that would be more code to
/// keep working than the 90 lines below.
class PriceHistoryChart extends StatelessWidget {
  final List<PricePoint> points;
  final bool bangla;
  final double height;

  const PriceHistoryChart({
    super.key,
    required this.points,
    required this.bangla,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppStrings.of(context);

    // Two points is the minimum that can show a direction.
    if (points.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          t.notEnoughHistory,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final lows = points.map((p) => p.minPrice).toList();
    final highs = points.map((p) => p.maxPrice).toList();
    final lowest = lows.reduce((a, b) => a < b ? a : b);
    final highest = highs.reduce((a, b) => a > b ? a : b);

    final first = points.first.minPrice;
    final last = points.last.minPrice;
    final change = first == 0 ? 0.0 : ((last - first) / first) * 100;
    final falling = change < -0.5;
    final rising = change > 0.5;

    final trendColour = falling
        ? theme.colorScheme.savingsColor
        : rising
            ? theme.colorScheme.premiumColor
            : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              falling
                  ? Icons.trending_down
                  : rising
                      ? Icons.trending_up
                      : Icons.trending_flat,
              size: 16,
              color: trendColour,
            ),
            const SizedBox(width: 6),
            Text(
              falling
                  ? t.trendFalling(Fmt.percent(change.abs(), bangla: bangla))
                  : rising
                      ? t.trendRising(Fmt.percent(change.abs(), bangla: bangla))
                      : t.trendStable,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: trendColour, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(
              points: points,
              lowest: lowest,
              highest: highest,
              lineColour: theme.colorScheme.primary,
              bandColour: theme.colorScheme.primary.withValues(alpha: 0.10),
              gridColour: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Axis(
              label: Fmt.shortDate(points.first.day, bangla: bangla),
              value: Fmt.price(lowest, bangla: bangla) ?? '',
              caption: t.lowest,
            ),
            _Axis(
              label: Fmt.shortDate(points.last.day, bangla: bangla),
              value: Fmt.price(highest, bangla: bangla) ?? '',
              caption: t.highest,
              alignEnd: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _Axis extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final bool alignEnd;

  const _Axis({
    required this.label,
    required this.value,
    required this.caption,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text('$caption $value',
            style: theme.textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<PricePoint> points;
  final double lowest;
  final double highest;
  final Color lineColour;
  final Color bandColour;
  final Color gridColour;

  _ChartPainter({
    required this.points,
    required this.lowest,
    required this.highest,
    required this.lineColour,
    required this.bandColour,
    required this.gridColour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Pad the range so a flat line doesn't sit on the very edge, and so a
    // zero-height range (all prices identical) never divides by zero.
    final range = (highest - lowest).abs() < 0.01 ? 1.0 : highest - lowest;
    final pad = range * 0.12;
    final minY = lowest - pad;
    final maxY = highest + pad;

    double dx(int i) => size.width * (i / (points.length - 1));
    double dy(double v) =>
        size.height - ((v - minY) / (maxY - minY)) * size.height;

    // Horizontal guides
    final grid = Paint()
      ..color = gridColour
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // min–max band
    final band = Path()..moveTo(dx(0), dy(points.first.maxPrice));
    for (var i = 1; i < points.length; i++) {
      band.lineTo(dx(i), dy(points[i].maxPrice));
    }
    for (var i = points.length - 1; i >= 0; i--) {
      band.lineTo(dx(i), dy(points[i].minPrice));
    }
    band.close();
    canvas.drawPath(band, Paint()..color = bandColour);

    // Cheapest-price line
    final line = Path()..moveTo(dx(0), dy(points.first.minPrice));
    for (var i = 1; i < points.length; i++) {
      line.lineTo(dx(i), dy(points[i].minPrice));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Marker on the latest value
    canvas.drawCircle(
      Offset(dx(points.length - 1), dy(points.last.minPrice)),
      4,
      Paint()..color = lineColour,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points ||
      old.lowest != lowest ||
      old.highest != highest ||
      old.lineColour != lineColour;
}
