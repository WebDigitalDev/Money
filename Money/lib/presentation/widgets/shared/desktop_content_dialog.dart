import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:money/money.dart';

Future<T?> showDesktopContentDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 920,
  VoidCallback? onClose,
}) {
  final Size screenSize = MediaQuery.sizeOf(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: math.min(maxWidth, screenSize.width - 48),
        height: math.min(860, screenSize.height - 48),
        child: Material(
          color: dialogContext.colors.background,
          child: Column(
            children: [
              SizedBox(
                height: 46,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: IconButton(
                      onPressed:
                          onClose ?? () => Navigator.of(dialogContext).pop(),
                      tooltip: 'Fechar',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        color: dialogContext.colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: dialogContext.colors.divider),
              Expanded(child: builder(dialogContext)),
            ],
          ),
        ),
      ),
    ),
  );
}
