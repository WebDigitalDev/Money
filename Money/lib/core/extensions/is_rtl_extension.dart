import 'package:flutter/material.dart';

extension IsRtlExtension on BuildContext {
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}
