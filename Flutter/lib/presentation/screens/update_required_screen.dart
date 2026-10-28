import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money/data/services/app_update_installer.dart';
import 'package:money/money.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateRequiredScreen extends StatefulWidget {
  final RequiredAppUpdate update;

  const UpdateRequiredScreen({super.key, required this.update});

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _updating = false;
  double _progress = 0;
  String? _errorMessage;
  String? _feedbackMessage;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          minimum: EdgeInsets.only(bottom: AppDimensions.padding),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double contentWidth = constraints.maxWidth.clamp(0, 760);
              return Column(
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: contentWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const SizedBox(height: 35),
                              Image.asset(
                                AppImages.money,
                                width: (contentWidth * 0.42).clamp(190, 220),
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 24),
                              Image.asset(
                                AppImages.update,
                                width: contentWidth,
                                fit: BoxFit.fitWidth,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.update.version.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Versão ${widget.update.version} disponível',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (_errorMessage != null || _feedbackMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: Text(
                        _errorMessage ?? _feedbackMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _errorMessage != null
                              ? Theme.of(context).colorScheme.error
                              : const Color(0xFF3D7F3B),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
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
                          onPressed: _updating ? null : _startUpdate,
                          child: _buttonContent(),
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
    );
  }

  Widget _buttonContent() {
    if (!_updating) return const Text('ATUALIZAR');
    if (widget.update.target == AppUpdateTarget.android) {
      final int percentage = (_progress * 100).round().clamp(0, 100);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              value: _progress > 0 ? _progress : null,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(width: 12),
          Text(_progress > 0 ? '$percentage%' : 'PREPARANDO...'),
        ],
      );
    }
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.3),
        ),
        SizedBox(width: 12),
        Text('ABRINDO ATUALIZAÇÃO...'),
      ],
    );
  }

  Future<void> _startUpdate() async {
    setState(() {
      _updating = true;
      _progress = 0;
      _errorMessage = null;
      _feedbackMessage = null;
    });
    try {
      switch (widget.update.target) {
        case AppUpdateTarget.android:
          final AndroidInstallOutcome outcome =
              await downloadAndInstallAndroidUpdate(widget.update, (
                double progress,
              ) {
                if (mounted) setState(() => _progress = progress);
              });
          if (!mounted) return;
          setState(() {
            _updating = false;
            _feedbackMessage =
                outcome == AndroidInstallOutcome.permissionRequested
                ? 'Autorize o Money a instalar aplicativos e depois volte para continuar.'
                : 'O instalador foi aberto. Confirme a atualização para continuar.';
          });
        case AppUpdateTarget.ios:
          if (widget.update.installUrl.isEmpty) {
            throw const FormatException(
              'O instalador do iPhone ainda não foi publicado.',
            );
          }
          final bool opened = await launchUrl(
            Uri.parse(widget.update.installUrl),
            mode: LaunchMode.externalApplication,
          );
          if (!opened) {
            throw const FormatException(
              'Não foi possível abrir a instalação no iPhone.',
            );
          }
          await Future<void>.delayed(const Duration(seconds: 2));
          if (mounted) {
            setState(() {
              _updating = false;
              _feedbackMessage =
                  'Confirme a instalação solicitada pelo iOS para continuar.';
            });
          }
        case AppUpdateTarget.web:
          final Uri current = Uri.base;
          final Uri refreshed = current.replace(
            queryParameters: <String, String>{
              ...current.queryParameters,
              '_money_release': widget.update.releaseId,
              '_money_reload': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
          final bool opened = await launchUrl(
            refreshed,
            webOnlyWindowName: '_self',
          );
          if (!opened) {
            throw const FormatException('Não foi possível atualizar a página.');
          }
        case AppUpdateTarget.unsupported:
          throw UnsupportedError('Plataforma não suportada.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updating = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is FormatException && error.message.isNotEmpty) {
      return error.message.toString();
    }
    return 'Não foi possível baixar a atualização. Verifique sua internet e tente novamente.';
  }
}
