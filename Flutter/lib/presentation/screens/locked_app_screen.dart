import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:money/money.dart';

class LockedAppScreen extends StatefulWidget {
  final Future<void> Function() onAccessGranted;
  final Future<void> Function(AuthenticationException error) onAccessRejected;

  const LockedAppScreen({
    super.key,
    required this.onAccessGranted,
    required this.onAccessRejected,
  });

  @override
  State<LockedAppScreen> createState() => _LockedAppScreenState();
}

class _LockedAppScreenState extends State<LockedAppScreen> {
  final AuthService _authService = AuthService();

  bool _requestedUnlock = false;
  bool _isValidatingSession = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedUnlock) return;

    _requestedUnlock = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestUnlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          minimum: EdgeInsets.only(bottom: AppDimensions.padding),
          child: BlocListener<LockedAppCubit, LockedAppState>(
            listener: (context, state) async {
              if (state is UnlockedApp) {
                await _validateSavedAccess();
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
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
                                  AppImages.blocked,
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
                            onPressed: _isValidatingSession
                                ? null
                                : _requestUnlock,
                            child: _isValidatingSession
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Text(context.tr!.unlock.toUpperCase()),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _requestUnlock() {
    if (_isValidatingSession) return;
    context.read<LockedAppCubit>().unlock(context.tr!.app_locked_description);
  }

  Future<void> _validateSavedAccess() async {
    if (_isValidatingSession || !mounted) return;

    setState(() => _isValidatingSession = true);

    try {
      await _authService.signInWithSavedCredentials();
      await widget.onAccessGranted();
    } on AuthenticationException catch (error) {
      if (error.kind == AuthenticationFailureKind.network &&
          await _authService.restoreOfflineSession()) {
        await widget.onAccessGranted();
        return;
      }
      final bool accessRejected =
          error.kind == AuthenticationFailureKind.invalidCredentials ||
          error.kind == AuthenticationFailureKind.forbidden;

      if (accessRejected) {
        await _authService.clearSavedCredentials();
        await widget.onAccessRejected(error);
      } else {
        await _showFeedbackDialog(
          title: 'Não foi possível validar o acesso',
          message: error.message,
        );
      }
    } catch (_) {
      await _showFeedbackDialog(
        title: 'Não foi possível validar o acesso',
        message: 'Não foi possível entrar. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _isValidatingSession = false);
      }
    }
  }

  Future<void> _showFeedbackDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showAppCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFF76B475)),
              ),
            ),
          ],
        );
      },
    );
  }
}
