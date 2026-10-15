import 'package:flutter/material.dart';
import 'package:money/money.dart';

class NetworkAwareContent extends StatelessWidget {
  final Widget child;
  final bool showAppBar;

  const NetworkAwareContent({
    super.key,
    required this.child,
    required this.showAppBar,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkStatus>(
      valueListenable: NetworkStatusService().statusListenable,
      child: child,
      builder: (context, status, onlineContent) {
        if (status == NetworkStatus.offline) {
          return OfflineScreen(showAppBar: showAppBar);
        }
        return onlineContent!;
      },
    );
  }
}

class OfflineScreen extends StatefulWidget {
  final bool showAppBar;

  const OfflineScreen({super.key, this.showAppBar = true});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          minimum: EdgeInsets.only(bottom: AppDimensions.padding),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 35),
                            Image.asset(
                              AppImages.money,
                              width: (constraints.maxWidth * 0.60).clamp(
                                190.0,
                                210.0,
                              ),
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 24),
                            Image.asset(
                              AppImages.connection,
                              width: constraints.maxWidth,
                              fit: BoxFit.fitWidth,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppDimensions.padding * 2,
                    0,
                    AppDimensions.padding * 2,
                    AppDimensions.padding * 2,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _checking ? null : _retry,
                        child: _checking
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Text('RECONECTAR'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _checking = true);
    await NetworkStatusService().checkNow();
    if (mounted) setState(() => _checking = false);
  }
}
