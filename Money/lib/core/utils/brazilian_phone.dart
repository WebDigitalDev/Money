import 'package:flutter/services.dart';

String brazilianPhoneDigits(String value) =>
    value.replaceAll(RegExp(r'\D'), '');

String formatBrazilianPhone(String? value) {
  final String rawDigits = brazilianPhoneDigits(value ?? '');
  final String digits = rawDigits.length > 11
      ? rawDigits.substring(0, 11)
      : rawDigits;
  if (digits.isEmpty) return '';
  if (digits.length < 3) return '(${digits.substring(0, digits.length)}';

  final String areaCode = digits.substring(0, 2);
  final String subscriber = digits.substring(2);
  final int prefixLength = digits.length == 11 ? 5 : 4;
  if (subscriber.length <= prefixLength) {
    return '($areaCode) $subscriber';
  }
  return '($areaCode) ${subscriber.substring(0, prefixLength)}-'
      '${subscriber.substring(prefixLength)}';
}

class BrazilianPhoneInputFormatter extends TextInputFormatter {
  const BrazilianPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String formatted = formatBrazilianPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
