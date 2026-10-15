import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:money/money.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LoginScreen extends StatefulWidget {
  final Future<void> Function() onAuthenticated;
  final String? initialFeedbackTitle;
  final String? initialFeedbackMessage;

  const LoginScreen({
    super.key,
    required this.onAuthenticated,
    this.initialFeedbackTitle,
    this.initialFeedbackMessage,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  final AuthService _authService = AuthService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();

  bool _canUseBiometrics = false;
  bool _biometricEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeLogin();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bool keyboardOpen = keyboardInset > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4B7D60), Color(0xFF76B475), Color(0xFFA8D6A0)],
            stops: [0, 0.52, 1],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool compact = constraints.maxWidth < 600;
                    final double horizontalPadding = compact ? 36 : 48;
                    final double loginFieldWidth = compact
                        ? constraints.maxWidth - 48
                        : 460;

                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        keyboardOpen ? 24 : 0,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: AutofillGroup(
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: constraints.maxHeight * 0.035,
                                  ),
                                  SizedBox(
                                    width: double.infinity,
                                    height: compact ? 92 : 118,
                                    child: Transform.translate(
                                      offset: Offset(
                                        0,
                                        -constraints.maxHeight * 0.09,
                                      ),
                                      child: Center(
                                        child: Opacity(
                                          opacity: 0.48,
                                          child: Image.asset(
                                            AppImages.moneyBr,
                                            width: compact ? 320 : 400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      'Olá, seja bem-vindo!',
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.88,
                                        ),
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      'Digite seu Usuário e Senha do aplicativo.',
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.68,
                                        ),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.15,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: constraints.maxHeight * 0.03,
                                  ),
                                  SizedBox(
                                    height: 50,
                                    child: OverflowBox(
                                      alignment: Alignment.center,
                                      minWidth: loginFieldWidth,
                                      maxWidth: loginFieldWidth,
                                      child: SizedBox(
                                        width: loginFieldWidth,
                                        child: _LoginField(
                                          controller: _usernameController,
                                          hintText: 'Usuário',
                                          icon: Icons.person_rounded,
                                          keyboardType: TextInputType.name,
                                          textCapitalization:
                                              TextCapitalization.characters,
                                          textInputAction: TextInputAction.next,
                                          enabled: !_isLoading,
                                          autofillHints: const [
                                            AutofillHints.username,
                                          ],
                                          inputFormatters: const [
                                            _LettersOnlyTextFormatter(),
                                            _UpperCaseTextFormatter(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 50,
                                    child: OverflowBox(
                                      alignment: Alignment.center,
                                      minWidth: loginFieldWidth,
                                      maxWidth: loginFieldWidth,
                                      child: SizedBox(
                                        width: loginFieldWidth,
                                        child: _LoginField(
                                          controller: _passwordController,
                                          hintText: 'Senha',
                                          icon: Icons.lock_rounded,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.done,
                                          obscureText: true,
                                          enabled: !_isLoading,
                                          autofillHints: const [
                                            AutofillHints.password,
                                          ],
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          onSubmitted: (_) => _submitLogin(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_canUseBiometrics) ...[
                                    const SizedBox(height: 14),
                                    _BiometricOption(
                                      value: _biometricEnabled,
                                      enabled: !_isLoading,
                                      onChanged: _setBiometricEnabled,
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: FilledButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _submitLogin,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        disabledBackgroundColor: Colors.white
                                            .withValues(alpha: 0.72),
                                        foregroundColor: const Color(
                                          0xFF76B475,
                                        ),
                                        elevation: 0,
                                        shape: const StadiumBorder(),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox.square(
                                              dimension: 22,
                                              child: CircularProgressIndicator(
                                                color: Color(0xFF76B475),
                                                strokeWidth: 2.4,
                                              ),
                                            )
                                          : const Text(
                                              'ENTRAR',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 70),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (!keyboardOpen)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: _AppVersionLabel(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeLogin() async {
    bool canUseBiometrics = false;
    bool biometricEnabled = false;
    String? savedUsername;

    if (!kIsWeb) {
      try {
        final List<BiometricType> availableBiometrics =
            await _localAuthentication.getAvailableBiometrics();
        canUseBiometrics = availableBiometrics.isNotEmpty;
        biometricEnabled = canUseBiometrics
            ? await _preferencesService.getLockAppStatus()
            : false;
      } catch (_) {}
    }

    try {
      savedUsername = await _authService.savedUsername;
    } catch (_) {}

    if (!mounted) return;
    if (_usernameController.text.isEmpty && savedUsername != null) {
      _usernameController.text = savedUsername;
    }
    setState(() {
      _canUseBiometrics = canUseBiometrics;
      _biometricEnabled = biometricEnabled;
    });

    final String? feedbackMessage = widget.initialFeedbackMessage;
    if (feedbackMessage == null || feedbackMessage.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _showFeedbackDialog(
        title: widget.initialFeedbackTitle ?? 'Atenção',
        message: feedbackMessage,
      );
    });
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    if (_isLoading) return;

    if (!enabled) {
      await _preferencesService.saveEnableLockApp(false);
      if (!mounted) return;
      setState(() {
        _biometricEnabled = false;
      });
      return;
    }

    final bool authenticated = await _authenticateBiometrically(
      'Confirme sua biometria para ativar o acesso rápido ao Money.',
    );
    if (!authenticated) return;

    await _preferencesService.saveEnableLockApp(true);
    if (!mounted) return;
    setState(() {
      _biometricEnabled = true;
    });
  }

  Future<void> _submitLogin() async {
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      await _showFeedbackDialog(
        title: 'Atenção',
        message: username.isEmpty ? 'Informe o usuário.' : 'Informe a senha.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
    });

    try {
      if (!NetworkStatusService().isOnline) {
        final bool restored = await _authService.restoreOfflineSession(
          username: username,
          password: password,
        );
        if (restored) {
          TextInput.finishAutofillContext();
          await widget.onAuthenticated();
          return;
        }

        await _showFeedbackDialog(
          title: 'Sem internet',
          message: 'Conecte-se à internet para validar este usuário e senha.',
        );
        return;
      }

      await _authService.signIn(username: username, password: password);
      await _authService.saveCredentials();
      TextInput.finishAutofillContext();
      await widget.onAuthenticated();
    } on AuthenticationException catch (error) {
      if (error.kind == AuthenticationFailureKind.network &&
          await _authService.restoreOfflineSession(
            username: username,
            password: password,
          )) {
        TextInput.finishAutofillContext();
        await widget.onAuthenticated();
        return;
      }
      await _showFeedbackDialog(
        title: 'Login não realizado',
        message: error.message,
      );
    } catch (_) {
      await _showFeedbackDialog(
        title: 'Login não realizado',
        message: 'Não foi possível entrar. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _authenticateBiometrically(String reason) async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: reason,
        authMessages: AppAuthMessages.portugueseBrazil,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      await _showFeedbackDialog(
        title: 'Biometria indisponível',
        message: 'Não foi possível confirmar a biometria neste dispositivo.',
      );
      return false;
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

class _BiometricOption extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _BiometricOption({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgIcon(
              icon: AppIcons.biometric,
              width: 25,
              height: 25,
              color: Colors.white.withValues(alpha: 0.86),
            ),
            const SizedBox(width: 11),
            Text(
              'Ativar Biometria',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 14),
            Transform.scale(
              scale: 0.82,
              child: Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeThumbColor: const Color(0xFF76B475),
                activeTrackColor: Colors.white.withValues(alpha: 0.72),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.26),
                trackOutlineColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  static final Future<String> _version = PackageInfo.fromPlatform().then(
    (PackageInfo info) => info.version,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _version,
      builder: (context, snapshot) {
        final String? version = snapshot.data;

        return Text(
          version == null ? 'Versão' : 'Versão $version',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }
}

class _LoginField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final bool obscureText;
  final bool enabled;
  final List<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  const _LoginField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.keyboardType,
    required this.textInputAction,
    required this.enabled,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
  });

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(
        widget.obscureText ? 'login_password_field' : 'login_username_field',
      ),
      height: 50,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            key: ValueKey(
              widget.obscureText
                  ? 'login_password_icon_background'
                  : 'login_username_icon_background',
            ),
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
            ),
            child: Icon(widget.icon, color: Color(0xFF76B475), size: 22),
          ),
          Expanded(
            child: SizedBox(
              height: 50,
              child: TextField(
                controller: widget.controller,
                enabled: widget.enabled,
                keyboardType: widget.keyboardType,
                textCapitalization: widget.textCapitalization,
                textInputAction: widget.textInputAction,
                obscureText: _obscureText,
                obscuringCharacter: '•',
                textAlignVertical: TextAlignVertical.center,
                autofillHints: widget.autofillHints,
                inputFormatters: widget.inputFormatters,
                onSubmitted: widget.onSubmitted,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: Colors.white,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: false,
                  contentPadding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    8,
                    widget.obscureText ? 0 : 12,
                  ),
                  suffixIcon: widget.obscureText
                      ? IconButton(
                          onPressed: widget.enabled
                              ? () {
                                  setState(() {
                                    _obscureText = !_obscureText;
                                  });
                                }
                              : null,
                          tooltip: _obscureText
                              ? 'Mostrar senha'
                              : 'Ocultar senha',
                          icon: Icon(
                            _obscureText
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            color: Colors.white.withValues(alpha: 0.82),
                            size: 20,
                          ),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 50,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LettersOnlyTextFormatter extends TextInputFormatter {
  const _LettersOnlyTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String filtered = newValue.text.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    return newValue.copyWith(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
      composing: TextRange.empty,
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      composing: TextRange.empty,
    );
  }
}
