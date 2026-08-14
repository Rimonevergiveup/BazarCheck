import 'package:bazarcheck_app/core/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fmt.price', () {
    test('returns null for a null amount, never ৳0', () {
      // The original bug: `(json['price'] as num?)?.toDouble() ?? 0.0` turned
      // "no price" into a confident ৳0, which reads as "this is free".
      expect(Fmt.price(null), isNull);
    });

    test('formats whole taka without decimals', () {
      expect(Fmt.price(72), '৳72');
      expect(Fmt.price(1234), '৳1,234');
    });

    test('keeps paisa for small fractional amounts', () {
      expect(Fmt.price(24.99), '৳24.99');
    });

    test('uses South Asian lakh/crore grouping, not Western', () {
      // Bangladeshi convention: 1,23,456 — not 123,456
      expect(Fmt.price(123456), '৳1,23,456');
      expect(Fmt.price(12345678), '৳1,23,45,678');
      expect(Fmt.price(999), '৳999');
      expect(Fmt.price(1000), '৳1,000');
    });

    test('renders Bangla digits when asked', () {
      expect(Fmt.price(1234, bangla: true), '৳১,২৩৪');
      expect(Fmt.price(72, bangla: true), '৳৭২');
    });

    test('handles zero as a real price, distinct from null', () {
      expect(Fmt.price(0), '৳0');
      expect(Fmt.price(null), isNull);
    });

    test('handles negatives without mangling the symbol', () {
      expect(Fmt.price(-50), '-৳50');
    });
  });

  group('Fmt.priceRange', () {
    test('collapses to one figure when min == max', () {
      expect(Fmt.priceRange(72, 72), '৳72');
    });

    test('shows both ends when sellers disagree', () {
      expect(Fmt.priceRange(72, 85), '৳72 – ৳85');
    });

    test('is null when there is no price at all', () {
      expect(Fmt.priceRange(null, null), isNull);
    });

    test('shows just the minimum when max is unknown', () {
      expect(Fmt.priceRange(72, null), '৳72');
    });
  });

  group('Fmt.toBanglaDigits', () {
    test('converts digits and leaves other characters alone', () {
      expect(Fmt.toBanglaDigits('2026-08-11'), '২০২৬-০৮-১১');
      expect(Fmt.toBanglaDigits('abc'), 'abc');
      expect(Fmt.toBanglaDigits('৳1,234'), '৳১,২৩৪');
    });
  });

  group('Fmt.relativeTime', () {
    final now = DateTime(2026, 8, 11, 12, 0);

    test('says just now for the last minute', () {
      expect(
        Fmt.relativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        'just now',
      );
    });

    test('minutes, hours, days, months, years', () {
      expect(Fmt.relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(Fmt.relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(Fmt.relativeTime(now.subtract(const Duration(days: 5)), now: now), '5d ago');
      expect(Fmt.relativeTime(now.subtract(const Duration(days: 60)), now: now), '2mo ago');
      expect(Fmt.relativeTime(now.subtract(const Duration(days: 400)), now: now), '1y ago');
    });

    test('reports unknown rather than guessing when there is no timestamp', () {
      expect(Fmt.relativeTime(null), 'unknown');
      expect(Fmt.relativeTime(null, bangla: true), 'অজানা');
    });

    test('renders Bangla wording and digits', () {
      expect(
        Fmt.relativeTime(now.subtract(const Duration(hours: 3)), bangla: true, now: now),
        '৩ ঘণ্টা আগে',
      );
    });
  });

  group('Freshness', () {
    final now = DateTime(2026, 8, 11, 12, 0);

    test('fresh under 24 hours', () {
      expect(Freshness.of(now.subtract(const Duration(hours: 5)), now: now),
          Freshness.fresh);
    });

    test('recent under 7 days', () {
      expect(Freshness.of(now.subtract(const Duration(days: 3)), now: now),
          Freshness.recent);
    });

    test('stale between 7 and 30 days', () {
      expect(Freshness.of(now.subtract(const Duration(days: 10)), now: now),
          Freshness.stale);
    });

    test('outdated beyond 30 days', () {
      expect(Freshness.of(now.subtract(const Duration(days: 90)), now: now),
          Freshness.outdated);
    });

    test('a missing timestamp is outdated, not fresh', () {
      // Failing "safe" here matters: unknown age must never look current.
      expect(Freshness.of(null), Freshness.outdated);
    });

    test('tolerates clock skew from the future', () {
      expect(Freshness.of(now.add(const Duration(hours: 2)), now: now),
          Freshness.fresh);
    });

    test('only fresh and recent count as trustworthy', () {
      expect(Freshness.fresh.isTrustworthy, isTrue);
      expect(Freshness.recent.isTrustworthy, isTrue);
      expect(Freshness.stale.isTrustworthy, isFalse);
      expect(Freshness.outdated.isTrustworthy, isFalse);
    });
  });

  group('Fmt.unitLabel', () {
    test('formats per-unit text in both languages', () {
      expect(Fmt.unitLabel('kg'), 'per kg');
      expect(Fmt.unitLabel('kg', bangla: true), 'প্রতি kg');
    });

    test('is empty when there is no unit', () {
      expect(Fmt.unitLabel(null), '');
      expect(Fmt.unitLabel('  '), '');
    });
  });
}
