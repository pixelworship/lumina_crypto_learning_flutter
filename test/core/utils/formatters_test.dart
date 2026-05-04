import 'package:flutter_demo/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters.currency', () {
    test('formats whole-dollar amounts with cents by default', () {
      expect(Formatters.currency(1234.5), r'$1,234.50');
    });

    test('omits cents when showCents is false', () {
      expect(Formatters.currency(1234.5, showCents: false), r'$1,235');
    });

    test('handles zero', () {
      expect(Formatters.currency(0), r'$0.00');
    });

    test('formats large values with thousands separators', () {
      expect(Formatters.currency(1234567.89), r'$1,234,567.89');
    });

    test('formats negative values with a leading minus before the symbol', () {
      expect(Formatters.currency(-42.5), r'-$42.50');
    });
  });

  group('Formatters.signedCurrency', () {
    test('prefixes positive values with +', () {
      expect(Formatters.signedCurrency(120.5), r'+$120.50');
    });

    test('prefixes negative values with - and uses absolute value', () {
      expect(Formatters.signedCurrency(-42.5), r'-$42.50');
    });

    test('prefixes zero with + (zero is treated as non-negative)', () {
      expect(Formatters.signedCurrency(0), r'+$0.00');
    });
  });

  group('Formatters.compactCurrency', () {
    test('keeps the full form for values under the compact threshold', () {
      expect(Formatters.compactCurrency(0), r'$0.00');
      expect(Formatters.compactCurrency(99.99), r'$99.99');
      expect(Formatters.compactCurrency(999.99), r'$999.99');
    });

    test('compacts thousands to K', () {
      expect(Formatters.compactCurrency(1500), r'$1.5K');
      expect(Formatters.compactCurrency(64289.5), r'$64.3K');
    });

    test('compacts millions to M', () {
      expect(Formatters.compactCurrency(1234567.89), r'$1.2M');
    });

    test('compacts billions to B', () {
      expect(Formatters.compactCurrency(2.5e9), r'$2.5B');
    });

    test('handles negative values', () {
      expect(Formatters.compactCurrency(-64289.5), r'-$64.3K');
    });
  });

  group('Formatters.signedCompactCurrency', () {
    test('prefixes positive compact values with +', () {
      expect(Formatters.signedCompactCurrency(64289.5), r'+$64.3K');
    });

    test('prefixes negative compact values with - on absolute value', () {
      expect(Formatters.signedCompactCurrency(-64289.5), r'-$64.3K');
    });

    test('prefixes small values with +/- using full currency form', () {
      expect(Formatters.signedCompactCurrency(120.5), r'+$120.50');
      expect(Formatters.signedCompactCurrency(-42.5), r'-$42.50');
    });
  });

  group('Formatters.percent', () {
    test('formats positive percent with + sign by default', () {
      expect(Formatters.percent(2.4), '+2.40%');
    });

    test('formats negative percent with - sign', () {
      expect(Formatters.percent(-1.5), '-1.50%');
    });

    test('omits sign when withSign is false', () {
      expect(Formatters.percent(2.4, withSign: false), '2.40%');
      expect(Formatters.percent(-2.4, withSign: false), '2.40%');
    });

    test('always shows two decimal places', () {
      expect(Formatters.percent(3), '+3.00%');
      expect(Formatters.percent(0.1), '+0.10%');
    });

    test('rounds to two decimal places', () {
      expect(Formatters.percent(2.456), '+2.46%');
    });
  });

  group('Formatters.crypto', () {
    test('renders at least four decimal places', () {
      expect(Formatters.crypto(1), '1.0000');
    });

    test('preserves up to eight decimal places of precision', () {
      expect(Formatters.crypto(0.12345678), '0.12345678');
    });

    test('formats large values with thousands separators', () {
      expect(Formatters.crypto(25876.55), '25,876.5500');
    });
  });
}
