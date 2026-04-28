import 'package:intl/intl.dart';

/// Centralized formatters keep number/currency presentation consistent.
class Formatters {
  Formatters._();

  static final NumberFormat _usd = NumberFormat.currency(
    locale: 'en_US',
    symbol: r'$',
    decimalDigits: 2,
  );

  static final NumberFormat _usdNoCents = NumberFormat.currency(
    locale: 'en_US',
    symbol: r'$',
    decimalDigits: 0,
  );

  static final NumberFormat _percent = NumberFormat.decimalPattern('en_US')
    ..minimumFractionDigits = 2
    ..maximumFractionDigits = 2;

  static final NumberFormat _crypto = NumberFormat.decimalPattern('en_US')
    ..minimumFractionDigits = 4
    ..maximumFractionDigits = 8;

  static String currency(num value, {bool showCents = true}) {
    return showCents ? _usd.format(value) : _usdNoCents.format(value);
  }

  static String signedCurrency(num value) {
    final String sign = value >= 0 ? '+' : '-';
    return '$sign${_usd.format(value.abs())}';
  }

  static String percent(num value, {bool withSign = true}) {
    final String sign = value >= 0 ? '+' : '-';
    final String body = '${_percent.format(value.abs())}%';
    return withSign ? '$sign$body' : body;
  }

  /// Formats a token quantity with sensible precision.
  static String crypto(num value) => _crypto.format(value);
}
