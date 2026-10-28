import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money/money.dart';

class MandatoryUpdateGate extends StatefulWidget {
  final Widget child;

  const MandatoryUpdateGate({super.key, required this.child});

  @override
  State<MandatoryUpdateGate> createState() => _MandatoryUpdateGateState();
}

class _MandatoryUpdateGateState extends State<MandatoryUpdateGate>
    with WidgetsBindingObserver {
  static const Duration _checkInterval = Duration(seconds: 20);

  final AppUpdateService _updateService = AppUpdateService();
  final NetworkStatusService _networkStatusService = NetworkStatusService();

  Timer? _timer;
  RequiredAppUpdate? _requiredUpdate;
  bool _initialCheck = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _networkStatusService.start();
    _networkStatusService.statusListenable.addListener(_handleNetworkChange);
    _timer = Timer.periodic(_checkInterval, (_) => unawaited(_check()));
    unawaited(_check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _networkStatusService.statusListenable.removeListener(_handleNetworkChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  Widget build(BuildContext context) {
    if (_initialCheck) return const _UpdateCheckLoadingScreen();
    final RequiredAppUpdate? update = _requiredUpdate;
    if (update != null) {
      return UpdateRequiredScreen(key: ValueKey(update.target), update: update);
    }
    return widget.child;
  }

  void _handleNetworkChange() {
    if (_networkStatusService.status == NetworkStatus.online) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final RequiredAppUpdate? update = await _updateService
          .checkForRequiredUpdate();
      if (!mounted) return;
      final bool changed = _requiredUpdate == null
          ? update != null
          : !_requiredUpdate!.sameRelease(update);
      if (_initialCheck || changed) {
        setState(() {
          _initialCheck = false;
          _requiredUpdate = update;
        });
      }
    } finally {
      _checking = false;
      if (mounted && _initialCheck) setState(() => _initialCheck = false);
    }
  }
}

class _UpdateCheckLoadingScreen extends StatelessWidget {
  const _UpdateCheckLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color(0xFF4B7D60),
            Color(0xFF76B475),
            Color(0xFFA8D6A0),
          ],
          stops: <double>[0, 0.52, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Opacity(
                  opacity: 0.48,
                  child: Image.asset(
                    AppImages.moneyBr,
                    width: constraints.maxWidth < 600 ? 300 : 400,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(height: 30),
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.6,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
