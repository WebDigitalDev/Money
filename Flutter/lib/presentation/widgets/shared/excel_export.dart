import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:money/money.dart';
import 'package:share_plus/share_plus.dart';

typedef AppExcelDialogProgress = void Function(double progress, String status);
typedef AppExcelDialogGenerator =
    Future<AppGeneratedExcelFile> Function(AppExcelDialogProgress onProgress);

final class AppGeneratedExcelFile {
  final Uint8List bytes;
  final String fileName;
  final String successMessage;

  const AppGeneratedExcelFile({
    required this.bytes,
    required this.fileName,
    required this.successMessage,
  });
}

final class AppExcelExportException implements Exception {
  final String message;

  const AppExcelExportException(this.message);

  @override
  String toString() => message;
}

Future<void> showAppExcelExportFlow({
  required BuildContext context,
  required String title,
  required String confirmationMessage,
  required AppExcelDialogGenerator generate,
}) async {
  final bool confirmed =
      await showAppCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text('$title?'),
          content: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(confirmationMessage),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Cancelar',
                style: TextStyle(color: dialogContext.colors.textPrimary),
              ),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Exportar'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return;

  final bool desktop = MediaQuery.sizeOf(context).width >= 1024;
  final ValueNotifier<bool> canClose = ValueNotifier<bool>(false);
  bool dialogActive = true;
  try {
    await showAppDialog<void>(
      context: context,
      title: title,
      subtitle: 'Acompanhe a geração do arquivo Excel.',
      icon: Icons.table_view_outlined,
      maxWidth: 520,
      maxHeight: desktop ? 360 : 300,
      canCloseListenable: canClose,
      builder: (_) => AppExcelExportDialog(
        generate: generate,
        desktop: desktop,
        onFinished: () {
          if (dialogActive) canClose.value = true;
        },
      ),
    );
  } finally {
    dialogActive = false;
    canClose.dispose();
  }
}

class AppDesktopExcelExportButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AppDesktopExcelExportButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(color: context.colors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'EXPORTAR',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class AppMobileExcelExportButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double dimension;

  const AppMobileExcelExportButton({
    super.key,
    required this.onPressed,
    this.dimension = 45,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(9),
          backgroundColor: context.colors.surface,
          side: BorderSide(color: context.colors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: Image.asset(
          AppImages.excel,
          width: dimension * .57,
          height: dimension * .57,
          semanticLabel: 'Exportar em Excel',
        ),
      ),
    );
  }
}

class AppExcelExportDialog extends StatefulWidget {
  final AppExcelDialogGenerator generate;
  final bool desktop;
  final VoidCallback onFinished;

  const AppExcelExportDialog({
    super.key,
    required this.generate,
    required this.desktop,
    required this.onFinished,
  });

  @override
  State<AppExcelExportDialog> createState() => _AppExcelExportDialogState();
}

class _AppExcelExportDialogState extends State<AppExcelExportDialog> {
  static const String _mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  double _progress = 0;
  String _status = 'Preparando a exportação...';
  AppGeneratedExcelFile? _file;
  String? _error;
  String? _actionMessage;
  bool _handlingFile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    try {
      final AppGeneratedExcelFile file = await widget.generate(_updateProgress);
      if (!mounted) return;
      setState(() {
        _progress = 1;
        _status = file.successMessage;
        _file = file;
      });
      widget.onFinished();
    } on AppExcelExportException catch (error) {
      _showError(error.message);
    } on Object {
      _showError('Não foi possível gerar o arquivo Excel. Tente novamente.');
    }
  }

  void _updateProgress(double value, String status) {
    if (!mounted) return;
    setState(() {
      _progress = value.clamp(0, 1);
      _status = status;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    widget.onFinished();
  }

  Future<void> _download() async {
    final AppGeneratedExcelFile? file = _file;
    if (file == null || _handlingFile) return;
    setState(() {
      _handlingFile = true;
      _actionMessage = null;
    });
    try {
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: file.fileName,
      );
      if (location == null) return;
      await _xFile(file).saveTo(location.path);
      if (mounted) {
        setState(() => _actionMessage = 'Download concluído com sucesso.');
      }
    } on Object {
      if (mounted) {
        setState(() => _actionMessage = 'Não foi possível salvar o arquivo.');
      }
    } finally {
      if (mounted) setState(() => _handlingFile = false);
    }
  }

  Future<void> _share() async {
    final AppGeneratedExcelFile? file = _file;
    if (file == null || _handlingFile) return;
    setState(() {
      _handlingFile = true;
      _actionMessage = null;
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [_xFile(file)],
          fileNameOverrides: [file.fileName],
          title: 'Exportação em Excel',
        ),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _actionMessage = 'Não foi possível compartilhar o arquivo.',
        );
      }
    } finally {
      if (mounted) setState(() => _handlingFile = false);
    }
  }

  XFile _xFile(AppGeneratedExcelFile file) => XFile.fromData(
    Uint8List.fromList(file.bytes),
    mimeType: _mimeType,
    name: file.fileName,
  );

  @override
  Widget build(BuildContext context) {
    final AppGeneratedExcelFile? file = _file;
    final int percentage = (_progress * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textPrimary),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
                side: BorderSide(color: context.colors.divider),
              ),
              child: const Text('FECHAR'),
            ),
          ] else if (file == null) ...[
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 10,
                color: context.colors.primary,
                backgroundColor: context.colors.primary.withValues(alpha: .14),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$percentage%',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ] else ...[
            Icon(
              Icons.check_circle_outline_rounded,
              color: context.colors.primary,
              size: 44,
            ),
            const SizedBox(height: 9),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              file.fileName,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
              ),
            ),
            if (_actionMessage != null) ...[
              const SizedBox(height: 7),
              Text(
                _actionMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (widget.desktop)
              OutlinedButton.icon(
                onPressed: _handlingFile ? null : _download,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                  side: BorderSide(color: context.colors.divider),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('DOWNLOAD'),
              )
            else
              FilledButton.icon(
                onPressed: _handlingFile ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('COMPARTILHAR'),
              ),
          ],
        ],
      ),
    );
  }
}
