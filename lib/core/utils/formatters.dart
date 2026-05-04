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

  /// Threshold above which compact formatting kicks in. Below this we
  /// keep the full `$N,NNN.NN` form so small balances don't lose their
  /// cents to the compact format's coarser precision.
  static const double _compactThreshold = 1000;

  static final NumberFormat _percent = NumberFormat.decimalPattern('en_US')
    ..minimumFractionDigits = 2
    ..maximumFractionDigits = 2;

  static final NumberFormat _crypto = NumberFormat.decimalPattern('en_US')
    ..minimumFractionDigits = 4
    ..maximumFractionDigits = 8;

  static final NumberFormat _volume = NumberFormat('#,##0', 'en_US');

  static String currency(num value, {bool showCents = true}) {
    return showCents ? _usd.format(value) : _usdNoCents.format(value);
  }

  static String signedCurrency(num value) {
    final String sign = value >= 0 ? '+' : '-';
    return '$sign${_usd.format(value.abs())}';
  }

  /// Compact USD format for large numbers, e.g. `$64.3K`, `$1.2M`,
  /// `$1.5B`. Values under [_compactThreshold] fall back to the
  /// regular `currency` format (`$100.00`, `$999.99`).
  ///
  /// Implemented manually rather than via `NumberFormat.compactCurrency`
  /// because the intl compact format doesn't honor `decimalDigits: 1`
  /// consistently across K/M/B magnitudes (it'll happily emit
  /// `$1.23M` even when asked for one decimal).
  static String compactCurrency(num value) {
    final double absValue = value.abs().toDouble();
    if (absValue < _compactThreshold) return _usd.format(value);

    final String suffix;
    final double scaled;
    if (absValue >= 1e12) {
      suffix = 'T';
      scaled = absValue / 1e12;
    } else if (absValue >= 1e9) {
      suffix = 'B';
      scaled = absValue / 1e9;
    } else if (absValue >= 1e6) {
      suffix = 'M';
      scaled = absValue / 1e6;
    } else {
      suffix = 'K';
      scaled = absValue / 1e3;
    }

    final String body = scaled.toStringAsFixed(1);
    final String prefix = value < 0 ? r'-$' : r'$';
    return '$prefix$body$suffix';
  }

  /// Same as [compactCurrency] but always prefixed with `+` or `-`.
  /// E.g. `+$64.3K`, `-$1.2M`. Useful for delta values like 24h
  /// change or unrealized P&L.
  static String signedCompactCurrency(num value) {
    final String sign = value >= 0 ? '+' : '-';
    return '$sign${compactCurrency(value.abs())}';
  }

  static String percent(num value, {bool withSign = true}) {
    final String sign = value >= 0 ? '+' : '-';
    final String body = '${_percent.format(value.abs())}%';
    return withSign ? '$sign$body' : body;
  }

  /// Formats a token quantity with sensible precision.
  static String crypto(num value) => _crypto.format(value);

  /// Whole-unit count with thousands separators: `12,345`. Useful for
  /// non-currency quantities like trade volume.
  static String volume(num value) => _volume.format(value);
}
