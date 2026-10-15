import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:money/money.dart';
import 'package:money/presentation/screens/notifications_screen.dart';

class SettingScreen extends StatelessWidget {
  final bool showAppBar;

  const SettingScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingCubit, SettingState>(
      builder: (context, state) {
        return Scaffold(
          appBar: showAppBar
              ? HomeAppBar(
                  title: context.tr!.settings,
                  leading: const AppSidebarMenuButton(),
                )
              : null,
          extendBodyBehindAppBar: (state is SettingInitial) ? false : true,
          body: state is SettingInitial
              ? SingleChildScrollView(
                  padding: EdgeInsets.all(AppDimensions.padding),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SettingCard(
                            title: context.tr!.app_preferences,
                            children: [
                              SettingTile(
                                title: context.tr!.theme_mode,
                                icon: AppIcons.themeMode,
                                trailing: _ThemeModeIndicator(
                                  dark: state.themeMode == ThemeMode.dark,
                                ),
                                onTap: () =>
                                    _toggleTheme(context, state.themeMode),
                              ),
                            ],
                          ),
                          if (!kIsWeb)
                            SettingCard(
                              title: context.tr!.security,
                              children: [
                                if (state.canAuthenticate)
                                  SettingTile(
                                    title: context.tr!.app_lock,
                                    icon: AppIcons.biometric,
                                    subtitle: context.tr!.app_lock_description(
                                      context.tr!.app_name,
                                    ),
                                    hasDivider: true,
                                    trailing: Transform.scale(
                                      scale: 0.75,
                                      child: Switch(
                                        value: state.appLocked,
                                        onChanged: (value) {
                                          context.read<SettingCubit>().switchAppLock(
                                            state.appLocked
                                                ? context.tr!
                                                      .unlock_app_localized_reason(
                                                        context.tr!.app_name,
                                                      )
                                                : context.tr!
                                                      .lock_app_localized_reason(
                                                        context.tr!.app_name,
                                                      ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                SettingTile(
                                  title: context.tr!.screenshot,
                                  icon: AppIcons.mobileScreenshot,
                                  subtitle:
                                      context.tr!.enable_screenshot_description,
                                  trailing: Transform.scale(
                                    scale: 0.75,
                                    child: Switch(
                                      value: state.enableScreenshot,
                                      onChanged: (_) => context
                                          .read<SettingCubit>()
                                          .switchScreenshot(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const NotificationPreferencesCard(),
                          SettingCard(
                            title: context.tr!.app_name,
                            children: [
                              SettingTile(
                                title: context.tr!.about_app(
                                  context.tr!.app_name,
                                ),
                                icon: AppIcons.about,
                                hasDivider: true,
                                trailingText: context.tr!.version(
                                  state.packageInfo.version,
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AboutScreen(
                                      version: state.packageInfo.version,
                                    ),
                                  ),
                                ),
                              ),
                              SettingTile(
                                title: context.tr!.share_app(
                                  context.tr!.app_name,
                                ),
                                icon: AppIcons.share,
                                onTap: () => _showShareMoneyDialog(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  void _toggleTheme(BuildContext context, ThemeMode currentMode) {
    final ThemeMode nextMode = currentMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    context.read<SettingCubit>().setThemeMode(nextMode);
    context.read<SharedCubit>().updateThemeMode(nextMode);
  }

  Future<void> _showShareMoneyDialog(BuildContext context) async {
    await showAppDialog<void>(
      context: context,
      title: 'Compartilhar Money',
      subtitle: 'Escolha uma plataforma para compartilhar o acesso.',
      icon: Icons.ios_share_rounded,
      maxWidth: 430,
      maxHeight: 340,
      barrierDismissible: true,
      builder: (dialogContext) => _ShareMoneyPlatforms(
        onShareAndroid: () {
          Navigator.pop(dialogContext);
          _shareAndroid(context);
        },
        onShareIos: () {
          Navigator.pop(dialogContext);
          _shareIos(context);
        },
        onShareWeb: () {
          Navigator.pop(dialogContext);
          _shareWeb(context);
        },
      ),
    );
  }

  Future<void> _shareAndroid(BuildContext context) => _share(
    context,
    message:
        'Olá, baixe o aplicativo Money para Android pelo link abaixo!\n\n'
        'https://moneyapp.site/download/android',
  );

  Future<void> _shareIos(BuildContext context) => _share(
    context,
    message:
        'Olá, instale o aplicativo Money no iPhone pelo link abaixo!\n\n'
        'https://moneyapp.site/download/ios',
  );

  Future<void> _shareWeb(BuildContext context) async {
    return _share(
      context,
      message:
          'Olá, acesse o Money na web pelo link abaixo!\n\n'
          'https://moneyapp.site',
    );
  }

  Future<void> _share(BuildContext context, {required String message}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: message, subject: 'Money'),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Não foi possível compartilhar.')),
        );
    }
  }
}

class _ShareMoneyPlatforms extends StatelessWidget {
  final VoidCallback onShareAndroid;
  final VoidCallback onShareIos;
  final VoidCallback onShareWeb;

  const _ShareMoneyPlatforms({
    required this.onShareAndroid,
    required this.onShareIos,
    required this.onShareWeb,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 218,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Escolha onde deseja instalar ou acessar o Money.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 10.5,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _SharePlatformOption(
                      icon: Icons.android_rounded,
                      label: 'ANDROID',
                      enabled: true,
                      onTap: onShareAndroid,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SharePlatformOption(
                      icon: Icons.apple,
                      label: 'IOS',
                      enabled: true,
                      onTap: onShareIos,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SharePlatformOption(
                      icon: Icons.language_rounded,
                      label: 'WEB',
                      enabled: true,
                      onTap: onShareWeb,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 15,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'moneyapp.site',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharePlatformOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _SharePlatformOption({
    required this.icon,
    required this.label,
    this.enabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = enabled
        ? context.colors.primary
        : context.colors.textSecondary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label${enabled ? '' : ', em breve'}',
      child: Material(
        color: enabled
            ? context.colors.primary.withValues(alpha: .08)
            : context.colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: enabled
                ? context.colors.primary.withValues(alpha: .38)
                : context.colors.divider,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: enabled ? .13 : .08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled ? 'Compartilhar' : 'Em breve',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? context.colors.primary
                        : context.colors.disabled,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeModeIndicator extends StatelessWidget {
  final bool dark;

  const _ThemeModeIndicator({required this.dark});

  @override
  Widget build(BuildContext context) {
    final String label = dark
        ? context.tr!.dark_theme
        : context.tr!.light_theme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          reverseDuration: const Duration(milliseconds: 100),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: Icon(
            dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            key: ValueKey<bool>(dark),
            size: 22,
            color: context.colors.primary,
          ),
        ),
      ],
    );
  }
}
