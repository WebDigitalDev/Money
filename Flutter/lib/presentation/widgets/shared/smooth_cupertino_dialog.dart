import 'dart:async';

import 'package:flutter/cupertino.dart';

const Duration appCupertinoDialogTransitionDuration = Duration(
  milliseconds: 180,
);

/// Exibe o diálogo Cupertino com uma transição curta e de baixo custo.
///
/// O conteúdo continua sendo um [CupertinoAlertDialog]. A diferença fica na
/// rota: o zoom nativo de 1.3x é substituído por uma escala discreta para não
/// ampliar o custo do blur enquanto o diálogo entra na tela.
Future<T?> showAppCupertinoDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  bool barrierDismissible = false,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  final Color resolvedBarrierColor = CupertinoDynamicColor.resolve(
    barrierColor ?? kCupertinoModalBarrierColor,
    context,
  );
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ??
        CupertinoLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: resolvedBarrierColor,
    transitionDuration: appCupertinoDialogTransitionDuration,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
    pageBuilder: (routeContext, _, _) => builder(routeContext),
    transitionBuilder: (_, animation, _, child) =>
        _AppCupertinoDialogTransition(animation: animation, child: child),
  );
}

class _AppCupertinoDialogTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _AppCupertinoDialogTransition({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final Curve curve = animation.status == AnimationStatus.reverse
            ? Curves.easeInCubic
            : Curves.easeOutCubic;
        final double progress = curve.transform(animation.value.clamp(0, 1));
        return Opacity(
          opacity: progress,
          child: Transform.scale(scale: .965 + (.035 * progress), child: child),
        );
      },
    );
  }
}

/// Prepara uma única vez o blur, o recorte e a composição usados pelo diálogo.
///
/// A cena de aquecimento fica abaixo da aplicação e sai da árvore logo após os
/// primeiros frames. Assim, o custo da primeira pintura ocorre durante a tela
/// inicial, e não quando o usuário toca para abrir o primeiro diálogo.
class CupertinoDialogRenderingWarmUp extends StatefulWidget {
  final Widget child;

  const CupertinoDialogRenderingWarmUp({super.key, required this.child});

  @override
  State<CupertinoDialogRenderingWarmUp> createState() =>
      _CupertinoDialogRenderingWarmUpState();
}

class _CupertinoDialogRenderingWarmUpState
    extends State<CupertinoDialogRenderingWarmUp> {
  Timer? _removalTimer;
  bool _warmingUp = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _removalTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _warmingUp = false);
      });
    });
  }

  @override
  void dispose() {
    _removalTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_warmingUp)
          const Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: Opacity(
                  // Um alpha não nulo força a pintura, mas permanece invisível
                  // sob a primeira tela opaca da aplicação.
                  opacity: .01,
                  child: CupertinoAlertDialog(
                    title: Text('Money'),
                    content: Text('Inteligência financeira'),
                    actions: [CupertinoDialogAction(child: Text('OK'))],
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
