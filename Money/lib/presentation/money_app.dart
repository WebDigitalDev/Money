import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:money/money.dart';

class MoneyApp extends StatefulWidget {
  final ThemeMode themeMode;

  const MoneyApp({super.key, required this.themeMode});

  @override
  State<MoneyApp> createState() => _MoneyAppState();
}

class _MoneyAppState extends State<MoneyApp> {
  final TutorialGuideController _tutorialController = TutorialGuideController();

  @override
  void dispose() {
    _tutorialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUpdateTarget? publicDownloadTarget = _publicDownloadTarget();
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (BuildContext context) => SharedCubit(widget.themeMode),
        ),
        BlocProvider(create: (BuildContext context) => HomeCubit()),
      ],
      child: BlocBuilder<SharedCubit, SharedState>(
        buildWhen: (previous, current) => current.runtimeType == SharedInitial,
        builder: (BuildContext context, SharedState state) {
          if (state is SharedInitial) {
            return MaterialApp(
              title: 'Money',
              theme: lightThemeData,
              darkTheme: darkThemeData,
              themeMode: state.themeMode,
              // No web, a animação interpola o tema de todas as páginas já
              // carregadas no IndexedStack e provoca uma pausa perceptível.
              // A troca imediata evita esses repaints intermediários.
              themeAnimationDuration: kIsWeb
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              themeAnimationCurve: Curves.easeOutCubic,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppStrings.supportedLocales,
              locale: AppStrings.defaultLocale,
              builder: (context, child) {
                final Widget application = CupertinoDialogRenderingWarmUp(
                  child: AnimatedBuilder(
                    animation: _tutorialController,
                    child: child ?? const SizedBox.shrink(),
                    builder: (context, application) {
                      final TutorialPhase phase = _tutorialController.phase;
                      return PopScope<void>(
                        canPop: !_tutorialController.active,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            application!,
                            if (phase != TutorialPhase.hidden)
                              Overlay(
                                key: ValueKey<TutorialPhase>(phase),
                                initialEntries: [
                                  OverlayEntry(
                                    builder: (tutorialContext) => switch (phase) {
                                      TutorialPhase.introduction =>
                                        InitialTutorialOverlay(
                                          requireUserAction: _tutorialController
                                              .introductionRequiresUserAction,
                                          onStart: () {
                                            final bool desktop =
                                                kIsWeb &&
                                                MediaQuery.sizeOf(
                                                      tutorialContext,
                                                    ).width >=
                                                    1024;
                                            _tutorialController
                                                .beginWalkthrough(
                                                  useMobileNavigation: !desktop,
                                                );
                                          },
                                        ),
                                      TutorialPhase.mobileNavigation =>
                                        MobileNavigationTutorialOverlay(
                                          controller: _tutorialController,
                                        ),
                                      TutorialPhase.walkthrough =>
                                        GuidedTutorialOverlay(
                                          controller: _tutorialController,
                                        ),
                                      TutorialPhase.conclusion =>
                                        FinalTutorialOverlay(
                                          controller: _tutorialController,
                                          onComplete: _completeTutorial,
                                        ),
                                      TutorialPhase.hidden =>
                                        const SizedBox.shrink(),
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                );
                return publicDownloadTarget != null
                    ? application
                    : MandatoryUpdateGate(child: application);
              },
              home: switch (publicDownloadTarget) {
                AppUpdateTarget.android => const AndroidDownloadScreen(),
                AppUpdateTarget.ios => const IosDownloadScreen(),
                _ => BlocListener<SharedCubit, SharedState>(
                  listener: (context, state) {
                    if (state is ShowModalBottomSheet) {
                      _showModalBottomSheet(
                        context,
                        state.builder,
                        backgroundColor: state.backgroundColor,
                      );
                    }
                  },
                  child: _AppEntryScreen(
                    tutorialController: _tutorialController,
                  ),
                ),
              },
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  AppUpdateTarget? _publicDownloadTarget() {
    if (!kIsWeb) return null;
    final String path = Uri.base.path.replaceFirst(RegExp(r'/+$'), '');
    return switch (path) {
      '/download/android' => AppUpdateTarget.android,
      '/download/ios' => AppUpdateTarget.ios,
      _ => null,
    };
  }

  Future<void> _completeTutorial() async {
    await AuthService().completeTutorial();
    _tutorialController.complete();
  }

  void _showModalBottomSheet(
    BuildContext context,
    WidgetBuilder builder, {
    Color? backgroundColor,
  }) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: context.isRtl
              ? Radius.zero
              : Radius.circular(MediaQuery.of(context).size.width * 0.11),
          topLeft: !context.isRtl
              ? Radius.zero
              : Radius.circular(MediaQuery.of(context).size.width * 0.11),
        ),
      ),
      constraints: BoxConstraints(minHeight: 0),
      backgroundColor: backgroundColor,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      builder: builder,
    );
  }
}

class _AppEntryScreen extends StatefulWidget {
  final TutorialGuideController tutorialController;

  const _AppEntryScreen({required this.tutorialController});

  @override
  State<_AppEntryScreen> createState() => _AppEntryScreenState();
}

enum _AppEntryStage { initializing, login, locked, application }

class _AppEntryScreenState extends State<_AppEntryScreen> {
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatusService = NetworkStatusService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();

  _AppEntryStage _stage = _AppEntryStage.initializing;
  Future<void>? _assetsReady;
  bool _initializationStarted = false;
  bool _revalidatingAfterReconnect = false;
  Timer? _revalidationRetry;
  String? _loginFeedbackTitle;
  String? _loginFeedbackMessage;

  @override
  void initState() {
    super.initState();
    _networkStatusService.start();
    _networkStatusService.statusListenable.addListener(
      _handleNetworkStatusChanged,
    );
  }

  @override
  void dispose() {
    _revalidationRetry?.cancel();
    _networkStatusService.statusListenable.removeListener(
      _handleNetworkStatusChanged,
    );
    _networkStatusService.stop();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _assetsReady ??= _precacheApplicationAssets().onError((_, _) {});
    if (_initializationStarted) return;

    _initializationStarted = true;
    _restoreSavedAccess();
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _AppEntryStage.initializing:
        return const _SessionLoadingScreen();
      case _AppEntryStage.locked:
        return BlocProvider(
          create: (_) => LockedAppCubit(),
          child: LockedAppScreen(
            onAccessGranted: () => _openApplication(),
            onAccessRejected: _returnToLoginAfterRejectedAccess,
          ),
        );
      case _AppEntryStage.application:
        return ValueListenableBuilder<NetworkStatus>(
          valueListenable: _networkStatusService.statusListenable,
          child: HomeScreen(
            onLogout: _logout,
            tutorialController: widget.tutorialController,
          ),
          builder: (context, status, application) => IndexedStack(
            index: status == NetworkStatus.offline ? 1 : 0,
            children: [application!, const OfflineScreen(showAppBar: false)],
          ),
        );
      case _AppEntryStage.login:
        return LoginScreen(
          onAuthenticated: () => _openApplication(),
          initialFeedbackTitle: _loginFeedbackTitle,
          initialFeedbackMessage: _loginFeedbackMessage,
        );
    }
  }

  Future<void> _precacheApplicationAssets() async {
    await Future.wait<void>([
      ...AppIcons.all.map((String asset) async {
        await SvgAssetLoader(asset).loadBytes(context);
      }),
      precacheImage(const AssetImage(AppImages.logo), context),
      precacheImage(const AssetImage(AppImages.money), context),
      precacheImage(const AssetImage(AppImages.moneyBr), context),
      precacheImage(const AssetImage(AppImages.blocked), context),
      precacheImage(const AssetImage(AppImages.update), context),
      precacheImage(const AssetImage(AppImages.connection), context),
      precacheImage(const AssetImage(AppImages.virtualDashboard), context),
      precacheImage(const AssetImage(AppImages.virtualAssistant), context),
    ]);
  }

  Future<void> _openApplication({bool restoredSession = false}) async {
    if (!_authService.isOfflineSession &&
        _authService.currentSession?.forcePasswordChange == true) {
      final bool? passwordChanged = await showAppCupertinoDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _RequiredPasswordChangeDialog(),
      );
      if (passwordChanged != true || !mounted) return;
    }

    if (!mounted) return;

    final bool enteringApplication = _stage != _AppEntryStage.application;
    setState(() {
      _loginFeedbackTitle = null;
      _loginFeedbackMessage = null;
      _stage = _AppEntryStage.application;
    });
    if (enteringApplication) {
      if (_authService.currentSession?.tutorialCompleted == true) {
        widget.tutorialController.hide();
      } else {
        widget.tutorialController.showIntroduction(
          requireUserAction: kIsWeb && restoredSession,
        );
      }
    }
  }

  Future<void> _restoreSavedAccess() async {
    try {
      if (!await _authService.hasSavedCredentials()) {
        _showLogin();
        return;
      }

      final bool biometricLockEnabled =
          !kIsWeb && await _preferencesService.getLockAppStatus();
      if (biometricLockEnabled) {
        if (!mounted) return;
        setState(() => _stage = _AppEntryStage.locked);
        return;
      }

      if (!await _networkStatusService.checkNow()) {
        if (await _authService.restoreOfflineSession()) {
          await _openApplication(restoredSession: true);
        } else {
          _showLogin(
            title: 'Sem internet',
            message:
                'Conecte-se à internet para validar este acesso pela primeira vez.',
          );
        }
        return;
      }

      await _validateSavedAccess();
    } catch (_) {
      _showLogin(
        title: 'Login não realizado',
        message: 'Não foi possível recuperar seu acesso. Tente novamente.',
      );
    }
  }

  Future<void> _validateSavedAccess() async {
    try {
      await _authService.signInWithSavedCredentials();
      await _openApplication(restoredSession: true);
    } on AuthenticationException catch (error) {
      if (error.kind == AuthenticationFailureKind.network &&
          await _authService.restoreOfflineSession()) {
        await _openApplication(restoredSession: true);
        return;
      }
      final bool accessRejected = _isAccessRejected(error);
      if (accessRejected) {
        await _authService.clearSavedCredentials();
      }
      _showLogin(
        title: accessRejected ? 'Entre novamente' : 'Login não realizado',
        message: _accessErrorMessage(error),
      );
    } catch (_) {
      _showLogin(
        title: 'Login não realizado',
        message: 'Não foi possível entrar. Tente novamente.',
      );
    }
  }

  Future<void> _returnToLoginAfterRejectedAccess(
    AuthenticationException error,
  ) async {
    _showLogin(title: 'Entre novamente', message: _accessErrorMessage(error));
  }

  Future<void> _logout() async {
    await _authService.signOut();
    UserService().clearCache();
    RegionService().clearCache();
    ClientService().clearCache();
    if (!mounted) return;

    context.read<HomeCubit>().onPageChanged(index: 0);
    _showLogin();
  }

  bool _isAccessRejected(AuthenticationException error) {
    return error.kind == AuthenticationFailureKind.invalidCredentials ||
        error.kind == AuthenticationFailureKind.forbidden;
  }

  String _accessErrorMessage(AuthenticationException error) {
    if (error.kind == AuthenticationFailureKind.invalidCredentials) {
      return 'Sua senha foi alterada ou o acesso salvo não é mais válido.';
    }
    return error.message;
  }

  void _showLogin({String? title, String? message}) {
    if (!mounted) return;

    widget.tutorialController.hide();
    setState(() {
      _loginFeedbackTitle = title;
      _loginFeedbackMessage = message;
      _stage = _AppEntryStage.login;
    });
  }

  void _handleNetworkStatusChanged() {
    if (_networkStatusService.status != NetworkStatus.online ||
        _stage != _AppEntryStage.application ||
        !_authService.isOfflineSession) {
      return;
    }
    unawaited(_revalidateAfterReconnect());
  }

  Future<void> _revalidateAfterReconnect() async {
    if (_revalidatingAfterReconnect) return;
    _revalidationRetry?.cancel();
    _revalidationRetry = null;
    _revalidatingAfterReconnect = true;
    try {
      await _authService.signInWithSavedCredentials();
      if (!mounted) return;
      await _openApplication();
    } on AuthenticationException catch (error) {
      if (!mounted) return;
      if (_isAccessRejected(error)) {
        await _authService.clearSavedCredentials();
        _showLogin(
          title: 'Entre novamente',
          message: _accessErrorMessage(error),
        );
      } else {
        _scheduleRevalidationRetry();
      }
    } catch (_) {
      _scheduleRevalidationRetry();
    } finally {
      _revalidatingAfterReconnect = false;
    }
  }

  void _scheduleRevalidationRetry() {
    _revalidationRetry?.cancel();
    _revalidationRetry = Timer(const Duration(seconds: 10), () {
      if (!mounted ||
          _networkStatusService.status != NetworkStatus.online ||
          !_authService.isOfflineSession) {
        return;
      }
      unawaited(_revalidateAfterReconnect());
    });
  }
}

class _RequiredPasswordChangeDialog extends StatefulWidget {
  const _RequiredPasswordChangeDialog();

  @override
  State<_RequiredPasswordChangeDialog> createState() =>
      _RequiredPasswordChangeDialogState();
}

class _RequiredPasswordChangeDialogState
    extends State<_RequiredPasswordChangeDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      child: CupertinoAlertDialog(
        title: const Text('Troca de senha obrigatória'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: [
              const Text(
                'Defina uma nova senha numérica para continuar no Money.',
              ),
              const SizedBox(height: 12),
              _PasswordField(
                controller: _passwordController,
                placeholder: 'Nova senha',
                obscureText: _obscurePassword,
                onToggleVisibility: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              const SizedBox(height: 8),
              _PasswordField(
                controller: _confirmationController,
                placeholder: 'Confirmar nova senha',
                obscureText: _obscureConfirmation,
                onToggleVisibility: () => setState(
                  () => _obscureConfirmation = !_obscureConfirmation,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 9),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: CupertinoColors.systemRed,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CupertinoActivityIndicator(),
                  )
                : const Text(
                    'Alterar senha',
                    style: TextStyle(color: Color(0xFF76B475)),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final String password = _passwordController.text;
    final String confirmation = _confirmationController.text;
    if (password.length < 4) {
      setState(() => _errorMessage = 'Informe pelo menos 4 números.');
      return;
    }
    if (password != confirmation) {
      setState(() => _errorMessage = 'As senhas informadas não conferem.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await AuthService().changeRequiredPassword(password);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AuthenticationException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'Não foi possível alterar a senha. Tente novamente.';
      });
    }
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final bool obscureText;
  final VoidCallback onToggleVisibility;

  const _PasswordField({
    required this.controller,
    required this.placeholder,
    required this.obscureText,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: TextInputType.number,
      obscureText: obscureText,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 64,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 4, 11),
      suffix: CupertinoButton(
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: onToggleVisibility,
        child: Icon(
          obscureText ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          size: 18,
          color: const Color(0xFF76B475),
        ),
      ),
    );
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4B7D60), Color(0xFF76B475), Color(0xFFA8D6A0)],
            stops: [0, 0.52, 1],
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
                      strokeWidth: 2.4,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
