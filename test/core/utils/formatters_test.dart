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
