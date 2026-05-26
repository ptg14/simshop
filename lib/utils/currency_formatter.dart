import 'package:intl/intl.dart';

/// Format a number as Vietnamese currency.
String formatCurrency(double amount) {
  final formatter = NumberFormat('#,###');
  return '${formatter.format(amount.toInt())}đ';
}

/// Format a number as Vietnamese currency with decimals.
String formatCurrencyWithDecimals(double amount) {
  final formatter = NumberFormat('#,###.##');
  return '${formatter.format(amount)}đ';
}

/// Parse a currency string to double.
double parseCurrency(String currencyString) {
  final cleanString = currencyString
      .replaceAll('đ', '')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .trim();
  return double.tryParse(cleanString) ?? 0.0;
}
