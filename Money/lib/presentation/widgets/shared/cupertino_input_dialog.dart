import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:money/money.dart';

Future<String?> showAppCupertinoTextInputDialog({
  required BuildContext context,
  required String title,
  required String placeholder,
  String initialValue = '',
  String cancelLabel = 'Cancelar',
  String confirmLabel = 'Salvar',
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  bool obscureText = false,
}) => showAppCupertinoDialog<String>(
  context: context,
  builder: (_) => _CupertinoTextInputDialog(
    title: title,
    placeholder: placeholder,
    initialValue: initialValue,
    cancelLabel: cancelLabel,
    confirmLabel: confirmLabel,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    obscureText: obscureText,
  ),
);

class _CupertinoTextInputDialog extends StatefulWidget {
  final String title;
  final String placeholder;
  final String initialValue;
  final String cancelLabel;
  final String confirmLabel;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;

  const _CupertinoTextInputDialog({
    required this.title,
    required this.placeholder,
    required this.initialValue,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.keyboardType,
    required this.inputFormatters,
    required this.obscureText,
  });

  @override
  State<_CupertinoTextInputDialog> createState() =>
      _CupertinoTextInputDialogState();
}

class _CupertinoTextInputDialogState extends State<_CupertinoTextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: Text(widget.title),
    content: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CupertinoTextField(
        controller: _controller,
        autofocus: true,
        placeholder: widget.placeholder,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        obscureText: widget.obscureText,
        textInputAction: TextInputAction.done,
        padding: const EdgeInsets.all(12),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: Text(
          widget.cancelLabel,
          style: TextStyle(color: context.colors.textPrimary),
        ),
      ),
      CupertinoDialogAction(
        isDefaultAction: true,
        onPressed: _submit,
        child: Text(widget.confirmLabel),
      ),
    ],
  );

  void _submit() => Navigator.pop(context, _controller.text.trim());
}
