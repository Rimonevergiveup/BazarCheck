import 'package:flutter/material.dart';

/// How stale a price is. Drives the colour and wording users see, so a price
/// is never presented as "current" when it is months old.
enum Freshness {
  /// Updated within the last 24 hours.
  fresh,

  /// Updated within the last 7 days.
  recent,

  /// 7-30 days old. Shown with a warning tint.
  stale,

  /// Over 30 days old, or unknown. Shown as not trustworthy.
  outdated;

  static Freshness of(DateTime? collectedAt, {DateTime? now}) {
    if (collectedAt == null) return Freshness.outdated;
    final elapsed = (now ?? DateTime.now()).difference(collectedAt);
    if (elapsed.isNegative) return Freshness.fresh; // clock skew
    if (elapsed.inHours < 24) return Freshness.fresh;
    if (elapsed.inDays < 7) return Freshness.recent;
    if (elapsed.inDays < 30) return Freshness.stale;
    return Freshness.outdated;
  }

  bool get isTrustworthy => this == Freshness.fresh || this == Freshness.recent;
}

/// Currency, number and date formatting for Bangladesh.
///
/// Deliberately dependency-free (no `intl`) so there is no version conflict
/// with `flutter_localizations`, and so Bangla digit rendering is explicit.
class Fmt {
  Fmt._();

  static const String taka = '৳'; // ৳

  static const List<String> _bnDigits = [
    '০', '১', '২', '৩', '৪',
    '৫', '৬', '৭', '৮', '৯',
  ];

  /// Converts ASCII digits to Bangla digits. Leaves everything else alone.
  static String toBanglaDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        buffer.write(_bnDigits[rune - 0x30]);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Groups digits the South Asian way: 1,23,45,678 (lakh / crore), which is
  /// what Bangladeshi users expect — not the Western 12,345,678.
  static String groupSouthAsian(String digits) {
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  /// Formats a price as `৳1,234` or `৳১,২৩৪`.
  ///
  /// Returns null when [amount] is null so callers are forced to decide what
  /// "no price" looks like, instead of silently rendering ৳0 — which was the
  /// original bug where a missing price displayed as a confident `$0.00`.
  static String? price(
    num? amount, {
    bool bangla = false,
    String symbol = taka,
    bool showDecimals = false,
  }) {
    if (amount == null) return null;
    final abs = amount.abs();
    final String body;
    if (showDecimals || (abs % 1 != 0 && abs < 1000)) {
      final fixed = abs.toStringAsFixed(2);
      final dot = fixed.indexOf('.');
      body = '${groupSouthAsian(fixed.substring(0, dot))}${fixed.substring(dot)}';
    } else {
      body = groupSouthAsian(abs.round().toString());
    }
    final sign = amount < 0 ? '-' : '';
    final out = '$sign$symbol$body';
    return bangla ? toBanglaDigits(out) : out;
  }

  /// A price range: `৳72` when both ends match, `৳72 – ৳85` otherwise.
  static String? priceRange(num? min, num? max, {bool bangla = false}) {
    final lo = price(min, bangla: bangla);
    if (lo == null) return null;
    if (max == null || min == max) return lo;
    return '$lo – ${price(max, bangla: bangla)}';
  }

  /// Whole-number percent, e.g. `18%`.
  static String percent(num value, {bool bangla = false}) {
    final out = '${value.round()}%';
    return bangla ? toBanglaDigits(out) : out;
  }

  /// Compact relative time: "just now", "3h ago", "5d ago", "2mo ago".
  /// [bangla] switches to Bangla wording and digits.
  static String relativeTime(
    DateTime? then, {
    bool bangla = false,
    DateTime? now,
  }) {
    if (then == null) return bangla ? 'অজানা' : 'unknown';
    final elapsed = (now ?? DateTime.now()).difference(then);
    final mins = elapsed.inMinutes;
    if (mins < 1) return bangla ? 'এইমাত্র' : 'just now';
    if (mins < 60) {
      return bangla ? '${toBanglaDigits('$mins')} মিনিট আগে' : '${mins}m ago';
    }
    final hours = elapsed.inHours;
    if (hours < 24) {
      return bangla ? '${toBanglaDigits('$hours')} ঘণ্টা আগে' : '${hours}h ago';
    }
    final days = elapsed.inDays;
    if (days < 30) {
      return bangla ? '${toBanglaDigits('$days')} দিন আগে' : '${days}d ago';
    }
    final months = (days / 30).floor();
    if (months < 12) {
      return bangla ? '${toBanglaDigits('$months')} মাস আগে' : '${months}mo ago';
    }
    final years = (days / 365).floor();
    return bangla ? '${toBanglaDigits('$years')} বছর আগে' : '${years}y ago';
  }

  /// `11 Aug 2026`
  static String shortDate(DateTime? d, {bool bangla = false}) {
    if (d == null) return bangla ? 'অজানা' : 'unknown';
    const en = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const bn = [
      'জানু', 'ফেব', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
      'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
    ];
    final month = bangla ? bn[d.month - 1] : en[d.month - 1];
    final out = '${d.day} $month ${d.year}';
    return bangla ? toBanglaDigits(out) : out;
  }

  /// "per kg" / "প্রতি কেজি". Returns empty string when there is no unit.
  static String unitLabel(String? unit, {bool bangla = false}) {
    if (unit == null || unit.trim().isEmpty) return '';
    return bangla ? 'প্রতি $unit' : 'per $unit';
  }
}

/// Colour + label for a [Freshness] value, resolved against the active theme.
class FreshnessStyle {
  final Color color;
  final IconData icon;

  const FreshnessStyle(this.color, this.icon);

  static FreshnessStyle of(Freshness f, ColorScheme scheme) {
    switch (f) {
      case Freshness.fresh:
        return const FreshnessStyle(Color(0xFF16A34A), Icons.check_circle_outline);
      case Freshness.recent:
        return FreshnessStyle(scheme.onSurfaceVariant, Icons.schedule_outlined);
      case Freshness.stale:
        return const FreshnessStyle(Color(0xFFD97706), Icons.warning_amber_outlined);
      case Freshness.outdated:
        return FreshnessStyle(scheme.error, Icons.error_outline);
    }
  }
}
