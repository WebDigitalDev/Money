import 'package:flutter/widgets.dart';
import 'package:money/money.dart';

extension TranslateExtension on BuildContext {
  AppLocalizations? get tr => AppLocalizations.of(this);
}
