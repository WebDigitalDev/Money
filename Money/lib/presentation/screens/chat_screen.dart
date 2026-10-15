import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderBox, RenderObject, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ChatQueryCallback = Future<AppChatResponse> Function({
  required String message,
  required String conversationId,
  required String mode,
  int? clientId,
  int? regionId,
});
typedef CodexStatusCallback = Future<AppCodexConnection> Function();
typedef CodexConnectCallback = Future<AppCodexLoginChallenge> Function();
typedef CodexInterruptCallback = Future<void> Function(String conversationId);

class ChatScreen extends StatefulWidget {
  final bool showAppBar;
  final bool compact;
  final VoidCallback? onClose;
  final ChatQueryCallback? query;
  final CodexStatusCallback? codexStatus;
  final CodexConnectCallback? codexConnect;
  final CodexInterruptCallback? codexInterrupt;

  const ChatScreen({
    super.key,
    this.showAppBar = true,
    this.compact = false,
    this.onClose,
    this.query,
    this.codexStatus,
    this.codexConnect,
    this.codexInterrupt,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Reserva espaço para o botão central sem sobrepor o campo de mensagem.
  static const double _mobileComposerSpacing = 68;
  static const List<AppChatSuggestion> _initialSuggestions = [];

  final ChatService _service = ChatService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _messageListKey = GlobalKey(debugLabel: 'chat_message_list');
  final GlobalKey _lastMessageKey = GlobalKey(debugLabel: 'chat_last_message');
  final List<_ConversationMessage> _messages = [
    const _ConversationMessage.assistant(
      AppChatResponse(
        message: 'Olá! Digite o número de um contrato ou faça uma pergunta financeira.',
        mode: 'READY',
        suggestions: _initialSuggestions,
        clients: [],
        summary: null,
        semanticSearch: false,
      ),
    ),
  ];

  String _mode = 'READY';
  late final String _conversationId;
  AppChatResponse? _activeResponse;
  Timer? _connectionPoll;
  bool _checkingCodex = true;
  bool _codexAvailable = true;
  bool _codexConnected = false;
  bool _connectingCodex = false;
  bool _startingCodexLogin = false;
  bool _statusRequestInFlight = false;
  String? _codexError;
  AppCodexUsage? _codexUsage;
  List<AppChatModelOption> _chatModels = const [];
  String? _selectedModelId;
  String? _selectedServiceTierId;
  final List<AppChatUpload> _pendingAttachments = [];
  int _pollAttempts = 0;
  int _requestGeneration = 0;
  bool _loading = false;
  bool _generatingPdf = false;
  double _keyboardInset = 0;
  bool _followKeyboardToEnd = false;
  bool _endPinScheduled = false;
  bool _resetKeyboardFollowAfterPin = false;

  @override
  void initState() {
    super.initState();
    _conversationId =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    if (widget.query != null && widget.codexStatus == null) {
      _checkingCodex = false;
      _codexConnected = true;
    } else {
      unawaited(_loadCodexStatus());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _connectionPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool desktop =
        !widget.compact && MediaQuery.sizeOf(context).width >= 1024;
    final bool usesMobileNavigation = widget.showAppBar && !widget.compact;
    final double mobileComposerBottomClearance =
        MediaQuery.viewPaddingOf(context).bottom +
        kBottomNavigationBarHeight +
        _mobileComposerSpacing;
    final double composerBottom = usesMobileNavigation
        ? mobileComposerBottomClearance
        : widget.compact
        ? 0
        : 12;
    final Widget content = Column(
      children: [
        if (!widget.showAppBar)
          _DesktopChatHeader(compact: widget.compact, onClose: widget.onClose),
        if (_checkingCodex)
          const Expanded(child: _ChatGptLoadingState())
        else if (!_codexConnected)
          Expanded(
            child: _CodexConnectPanel(
              connecting: _connectingCodex,
              starting: _startingCodexLogin,
              available: _codexAvailable,
              error: _codexError,
              onConnect: _connectCodex,
              onRetry: _loadCodexStatus,
            ),
          )
        else ...[
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: NotificationListener<UserScrollNotification>(
                  onNotification: _handleUserScroll,
                  child: ListView.builder(
                    key: _messageListKey,
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      desktop ? 24 : 12,
                      widget.compact ? 12 : 18,
                      desktop ? 24 : 12,
                      widget.compact ? 10 : 16,
                    ),
                    itemCount:
                        _messages.length +
                        (_loading && !_generatingPdf ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return KeyedSubtree(
                          key: _lastMessageKey,
                          child: const _TypingBubble(),
                        );
                      }
                      final _ConversationMessage item = _messages[index];
                      return KeyedSubtree(
                        key:
                            index == _messages.length - 1 &&
                                (!_loading || _generatingPdf)
                            ? _lastMessageKey
                            : null,
                        child: _MessageBubble(
                          message: item,
                          onSuggestion: _sendSuggestion,
                          onLoan: _confirmOpenLoan,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          _ChatComposerDock(
            bottomWhenClosed: composerBottom,
            onKeyboardInsetChanged: _handleKeyboardInsetChanged,
            controller: _controller,
            focusNode: _focusNode,
            canSend: !_loading,
            isResponding: _loading && !_generatingPdf,
            usage: _codexUsage,
            models: _chatModels,
            selectedModelId: _selectedModelId,
            selectedServiceTierId: _selectedServiceTierId,
            attachments: List.unmodifiable(_pendingAttachments),
            onSend: _sendTypedMessage,
            onStop: _stopResponse,
            onAttach: _pickAttachments,
            onRemoveAttachment: _removeAttachment,
            onConfigure: _openModelSelector,
          ),
        ],
      ],
    );

    return Scaffold(
      // O dock trata o inset do teclado. Evita que o Scaffold e o compositor
      // redimensionem o mesmo conteúdo em momentos diferentes da animação.
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: context.tr!.ai,
              leading: const AppSidebarMenuButton(),
            )
          : null,
      body: content,
    );
  }

  Future<void> _loadCodexStatus() async {
    if (_statusRequestInFlight) return;
    _statusRequestInFlight = true;
    try {
      final AppCodexConnection connection = widget.codexStatus == null
          ? await _service.codexStatus()
          : await widget.codexStatus!();
      if (!mounted) return;
      setState(() {
        _checkingCodex = false;
        _codexAvailable = connection.enabled && connection.available;
        _codexConnected = connection.connected;
        _connectingCodex = !connection.connected && connection.connecting;
        if (connection.connected) _startingCodexLogin = false;
        _codexUsage = connection.connected ? connection.usage : null;
        _chatModels = connection.connected ? connection.models : const [];
        if (_chatModels.isNotEmpty) {
          final bool currentModelExists = _chatModels.any(
            (item) => item.id == _selectedModelId,
          );
          if (!currentModelExists) {
            AppChatModelOption? defaultOption;
            for (final AppChatModelOption item in _chatModels) {
              if (item.defaultModel) {
                defaultOption = item;
                break;
              }
            }
            _selectedModelId =
                connection.defaultModel ??
                defaultOption?.id ??
                _chatModels.first.id;
          }
          final AppChatModelOption selected = _chatModels.firstWhere(
            (item) => item.id == _selectedModelId,
            orElse: () => _chatModels.first,
          );
          if (selected.tier(_selectedServiceTierId) == null) {
            _selectedServiceTierId =
                connection.defaultServiceTier ?? selected.preferredTier;
          }
        }
        _codexError = connection.error;
      });
      if (connection.connected) {
        _connectionPoll?.cancel();
        _connectionPoll = null;
      } else if (connection.connecting && _connectionPoll == null) {
        _startConnectionPolling();
      }
    } on ChatServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingCodex = false;
        _codexAvailable = false;
        _codexConnected = false;
        _connectingCodex = false;
        _startingCodexLogin = false;
        _codexUsage = null;
        _chatModels = const [];
        _selectedModelId = null;
        _selectedServiceTierId = null;
        _codexError = error.message;
      });
    } finally {
      _statusRequestInFlight = false;
    }
  }

  Future<void> _connectCodex() async {
    if (_startingCodexLogin) return;
    setState(() {
      _connectingCodex = true;
      _startingCodexLogin = true;
      _codexError = null;
    });
    try {
      final AppCodexLoginChallenge challenge = widget.codexConnect == null
          ? await _service.connectCodex()
          : await widget.codexConnect!();
      if (!mounted) return;
      setState(() => _startingCodexLogin = false);
      _startConnectionPolling();
      final _CodexLoginAction? action =
          await showAppCupertinoDialog<_CodexLoginAction>(
            context: context,
            builder: (dialogContext) => CupertinoAlertDialog(
              title: const Text('Conectar ao ChatGPT'),
              content: Column(
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Use o código abaixo para autorizar sua conta individual.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    challenge.userCode,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () =>
                      Navigator.pop(dialogContext, _CodexLoginAction.cancel),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: dialogContext.colors.textPrimary),
                  ),
                ),
                CupertinoDialogAction(
                  onPressed: () =>
                      Navigator.pop(dialogContext, _CodexLoginAction.copy),
                  child: const Text('Copiar código'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () =>
                      Navigator.pop(dialogContext, _CodexLoginAction.open),
                  child: const Text('Abrir ChatGPT'),
                ),
              ],
            ),
          );
      if (!mounted) return;
      if (action == _CodexLoginAction.cancel || action == null) {
        _connectionPoll?.cancel();
        _connectionPoll = null;
        setState(() {
          _connectingCodex = false;
          _startingCodexLogin = false;
        });
        return;
      }
      await Clipboard.setData(ClipboardData(text: challenge.clipboardCode));
      if (action == _CodexLoginAction.open) {
        final bool opened = await launchUrl(
          challenge.prefilledVerificationUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          throw const ChatServiceException(
            'Não foi possível abrir o ChatGPT. O código foi copiado; abra o endereço no navegador.',
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == _CodexLoginAction.open
                ? 'Código preenchido. Conclua a autorização no ChatGPT.'
                : 'Código copiado no formato correto. Abra o ChatGPT para concluir.',
          ),
        ),
      );
    } on ChatServiceException catch (error) {
      if (!mounted) return;
      _connectionPoll?.cancel();
      _connectionPoll = null;
      setState(() {
        _connectingCodex = false;
        _startingCodexLogin = false;
        _codexError = error.message;
      });
    } on Object {
      if (!mounted) return;
      _connectionPoll?.cancel();
      _connectionPoll = null;
      setState(() {
        _connectingCodex = false;
        _startingCodexLogin = false;
        _codexError = 'Não foi possível abrir a autenticação do ChatGPT.';
      });
    }
  }

  void _startConnectionPolling() {
    _connectionPoll?.cancel();
    _pollAttempts = 0;
    _connectionPoll = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || ++_pollAttempts > 150) {
        timer.cancel();
        _connectionPoll = null;
        if (mounted && !_codexConnected) {
          setState(() {
            _connectingCodex = false;
            _codexError = 'A autorização expirou. Toque em conectar para tentar novamente.';
          });
        }
        return;
      }
      unawaited(_loadCodexStatus());
    });
  }

  void _sendTypedMessage() {
    final String text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    final List<AppChatUpload> attachments = List.of(_pendingAttachments);
    _controller.clear();
    setState(_pendingAttachments.clear);
    _send(text, attachments: attachments);
  }

  void _sendSuggestion(AppChatSuggestion suggestion) {
    if (_loading) return;
    if (suggestion.action == 'EXPORT_EXCEL') {
      _exportLoans(_activeResponse);
      return;
    }
    if (suggestion.action == 'EXPORT_PDF') {
      _exportSummaryPdf(_activeResponse);
      return;
    }
    _send(
      suggestion.message,
      displayText: suggestion.label,
      clientId: suggestion.clientId,
      regionId: suggestion.regionId,
    );
  }

  Future<void> _send(
    String message, {
    String? displayText,
    int? clientId,
    int? regionId,
    List<AppChatUpload> attachments = const [],
  }) async {
    final int requestGeneration = ++_requestGeneration;
    final bool closeKeyboardOnResponse = _focusNode.hasFocus;
    setState(() {
      _messages.add(
        _ConversationMessage.user(
          displayText ?? message,
          attachmentNames: attachments.map((item) => item.fileName).toList(),
        ),
      );
      _loading = true;
    });
    if (closeKeyboardOnResponse) _followKeyboardToEnd = true;
    _scrollToEnd(duration: const Duration(milliseconds: 140));
    try {
      final AppChatResponse response = widget.query == null
          ? await _service.query(
              message: message,
              conversationId: _conversationId,
              mode: _mode,
              clientId: clientId,
              regionId: regionId,
              model: _selectedModelId,
              serviceTier: _selectedServiceTierId,
              attachments: attachments,
            )
          : await widget.query!(
              message: message,
              conversationId: _conversationId,
              mode: _mode,
              clientId: clientId,
              regionId: regionId,
            );
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _mode = response.mode;
        _messages.add(_ConversationMessage.assistant(response));
        _activeResponse = response;
        _loading = false;
      });
    } on ChatServiceException catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _messages.add(
          _ConversationMessage.assistant(
            AppChatResponse(
              message: error.message,
              mode: _mode,
              suggestions: _initialSuggestions,
              clients: const [],
              summary: null,
              semanticSearch: false,
            ),
            error: true,
          ),
        );
        _activeResponse = null;
        _loading = false;
        if (error.statusCode == 401 || error.statusCode == 409) {
          _codexConnected = false;
          _codexError = error.message;
        }
      });
    }
    if (requestGeneration != _requestGeneration) return;
    if (closeKeyboardOnResponse && _focusNode.hasFocus) {
      _followKeyboardToEnd = true;
      _focusNode.unfocus();
    }
    _scrollToEnd();
    if (widget.query == null || widget.codexStatus != null) {
      unawaited(_loadCodexStatus());
    }
  }

  Future<void> _pickAttachments() async {
    if (_loading || _pendingAttachments.length >= 3) return;
    try {
      final List<XFile> files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Imagens e documentos',
            extensions: [
              'png',
              'jpg',
              'jpeg',
              'webp',
              'pdf',
              'txt',
              'md',
              'csv',
              'json',
              'xml',
              'log',
            ],
          ),
        ],
      );
      if (files.isEmpty || !mounted) return;
      final int available = 3 - _pendingAttachments.length;
      final List<AppChatUpload> additions = [];
      for (final XFile file in files.take(available)) {
        final int size = await file.length();
        if (size > 8 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${file.name} ultrapassa o limite de 8 MB.'),
              ),
            );
          }
          continue;
        }
        additions.add(
          AppChatUpload(fileName: file.name, bytes: await file.readAsBytes()),
        );
      }
      if (!mounted || additions.isEmpty) return;
      setState(() => _pendingAttachments.addAll(additions));
      if (files.length > available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Envie no máximo três arquivos por mensagem.'),
          ),
        );
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível selecionar o arquivo.')),
      );
    }
  }

  void _removeAttachment(AppChatUpload attachment) {
    if (_loading) return;
    setState(() => _pendingAttachments.remove(attachment));
  }

  Future<void> _openModelSelector() async {
    if (_chatModels.isEmpty || _loading) return;
    String modelId = _selectedModelId ?? _chatModels.first.id;
    AppChatModelOption model = _chatModels.firstWhere(
      (item) => item.id == modelId,
      orElse: () => _chatModels.first,
    );
    String? tierId =
        model.tier(_selectedServiceTierId)?.id ?? model.preferredTier;
    final _ChatModelSelection? selected = await showDialog<_ChatModelSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          model = _chatModels.firstWhere(
            (item) => item.id == modelId,
            orElse: () => _chatModels.first,
          );
          return AlertDialog(
            title: const Text('Modelo do ChatGPT'),
            content: SizedBox(
              width: 390,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: modelId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Modelo'),
                    items: [
                      for (final AppChatModelOption item in _chatModels)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        modelId = value;
                        model = _chatModels.firstWhere(
                          (item) => item.id == value,
                        );
                        tierId = model.preferredTier;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey('$modelId-$tierId'),
                    initialValue: tierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Velocidade'),
                    items: [
                      for (final AppChatServiceTier tier in model.serviceTiers)
                        DropdownMenuItem(
                          value: tier.id,
                          child: Text(_serviceTierLabel(tier)),
                        ),
                    ],
                    onChanged: model.serviceTiers.isEmpty
                        ? null
                        : (value) => setDialogState(() => tierId = value),
                  ),
                  if (model.tier(tierId)?.description.trim().isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 8),
                    Text(
                      model.tier(tierId)!.description,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _ChatModelSelection(modelId: modelId, serviceTierId: tierId),
                ),
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedModelId = selected.modelId;
      _selectedServiceTierId = selected.serviceTierId;
    });
  }

  Future<void> _stopResponse() async {
    if (!_loading || _generatingPdf) return;
    ++_requestGeneration;
    setState(() => _loading = false);
    try {
      if (widget.codexInterrupt == null) {
        await _service.interruptCodex(_conversationId);
      } else {
        await widget.codexInterrupt!(_conversationId);
      }
    } on ChatServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _exportLoans(AppChatResponse? response) async {
    if (response == null || response.loans.isEmpty || _loading) return;
    setState(() {
      _messages.add(const _ConversationMessage.user('Exportar'));
      _loading = true;
    });
    _scrollToEnd();
    try {
      final AppTableExcelFile file = await ChatLoanExcelExportService().create(
        response.loans,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ConversationMessage.excel(file));
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ConversationMessage.assistant(
            AppChatResponse(
              message:
                  'Não foi possível gerar o arquivo Excel. Tente novamente.',
              mode: _mode,
              suggestions: response.suggestions,
              clients: const [],
              summary: null,
              semanticSearch: false,
            ),
            error: true,
          ),
        );
        _loading = false;
      });
    }
    _scrollToEnd();
  }

  Future<void> _exportSummaryPdf(AppChatResponse? response) async {
    final AppChatSummaryContext? summary = response?.summaryContext;
    if (summary == null || _loading) return;
    setState(() {
      _messages.add(const _ConversationMessage.user('Exportar PDF'));
      _messages.add(const _ConversationMessage.pdfLoading());
      _loading = true;
      _generatingPdf = true;
    });
    _scrollToEnd();
    try {
      final AppChatPdfFile file = await _service.exportSummaryPdf(summary);
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((item) => item.pdfLoading);
        _messages.add(_ConversationMessage.pdf(file));
        _loading = false;
        _generatingPdf = false;
      });
    } on ChatServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((item) => item.pdfLoading);
        _messages.add(
          _ConversationMessage.assistant(
            AppChatResponse(
              message: error.message,
              mode: _mode,
              suggestions: response?.suggestions ?? _initialSuggestions,
              clients: const [],
              summary: null,
              semanticSearch: false,
            ),
            error: true,
          ),
        );
        _loading = false;
        _generatingPdf = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((item) => item.pdfLoading);
        _messages.add(
          _ConversationMessage.assistant(
            AppChatResponse(
              message: 'Não foi possível gerar o PDF. Tente novamente.',
              mode: _mode,
              suggestions: response?.suggestions ?? _initialSuggestions,
              clients: const [],
              summary: null,
              semanticSearch: false,
            ),
            error: true,
          ),
        );
        _loading = false;
        _generatingPdf = false;
      });
    }
    _scrollToEnd();
  }

  Future<void> _confirmOpenLoan(AppChatLoan loan) async {
    final bool? confirmed = await showAppCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Abrir empréstimo?'),
        content: Text(
          'Deseja abrir o contrato #${loan.loanId} de ${loan.clientName}?',
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
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await openLoanDetailScreen(context: context, loanId: loan.loanId);
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    if (_keyboardInset <= .5) return false;
    if (notification.direction == ScrollDirection.forward) {
      _followKeyboardToEnd = false;
    } else if (notification.direction == ScrollDirection.idle && _isNearEnd()) {
      _followKeyboardToEnd = true;
    }
    return false;
  }

  void _handleKeyboardInsetChanged(double nextInset) {
    if (!mounted) return;
    final bool wasClosed = _keyboardInset <= .5;
    final bool isClosed = nextInset <= .5;
    if (wasClosed && !isClosed) {
      _followKeyboardToEnd = _isNearEnd();
    }
    _keyboardInset = nextInset;
    if (_followKeyboardToEnd) {
      _scheduleEndPin(resetAfterPin: isClosed);
    } else if (isClosed) {
      _followKeyboardToEnd = false;
    }
  }

  bool _isNearEnd({double tolerance = 72}) {
    if (!_scrollController.hasClients) return true;
    final ScrollPosition position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= tolerance;
  }

  void _scheduleEndPin({bool resetAfterPin = false}) {
    _resetKeyboardFollowAfterPin |= resetAfterPin;
    if (_endPinScheduled) return;
    _endPinScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _endPinScheduled = false;
      if (!mounted) return;
      if (_followKeyboardToEnd && _scrollController.hasClients) {
        _pinScrollToEnd();
      }
      if (_resetKeyboardFollowAfterPin) {
        _resetKeyboardFollowAfterPin = false;
        _followKeyboardToEnd = false;
      }
    });
  }

  void _pinScrollToEnd() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    final double target = position.maxScrollExtent;
    if ((target - position.pixels).abs() > .5) {
      // Durante a animação nativa do teclado, o viewport já está sendo
      // recalculado pelo Flutter. Usar diretamente as métricas de rolagem
      // evita medições globais de RenderBox e uma segunda passagem de layout
      // a cada frame, mantendo a última mensagem acompanhando o compositor.
      _scrollController.jumpTo(target);
    }
  }

  void _scrollToEnd({Duration duration = const Duration(milliseconds: 180)}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final BuildContext? lastMessageContext = _lastMessageKey.currentContext;
      if (lastMessageContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            lastMessageContext,
            alignment: 1,
            duration: duration,
            curve: Curves.easeOutCubic,
          ).whenComplete(() {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _ensureLastMessageVisible();
            });
          }),
        );
        return;
      }
      unawaited(
        _scrollController
            .animateTo(
              _scrollController.position.maxScrollExtent,
              duration: duration,
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ensureLastMessageVisible();
              });
            }),
      );
    });
  }

  void _ensureLastMessageVisible() {
    final BuildContext? lastMessageContext = _lastMessageKey.currentContext;
    final BuildContext? listContext = _messageListKey.currentContext;
    final RenderObject? lastRenderObject = lastMessageContext
        ?.findRenderObject();
    final RenderObject? listRenderObject = listContext?.findRenderObject();
    if (lastRenderObject is RenderBox && listRenderObject is RenderBox) {
      final double lastBottom = lastRenderObject
          .localToGlobal(Offset(0, lastRenderObject.size.height))
          .dy;
      final double listBottom = listRenderObject
          .localToGlobal(Offset(0, listRenderObject.size.height))
          .dy;
      final double correction = lastBottom - (listBottom - 8);
      final double target = math.max(
        0,
        _scrollController.position.pixels + correction,
      );
      if ((target - _scrollController.position.pixels).abs() > .5) {
        _scrollController.jumpTo(target);
      }
      return;
    }
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }
}

enum _CodexLoginAction { cancel, copy, open }

final class _ChatModelSelection {
  final String modelId;
  final String? serviceTierId;

  const _ChatModelSelection({
    required this.modelId,
    required this.serviceTierId,
  });
}

String _serviceTierLabel(AppChatServiceTier tier) {
  return switch (tier.id.toLowerCase()) {
    'fast' => 'Rápida',
    'default' || 'standard' => 'Padrão',
    _ => tier.name,
  };
}

class _ChatGptLoadingState extends StatelessWidget {
  const _ChatGptLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgIcon(
            icon: AppIcons.gpt,
            width: 48,
            height: 48,
            color: context.colors.primary,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 128,
            child: LinearProgressIndicator(
              minHeight: 3,
              borderRadius: BorderRadius.circular(3),
              color: context.colors.primary,
              backgroundColor: context.colors.primary.withValues(alpha: .14),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Conectando ao ChatGPT...',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodexConnectPanel extends StatelessWidget {
  final bool connecting;
  final bool starting;
  final bool available;
  final String? error;
  final VoidCallback? onConnect;
  final VoidCallback onRetry;

  const _CodexConnectPanel({
    required this.connecting,
    required this.starting,
    required this.available,
    required this.error,
    required this.onConnect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action = starting
        ? null
        : available
        ? onConnect
        : onRetry;
    final String label = starting
        ? 'PREPARANDO CONEXÃO'
        : connecting
        ? 'EXIBIR CÓDIGO DE CONEXÃO'
        : available
        ? 'CONECTAR CHATGPT'
        : 'TENTAR NOVAMENTE';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 112),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 410),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: .10),
                  shape: BoxShape.circle,
                ),
                child: SvgIcon(
                  icon: AppIcons.gpt,
                  width: 44,
                  height: 44,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Conecte sua conta ChatGPT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use o ChatGPT para conversar sobre os dados financeiros no Money.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              if (error != null && error!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.error,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: action == null
                        ? null
                        : CustomFloatingActionButton.gradient,
                    color: action == null ? context.colors.disabled : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: action == null
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x334B7D60),
                              blurRadius: 10,
                              offset: Offset(1, 4),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: action,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (starting)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const SvgIcon(
                                icon: AppIcons.gpt,
                                width: 20,
                                height: 20,
                                color: Colors.white,
                              ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationMessage {
  final bool fromUser;
  final String text;
  final AppChatResponse? response;
  final bool error;
  final AppTableExcelFile? excel;
  final AppChatPdfFile? pdf;
  final bool pdfLoading;
  final List<String> attachmentNames;

  const _ConversationMessage.user(this.text, {this.attachmentNames = const []})
    : fromUser = true,
      response = null,
      error = false,
      excel = null,
      pdf = null,
      pdfLoading = false;

  const _ConversationMessage.assistant(this.response, {this.error = false})
    : fromUser = false,
      text = '',
      excel = null,
      pdf = null,
      pdfLoading = false,
      attachmentNames = const [];

  const _ConversationMessage.excel(this.excel)
    : fromUser = false,
      text = '',
      response = null,
      error = false,
      pdf = null,
      pdfLoading = false,
      attachmentNames = const [];

  const _ConversationMessage.pdf(this.pdf)
    : fromUser = false,
      text = '',
      response = null,
      error = false,
      excel = null,
      pdfLoading = false,
      attachmentNames = const [];

  const _ConversationMessage.pdfLoading()
    : fromUser = false,
      text = '',
      response = null,
      error = false,
      excel = null,
      pdf = null,
      pdfLoading = true,
      attachmentNames = const [];
}

class _DesktopChatHeader extends StatelessWidget {
  final bool compact;
  final VoidCallback? onClose;

  const _DesktopChatHeader({required this.compact, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: compact
          ? const EdgeInsets.fromLTRB(14, 12, 8, 11)
          : const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(bottom: BorderSide(color: context.colors.divider)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Row(
            children: [
              _AssistantAvatar(size: compact ? 38 : 42),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat Financeiro',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: compact ? 15 : 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      compact
                          ? 'Assistente Money'
                          : 'Contratos, histórico e análises com dados atuais',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: compact ? 11 : 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  key: const ValueKey('desktop_chat_close_button'),
                  tooltip: 'Fechar assistente financeira',
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 21),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ConversationMessage message;
  final ValueChanged<AppChatSuggestion> onSuggestion;
  final ValueChanged<AppChatLoan> onLoan;

  const _MessageBubble({
    required this.message,
    required this.onSuggestion,
    required this.onLoan,
  });

  @override
  Widget build(BuildContext context) {
    if (message.fromUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.only(bottom: 12, left: 48, right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFA8D6A0), Color(0xFF76B475), Color(0xFF4B7D60)],
              stops: [0, 0.52, 1],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(11),
              bottomRight: Radius.circular(5),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4B7D60).withValues(alpha: 0.16),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              if (message.attachmentNames.isNotEmpty) ...[
                const SizedBox(height: 7),
                for (final String name in message.attachmentNames)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.attach_file_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    if (message.pdfLoading) return const _PdfGeneratingBubble();
    if (message.excel != null) {
      return _FileAttachmentBubble.excel(file: message.excel!);
    }
    if (message.pdf != null) {
      return _FileAttachmentBubble.pdf(file: message.pdf!);
    }

    final AppChatResponse response = message.response!;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.only(right: 28, bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AssistantAvatar(size: 34),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 680),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: message.error
                          ? context.colors.error.withValues(alpha: 0.08)
                          : context.colors.surface,
                      border: Border.all(
                        color: message.error
                            ? context.colors.error.withValues(alpha: 0.25)
                            : context.colors.divider,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(5),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AssistantMessageText(
                          text: response.message,
                          style: TextStyle(
                            color: message.error
                                ? context.colors.error
                                : context.colors.textPrimary,
                            fontSize: 14,
                            height: 1.42,
                          ),
                        ),
                        if (response.mode == 'CONTRACT_HISTORY' &&
                            response.contract != null &&
                            response.contract!.history.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Divider(height: 1, color: context.colors.divider),
                          const SizedBox(height: 9),
                          _InlineContractHistory(contract: response.contract!),
                        ],
                      ],
                    ),
                  ),
                  if (response.summary != null) ...[
                    const SizedBox(height: 8),
                    _SummaryPanel(summary: response.summary!),
                  ],
                  if (response.loanStatus != null) ...[
                    const SizedBox(height: 8),
                    _LoanStatusDonutCard(status: response.loanStatus!),
                  ],
                  if (response.clientStatus != null) ...[
                    const SizedBox(height: 8),
                    _ClientStatusBarCard(status: response.clientStatus!),
                  ],
                  if (response.financialGoals.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _CompactFinancialGoals(goals: response.financialGoals),
                  ],
                  if (response.clients.length == 1) ...[
                    const SizedBox(height: 8),
                    _ChatClientDetailCard(client: response.clients.single),
                  ],
                  if (response.contract != null &&
                      response.mode != 'CONTRACT_HISTORY') ...[
                    const SizedBox(height: 8),
                    _ChatContractCard(
                      contract: response.contract!,
                      onOpen: () => onLoan(response.contract!.asLoan),
                    ),
                  ],
                  if (response.loans.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    if (response.mode == 'CLIENT_CONTEXT') ...[
                      _ClientActiveLoansHeader(loans: response.loans),
                      const SizedBox(height: 7),
                    ],
                    _ChatLoanResults(loans: response.loans, onLoan: onLoan),
                    if (response.mode != 'CLIENT_CONTEXT') ...[
                      const SizedBox(height: 8),
                      _LoanTotalsCard(loans: response.loans),
                    ],
                  ],
                  if (response.clients.length > 1) ...[
                    const SizedBox(height: 8),
                    _ClientResults(
                      clients: response.clients,
                      suggestions: response.suggestions,
                      onSuggestion: onSuggestion,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessageText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _AssistantMessageText({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: style,
        children: _inlineMarkdownSpans(text, style, context.colors.background),
      ),
    );
  }

  List<InlineSpan> _inlineMarkdownSpans(
    String source,
    TextStyle baseStyle,
    Color codeBackground,
  ) {
    final List<InlineSpan> spans = [];
    int cursor = 0;

    while (cursor < source.length) {
      final _MarkdownToken? token = _nextMarkdownToken(source, cursor);
      if (token == null) {
        spans.add(TextSpan(text: source.substring(cursor)));
        break;
      }
      if (token.start > cursor) {
        spans.add(TextSpan(text: source.substring(cursor, token.start)));
      }
      spans.add(
        TextSpan(
          text: source.substring(token.contentStart, token.contentEnd),
          style: token.code
              ? baseStyle.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: codeBackground,
                )
              : baseStyle.copyWith(fontWeight: FontWeight.w700),
        ),
      );
      cursor = token.end;
    }

    return spans.isEmpty ? [const TextSpan(text: '')] : spans;
  }

  _MarkdownToken? _nextMarkdownToken(String source, int from) {
    _MarkdownToken? next;
    for (final String delimiter in const ['**', '__', '`']) {
      final int start = source.indexOf(delimiter, from);
      if (start < 0) continue;
      final int contentStart = start + delimiter.length;
      final int contentEnd = source.indexOf(delimiter, contentStart);
      if (contentEnd <= contentStart) continue;
      final _MarkdownToken candidate = _MarkdownToken(
        start: start,
        contentStart: contentStart,
        contentEnd: contentEnd,
        end: contentEnd + delimiter.length,
        code: delimiter == '`',
      );
      if (next == null || candidate.start < next.start) next = candidate;
    }
    return next;
  }
}

class _MarkdownToken {
  final int start;
  final int contentStart;
  final int contentEnd;
  final int end;
  final bool code;

  const _MarkdownToken({
    required this.start,
    required this.contentStart,
    required this.contentEnd,
    required this.end,
    required this.code,
  });
}

class _PdfGeneratingBubble extends StatelessWidget {
  const _PdfGeneratingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.only(right: 28, bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AssistantAvatar(size: 34),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 430),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border.all(color: context.colors.divider),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: context.colors.primary,
                        backgroundColor: context.colors.primary.withValues(
                          alpha: 0.14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gerando resumo em PDF',
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Organizando valores, gráficos e dados da região…',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileAttachmentBubble extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String title;
  final String shareTitle;
  final IconData icon;

  _FileAttachmentBubble.excel({required AppTableExcelFile file})
    : bytes = file.bytes,
      fileName = file.fileName,
      mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      title = 'Lista pronta para exportar',
      shareTitle = 'Lista de empréstimos em Excel',
      icon = Icons.table_view_rounded;

  _FileAttachmentBubble.pdf({required AppChatPdfFile file})
    : bytes = file.bytes,
      fileName = file.fileName,
      mimeType = 'application/pdf',
      title = 'Resumo financeiro em PDF',
      shareTitle = 'Resumo financeiro da região',
      icon = Icons.picture_as_pdf_outlined;

  @override
  State<_FileAttachmentBubble> createState() => _FileAttachmentBubbleState();
}

class _FileAttachmentBubbleState extends State<_FileAttachmentBubble> {
  bool _handling = false;
  String? _message;

  XFile get _file => XFile.fromData(
    Uint8List.fromList(widget.bytes),
    name: widget.fileName,
    mimeType: widget.mimeType,
  );

  Future<void> _download() async {
    if (_handling) return;
    setState(() {
      _handling = true;
      _message = null;
    });
    try {
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: widget.fileName,
      );
      if (location == null) return;
      await _file.saveTo(location.path);
      if (mounted) setState(() => _message = 'Download concluído.');
    } on Object {
      if (mounted) setState(() => _message = 'Não foi possível salvar.');
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  Future<void> _share() async {
    if (_handling) return;
    setState(() {
      _handling = true;
      _message = null;
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [_file],
          fileNameOverrides: [widget.fileName],
          title: widget.shareTitle,
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _message = 'Não foi possível compartilhar.');
      }
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool desktop = MediaQuery.sizeOf(context).width >= 1024;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.only(right: 28, bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AssistantAvatar(size: 34),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border.all(color: context.colors.divider),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: context.colors.primary.withValues(
                              alpha: .12,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            widget.icon,
                            color: context.colors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                widget.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: FilledButton.icon(
                        onPressed: _handling
                            ? null
                            : desktop
                            ? _download
                            : _share,
                        icon: _handling
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                desktop
                                    ? Icons.download_rounded
                                    : Icons.share_rounded,
                                size: 17,
                              ),
                        label: Text(desktop ? 'DOWNLOAD' : 'COMPARTILHAR'),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.colors.primary,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatClientDetailCard extends StatelessWidget {
  final AppChatClient client;

  const _ChatClientDetailCard({required this.client});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final bool overdue = client.overdue > 0;
    final Color accent = overdue
        ? context.colors.error
        : const Color(0xFF4B7D60);
    return Container(
      key: ValueKey('chat_client_card_${client.id}'),
      constraints: const BoxConstraints(maxWidth: 680),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: accent.withValues(alpha: .12),
                  child: Text(
                    _initials(client.name),
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ClientIdentityFact(
                            icon: Icons.location_on_outlined,
                            text: client.regionName,
                          ),
                          if (client.document != null)
                            _ClientIdentityFact(
                              icon: Icons.badge_outlined,
                              text: client.document!,
                            ),
                          if (client.phone != null)
                            _ClientIdentityFact(
                              icon: Icons.phone_outlined,
                              text: client.phone!,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    overdue ? 'COM ATRASO' : 'REGULAR',
                    style: TextStyle(
                      color: accent,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final int columns = constraints.maxWidth < 430 ? 2 : 4;
                    final double width =
                        (constraints.maxWidth - ((columns - 1) * 7)) / columns;
                    final List<Widget> metrics = [
                      _ContractMetric(
                        label: 'Emprestado',
                        value: currency.format(client.loaned),
                        icon: Icons.south_west_rounded,
                        color: const Color(0xFF4D7EC7),
                      ),
                      _ContractMetric(
                        label: 'Recebido',
                        value: currency.format(client.received),
                        icon: Icons.savings_outlined,
                        color: const Color(0xFF4B8B66),
                      ),
                      _ContractMetric(
                        label: 'A receber',
                        value: currency.format(client.receivable),
                        icon: Icons.schedule_rounded,
                        color: const Color(0xFFD18A21),
                      ),
                      _ContractMetric(
                        label: 'Em atraso',
                        value: currency.format(client.overdue),
                        icon: Icons.warning_amber_rounded,
                        color: overdue
                            ? context.colors.error
                            : const Color(0xFF76847A),
                      ),
                    ];
                    return Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: metrics
                          .map((item) => SizedBox(width: width, child: item))
                          .toList(growable: false),
                    );
                  },
                ),
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.background.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ClientCompactTotal(
                          icon: Icons.receipt_long_outlined,
                          label: 'CONTRATOS ATIVOS',
                          value: '${client.openLoans}',
                          color: context.colors.primary,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: context.colors.divider,
                      ),
                      Expanded(
                        child: _ClientCompactTotal(
                          icon: Icons.today_outlined,
                          label: 'VENCE HOJE',
                          value: currency.format(client.dueToday),
                          color: client.dueToday > 0
                              ? const Color(0xFFD18A21)
                              : context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientIdentityFact extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ClientIdentityFact({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: context.colors.textSecondary),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClientCompactTotal extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ClientCompactTotal({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientActiveLoansHeader extends StatelessWidget {
  final List<AppChatLoan> loans;

  const _ClientActiveLoansHeader({required this.loans});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final double balance = loans.fold(0, (sum, loan) => sum + loan.amount);
    final int overdue = loans.where((loan) => loan.status == 'ATRASADO').length;
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: context.colors.primary,
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EMPRÉSTIMOS ATIVOS',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .55,
                  ),
                ),
                Text(
                  '${loans.length} contrato(s) • saldo ${currency.format(balance)}',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          if (overdue > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: context.colors.error.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$overdue EM ATRASO',
                style: TextStyle(
                  color: context.colors.error,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatContractCard extends StatelessWidget {
  final AppChatContract contract;
  final VoidCallback onOpen;

  const _ChatContractCard({required this.contract, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final DateFormat date = DateFormat('dd/MM/yyyy');
    final bool overdue = contract.overdueInstallments > 0;
    final Color accent = overdue
        ? context.colors.error
        : const Color(0xFF4B7D60);

    return Container(
      key: ValueKey('chat_contract_card_${contract.loanId}'),
      constraints: const BoxConstraints(maxWidth: 680),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 10, 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Contrato #${contract.loanId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          _ContractStatusPill(
                            label: contract.status,
                            color: accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${contract.clientName} • ${contract.regionName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('open_chat_contract_${contract.loanId}'),
                  tooltip: 'Abrir contrato',
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpen,
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    color: context.colors.primary,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
          Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final int columns = constraints.maxWidth < 430 ? 2 : 4;
                    final double width =
                        (constraints.maxWidth - ((columns - 1) * 7)) / columns;
                    final List<Widget> metrics = [
                      _ContractMetric(
                        label: 'Emprestado',
                        value: currency.format(contract.loanedAmount),
                        icon: Icons.south_west_rounded,
                        color: const Color(0xFF4D7EC7),
                      ),
                      _ContractMetric(
                        label: 'Recebido',
                        value: currency.format(contract.receivedAmount),
                        icon: Icons.savings_outlined,
                        color: const Color(0xFF4B8B66),
                      ),
                      _ContractMetric(
                        label: 'A receber',
                        value: currency.format(contract.receivableAmount),
                        icon: Icons.schedule_rounded,
                        color: overdue
                            ? context.colors.error
                            : const Color(0xFFD18A21),
                      ),
                      _ContractMetric(
                        label: 'Lucro',
                        value: currency.format(contract.profitAmount),
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFF6D5DB3),
                      ),
                    ];
                    return Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: metrics
                          .map((item) => SizedBox(width: width, child: item))
                          .toList(growable: false),
                    );
                  },
                ),
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.background.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 7,
                    children: [
                      _ContractFact(
                        icon: Icons.event_note_outlined,
                        text:
                            '${contract.installmentCount} parcelas • ${contract.paidInstallments} pagas • ${contract.openInstallments} abertas',
                      ),
                      _ContractFact(
                        icon: Icons.calendar_today_outlined,
                        text: contract.contractDate == null
                            ? contract.paymentType
                            : '${date.format(contract.contractDate!)} • ${contract.paymentType}',
                      ),
                      if (contract.overdueInstallments > 0)
                        _ContractFact(
                          icon: Icons.warning_amber_rounded,
                          text:
                              '${contract.overdueInstallments} parcela(s) em atraso',
                          color: context.colors.error,
                        ),
                    ],
                  ),
                ),
                if (contract.lastPaymentDate != null ||
                    contract.nextDueDate != null) ...[
                  const SizedBox(height: 9),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ContractDateBlock(
                          label: 'ÚLTIMO PAGAMENTO',
                          date: contract.lastPaymentDate == null
                              ? 'Sem pagamento'
                              : date.format(contract.lastPaymentDate!),
                          value: contract.lastPaymentDate == null
                              ? null
                              : currency.format(contract.lastPaymentAmount),
                          icon: Icons.check_circle_outline_rounded,
                          color: const Color(0xFF4B8B66),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ContractDateBlock(
                          label: 'PRÓXIMO VENCIMENTO',
                          date: contract.nextDueDate == null
                              ? 'Sem pendência'
                              : date.format(contract.nextDueDate!),
                          value: contract.nextDueDate == null
                              ? null
                              : currency.format(contract.nextDueAmount),
                          icon: Icons.upcoming_outlined,
                          color: overdue
                              ? context.colors.error
                              : const Color(0xFFD18A21),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _ContractStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.isEmpty ? 'Sem status' : label,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ContractMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ContractMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 8,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractFact extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _ContractFact({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final Color foreground = color ?? context.colors.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 13, color: foreground),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContractDateBlock extends StatelessWidget {
  final String label;
  final String date;
  final String? value;
  final IconData icon;
  final Color color;

  const _ContractDateBlock({
    required this.label,
    required this.date,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.divider),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value == null ? date : '$date • $value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineContractHistory extends StatefulWidget {
  final AppChatContract contract;

  const _InlineContractHistory({required this.contract});

  @override
  State<_InlineContractHistory> createState() => _InlineContractHistoryState();
}

class _InlineContractHistoryState extends State<_InlineContractHistory> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<AppChatContractEvent> events = widget.contract.history;
    final DateFormat dateTime = DateFormat('dd/MM/yyyy • HH:mm');
    final double listHeight = (events.length * 61.0).clamp(92.0, 260.0);
    return Container(
      key: ValueKey('chat_contract_history_${widget.contract.loanId}'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.background.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 7),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: context.colors.primary,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HISTÓRICO DO CONTRATO',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .45,
                        ),
                      ),
                      Text(
                        '#${widget.contract.loanId} • ${events.length} evento${events.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.swipe_vertical_rounded,
                  color: context.colors.textSecondary,
                  size: 17,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
          SizedBox(
            height: listHeight,
            child: Scrollbar(
              controller: _controller,
              thumbVisibility: events.length > 3,
              child: ListView.builder(
                key: ValueKey(
                  'chat_contract_history_list_${widget.contract.loanId}',
                ),
                controller: _controller,
                primary: false,
                padding: const EdgeInsets.fromLTRB(10, 9, 8, 4),
                physics: const ClampingScrollPhysics(),
                itemCount: events.length,
                itemBuilder: (context, index) => _ContractEventRow(
                  event: events[index],
                  dateTime: dateTime,
                  last: index == events.length - 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContractEventRow extends StatelessWidget {
  final AppChatContractEvent event;
  final DateFormat dateTime;
  final bool last;

  const _ContractEventRow({
    required this.event,
    required this.dateTime,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final String title = event.description.isNotEmpty
        ? event.description
        : event.operation.isNotEmpty
        ? event.operation
        : event.category;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 1, color: context.colors.divider),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.username}${event.occurredAt == null ? '' : ' • ${dateTime.format(event.occurredAt!)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatLoanResults extends StatefulWidget {
  final List<AppChatLoan> loans;
  final ValueChanged<AppChatLoan> onLoan;

  const _ChatLoanResults({required this.loans, required this.onLoan});

  @override
  State<_ChatLoanResults> createState() => _ChatLoanResultsState();
}

class _ChatLoanResultsState extends State<_ChatLoanResults> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final DateFormat date = DateFormat('dd/MM/yyyy');
    final double listHeight = (widget.loans.length * 50.0).clamp(50.0, 280.0);
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider),
      ),
      child: SizedBox(
        height: listHeight,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: widget.loans.length > 5,
          child: ListView.separated(
            key: const ValueKey('chat_loan_results'),
            controller: _scrollController,
            primary: false,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: widget.loans.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: context.colors.divider),
            itemBuilder: (context, index) {
              final AppChatLoan loan = widget.loans[index];
              final bool overdue = loan.status == 'ATRASADO';
              return SizedBox(
                height: 49,
                child: InkWell(
                  onTap: () => widget.onLoan(loan),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 6, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color:
                                (overdue
                                        ? context.colors.error
                                        : const Color(0xFFE5A900))
                                    .withValues(alpha: .11),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.receipt_long_outlined,
                            color: overdue
                                ? context.colors.error
                                : const Color(0xFFB27A00),
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loan.clientName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '#${loan.loanId} • ${loan.paymentType} • ${loan.dueDate == null ? '-' : date.format(loan.dueDate!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          currency.format(loan.amount),
                          style: TextStyle(
                            color: overdue
                                ? context.colors.error
                                : context.colors.textPrimary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: context.colors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoanTotalsCard extends StatelessWidget {
  final List<AppChatLoan> loans;

  const _LoanTotalsCard({required this.loans});

  @override
  Widget build(BuildContext context) {
    final bool overdue = loans.any((loan) => loan.status == 'ATRASADO');
    final double total = loans.fold(0, (sum, loan) => sum + loan.amount);
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final Color accent = overdue
        ? context.colors.error
        : const Color(0xFFE0A000);
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.today_outlined,
                  color: accent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                overdue ? 'Totais em atraso' : 'Totais dos vencimentos',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _LoanTotalValue(
                  icon: Icons.receipt_long_outlined,
                  label: 'Empréstimos',
                  value: '${loans.length}',
                  color: accent,
                ),
              ),
              Container(width: 1, height: 34, color: context.colors.divider),
              Expanded(
                child: _LoanTotalValue(
                  icon: Icons.payments_outlined,
                  label: 'Valor total',
                  value: currency.format(total),
                  color: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoanTotalValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _LoanTotalValue({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 7),
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 8.5,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientResults extends StatefulWidget {
  final List<AppChatClient> clients;
  final List<AppChatSuggestion> suggestions;
  final ValueChanged<AppChatSuggestion> onSuggestion;

  const _ClientResults({
    required this.clients,
    required this.suggestions,
    required this.onSuggestion,
  });

  @override
  State<_ClientResults> createState() => _ClientResultsState();
}

class _ClientResultsState extends State<_ClientResults> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<int, AppChatSuggestion> byClient = {
      for (final item in widget.suggestions)
        if (item.clientId != null) item.clientId!: item,
    };
    final double listHeight = (widget.clients.length * 54.0).clamp(
      108.0,
      220.0,
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider),
      ),
      child: SizedBox(
        height: listHeight,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: widget.clients.length > 4,
          child: ListView.separated(
            key: const ValueKey('chat_client_results'),
            controller: _scrollController,
            primary: false,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: widget.clients.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: context.colors.divider),
            itemBuilder: (context, index) {
              final AppChatClient client = widget.clients[index];
              return SizedBox(
                height: 53,
                child: InkWell(
                  onTap: byClient[client.id] == null
                      ? null
                      : () => widget.onSuggestion(byClient[client.id]!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: context.colors.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Text(
                            _initials(client.name),
                            style: TextStyle(
                              color: context.colors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                client.regionName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: context.colors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  final AppChatFinancialSummary summary;

  const _SummaryPanel({required this.summary});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double itemWidth = constraints.maxWidth < 500
              ? (constraints.maxWidth - 10) / 2
              : 112;
          return Wrap(
            spacing: 10,
            runSpacing: 7,
            children: [
              _SummaryValue(
                width: itemWidth,
                label: 'Emprestado',
                value: currency.format(summary.loaned),
              ),
              _SummaryValue(
                width: itemWidth,
                label: 'Recebido',
                value: currency.format(summary.received),
                color: const Color(0xFF3F83C5),
              ),
              _SummaryValue(
                width: itemWidth,
                label: 'Atrasados',
                value: currency.format(summary.overdue),
                color: context.colors.error,
              ),
              _SummaryValue(
                width: itemWidth,
                label: 'Lucro',
                value: currency.format(summary.profit),
                color: const Color(0xFF7C65B7),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final double width;

  const _SummaryValue({
    required this.label,
    required this.value,
    required this.width,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 10),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? context.colors.primary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoanStatusDonutCard extends StatelessWidget {
  final AppChatLoanStatus status;

  const _LoanStatusDonutCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final List<_LoanStatusSlice> slices = _loanStatusSlices(context, status);
    final int total = slices.fold(0, (sum, item) => sum + item.count);
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    return _ChatDataCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Distribuição dos empréstimos',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox.square(
                dimension: 112,
                child: CustomPaint(
                  painter: _DonutChartPainter(slices: slices, total: total),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$total',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'empréstimos',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 8.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  children: slices
                      .map(
                        (slice) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: slice.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  slice.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                              Text(
                                '${slice.count} • ${total == 0 ? 0 : (slice.count * 100 / total).round()}%',
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ),
          Divider(height: 18, color: context.colors.divider),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int index = 0; index < slices.length; index++) ...[
                if (index > 0) const SizedBox(width: 5),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 29,
                        color: slices[index].color,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              slices[index].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 8,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                currency.format(slices[index].amount),
                                maxLines: 1,
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientStatusBarCard extends StatelessWidget {
  final AppChatClientStatus status;

  const _ClientStatusBarCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final List<_ClientStatusSlice> slices = [
      _ClientStatusSlice(
        label: 'Ativos',
        count: status.activeCount,
        color: context.colors.primary,
      ),
      _ClientStatusSlice(
        label: 'Sem empréstimos',
        count: status.withoutLoansCount,
        color: context.colors.textSecondary,
      ),
      _ClientStatusSlice(
        label: 'Desaparecido',
        count: status.missingCount,
        color: context.colors.error,
      ),
    ];
    return _ChatDataCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quantidade de clientes',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 154,
            child: CustomPaint(
              painter: _BarChartPainter(
                slices: slices,
                labelColor: context.colors.textSecondary,
                gridColor: context.colors.divider,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientStatusSlice {
  final String label;
  final int count;
  final Color color;

  const _ClientStatusSlice({
    required this.label,
    required this.count,
    required this.color,
  });
}

class _CompactFinancialGoals extends StatelessWidget {
  final List<AppFinancialGoal> goals;

  const _CompactFinancialGoals({required this.goals});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = constraints.maxWidth >= 620
            ? 3
            : constraints.maxWidth >= 430
            ? 2
            : 1;
        final double width =
            (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: goals
              .map(
                (goal) => SizedBox(
                  width: width,
                  child: _CompactFinancialGoalCard(goal: goal),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _CompactFinancialGoalCard extends StatelessWidget {
  final AppFinancialGoal goal;

  const _CompactFinancialGoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final Color accent = _chatGoalColor(context, goal.type);
    return _ChatDataCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, color: accent, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${_shortDate(goal.startDate)} até ${_shortDate(goal.endDate)}',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${goal.displayPercentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Meta de ${goal.type.label.toLowerCase()}',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: goal.progress,
              minHeight: 7,
              color: accent,
              backgroundColor: accent.withValues(alpha: .13),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _GoalCompactValue(
                  label: 'Meta',
                  value: currency.format(goal.targetAmount),
                ),
              ),
              Expanded(
                child: _GoalCompactValue(
                  label: 'Alcançado',
                  value: currency.format(goal.achievedAmount),
                  color: accent,
                ),
              ),
              Expanded(
                child: _GoalCompactValue(
                  label: 'Restante',
                  value: currency.format(goal.remainingAmount),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _chatGoalColor(BuildContext context, AppFinancialGoalType type) =>
    switch (type) {
      AppFinancialGoalType.loaned => context.colors.primary,
      AppFinancialGoalType.received => const Color(0xFF3F83C5),
      AppFinancialGoalType.profit => const Color(0xFF7C65B7),
      _ => context.colors.primary,
    };

class _GoalCompactValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _GoalCompactValue({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 8.5),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color ?? context.colors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ChatDataCard extends StatelessWidget {
  final Widget child;

  const _ChatDataCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider),
      ),
      child: child,
    );
  }
}

class _LoanStatusSlice {
  final String label;
  final int count;
  final double amount;
  final Color color;

  const _LoanStatusSlice({
    required this.label,
    required this.count,
    required this.amount,
    required this.color,
  });
}

List<_LoanStatusSlice> _loanStatusSlices(
  BuildContext context,
  AppChatLoanStatus status,
) => [
  _LoanStatusSlice(
    label: 'Atrasados',
    count: status.overdueCount,
    amount: status.overdueAmount,
    color: context.colors.error,
  ),
  _LoanStatusSlice(
    label: 'Em dia',
    count: status.onTimeCount,
    amount: status.onTimeAmount,
    color: context.colors.primary,
  ),
  _LoanStatusSlice(
    label: 'Quitados',
    count: status.settledCount,
    amount: status.settledAmount,
    color: context.colors.textPrimary,
  ),
];

class _DonutChartPainter extends CustomPainter {
  final List<_LoanStatusSlice> slices;
  final int total;

  const _DonutChartPainter({required this.slices, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.butt;
    if (total == 0) {
      paint.color = const Color(0xFFE4E7EB);
      canvas.drawArc(rect.deflate(10), 0, math.pi * 2, false, paint);
      return;
    }
    double start = -math.pi / 2;
    for (final _LoanStatusSlice slice in slices) {
      if (slice.count == 0) continue;
      final double sweep = math.pi * 2 * slice.count / total;
      paint.color = slice.color;
      canvas.drawArc(rect.deflate(10), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.total != total || oldDelegate.slices != slices;
}

class _BarChartPainter extends CustomPainter {
  final List<_ClientStatusSlice> slices;
  final Color labelColor;
  final Color gridColor;

  const _BarChartPainter({
    required this.slices,
    required this.labelColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double labelHeight = 22;
    const double valueHeight = 18;
    final double chartHeight = size.height - labelHeight - valueHeight;
    final int maximum = slices.fold(
      0,
      (value, item) => math.max(value, item.count),
    );
    final Paint grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, valueHeight + chartHeight),
      Offset(size.width, valueHeight + chartHeight),
      grid,
    );
    final double slot = size.width / slices.length;
    final double barWidth = math.min(38, slot * .46);
    for (int index = 0; index < slices.length; index++) {
      final _ClientStatusSlice slice = slices[index];
      final double fraction = maximum == 0 ? 0 : slice.count / maximum;
      final double height = chartHeight * fraction;
      final double left = slot * index + (slot - barWidth) / 2;
      final RRect bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          valueHeight + chartHeight - height,
          barWidth,
          height,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(bar, Paint()..color = slice.color);
      _paintText(
        canvas,
        '${slice.count}',
        Offset(slot * index, chartHeight - height),
        slot,
        labelColor,
        10,
        FontWeight.w700,
      );
      _paintText(
        canvas,
        slice.label,
        Offset(slot * index, valueHeight + chartHeight + 6),
        slot,
        labelColor,
        9,
        FontWeight.w600,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    double width,
    Color color,
    double fontSize,
    FontWeight weight,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset + Offset((width - painter.width) / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.gridColor != gridColor;
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

class _ChatComposerDock extends StatelessWidget {
  final double bottomWhenClosed;
  final ValueChanged<double> onKeyboardInsetChanged;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool isResponding;
  final AppCodexUsage? usage;
  final List<AppChatModelOption> models;
  final String? selectedModelId;
  final String? selectedServiceTierId;
  final List<AppChatUpload> attachments;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;
  final ValueChanged<AppChatUpload> onRemoveAttachment;
  final VoidCallback onConfigure;

  const _ChatComposerDock({
    required this.bottomWhenClosed,
    required this.onKeyboardInsetChanged,
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.isResponding,
    required this.usage,
    required this.models,
    required this.selectedModelId,
    required this.selectedServiceTierId,
    required this.attachments,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    return _KeyboardInsetPadding(
      bottomWhenClosed: bottomWhenClosed,
      onInsetChanged: onKeyboardInsetChanged,
      child: RepaintBoundary(
        child: _ChatComposer(
          controller: controller,
          focusNode: focusNode,
          canSend: canSend,
          isResponding: isResponding,
          usage: usage,
          models: models,
          selectedModelId: selectedModelId,
          selectedServiceTierId: selectedServiceTierId,
          attachments: attachments,
          onSend: onSend,
          onStop: onStop,
          onAttach: onAttach,
          onRemoveAttachment: onRemoveAttachment,
          onConfigure: onConfigure,
        ),
      ),
    );
  }
}

class _KeyboardInsetPadding extends StatefulWidget {
  final double bottomWhenClosed;
  final ValueChanged<double> onInsetChanged;
  final Widget child;

  const _KeyboardInsetPadding({
    required this.bottomWhenClosed,
    required this.onInsetChanged,
    required this.child,
  });

  @override
  State<_KeyboardInsetPadding> createState() => _KeyboardInsetPaddingState();
}

class _KeyboardInsetPaddingState extends State<_KeyboardInsetPadding> {
  static const double _initialKeyboardTravelFactor = 1.75;

  double _keyboardInset = 0;
  double _largestKeyboardInset = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mantém a dependência do MediaQuery restrita a este pequeno componente.
    // As mensagens e os cards do chat não são reconstruídos em cada frame da
    // animação nativa do teclado.
    final double nextInset = MediaQuery.viewInsetsOf(context).bottom;
    final bool changed = (nextInset - _keyboardInset).abs() > .5;
    _largestKeyboardInset = math.max(_largestKeyboardInset, nextInset);
    _keyboardInset = nextInset;
    if (changed) widget.onInsetChanged(nextInset);
  }

  @override
  Widget build(BuildContext context) {
    // Na primeira abertura ainda não conhecemos a altura final do teclado.
    // Esta estimativa baseada no espaço fechado inicia o deslocamento já no
    // primeiro inset, evitando que o dock fique parado e depois salte. Assim
    // que o teclado supera a estimativa, sua altura real passa a ser usada.
    final double keyboardTravel = math.max(
      _largestKeyboardInset,
      widget.bottomWhenClosed * _initialKeyboardTravelFactor,
    );
    final double keyboardProgress = keyboardTravel == 0
        ? 0
        : (_keyboardInset / keyboardTravel).clamp(0.0, 1.0);
    final double bottomClearance =
        _keyboardInset + widget.bottomWhenClosed * (1 - keyboardProgress);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: widget.child,
    );
  }
}

class _ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool isResponding;
  final AppCodexUsage? usage;
  final List<AppChatModelOption> models;
  final String? selectedModelId;
  final String? selectedServiceTierId;
  final List<AppChatUpload> attachments;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;
  final ValueChanged<AppChatUpload> onRemoveAttachment;
  final VoidCallback onConfigure;

  const _ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.isResponding,
    required this.usage,
    required this.models,
    required this.selectedModelId,
    required this.selectedServiceTierId,
    required this.attachments,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (usage != null || models.isNotEmpty) ...[
                    _ChatControlsRow(
                      usage: usage,
                      models: models,
                      selectedModelId: selectedModelId,
                      selectedServiceTierId: selectedServiceTierId,
                      onConfigure: onConfigure,
                    ),
                    const SizedBox(height: 7),
                  ],
                  if (attachments.isNotEmpty) ...[
                    _AttachmentStrip(
                      attachments: attachments,
                      enabled: !isResponding,
                      onRemove: onRemoveAttachment,
                    ),
                    const SizedBox(height: 7),
                  ],
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 200,
                    inputFormatters: [LengthLimitingTextInputFormatter(200)],
                    textInputAction: TextInputAction.send,
                    onSubmitted: canSend ? (_) => onSend() : null,
                    decoration: InputDecoration(
                      hintText: 'Digite sua consulta financeira...',
                      hintStyle: TextStyle(
                        color: context.colors.textPlaceholder,
                        fontSize: 13,
                      ),
                      filled: true,
                      counterText: '',
                      fillColor: context.colors.background,
                      contentPadding: const EdgeInsetsDirectional.fromSTEB(
                        15,
                        11,
                        5,
                        11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: context.colors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: context.colors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: context.colors.primary,
                          width: 1.4,
                        ),
                      ),
                      prefixIcon: IconButton(
                        tooltip: attachments.length >= 3
                            ? 'Limite de três arquivos atingido'
                            : 'Anexar imagem ou arquivo',
                        onPressed: isResponding || attachments.length >= 3
                            ? null
                            : onAttach,
                        icon: const Icon(Icons.attach_file_rounded, size: 20),
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.all(4),
                        child: IconButton.filled(
                          tooltip: isResponding ? 'Interromper' : 'Enviar',
                          onPressed: isResponding
                              ? onStop
                              : canSend
                              ? onSend
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: isResponding
                                ? context.colors.secondary
                                : context.colors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: context.colors.disabled,
                          ),
                          icon: Icon(
                            isResponding
                                ? Icons.stop_rounded
                                : Icons.send_rounded,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatControlsRow extends StatelessWidget {
  final AppCodexUsage? usage;
  final List<AppChatModelOption> models;
  final String? selectedModelId;
  final String? selectedServiceTierId;
  final VoidCallback onConfigure;

  const _ChatControlsRow({
    required this.usage,
    required this.models,
    required this.selectedModelId,
    required this.selectedServiceTierId,
    required this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    AppChatModelOption? model;
    for (final AppChatModelOption item in models) {
      if (item.id == selectedModelId) model = item;
    }
    model ??= models.isEmpty ? null : models.first;
    final AppChatServiceTier? tier = model?.tier(selectedServiceTierId);
    return Row(
      children: [
        if (usage != null) Expanded(child: _ChatGptUsageBar(usage: usage!)),
        if (usage != null && model != null) const SizedBox(width: 8),
        if (model != null)
          Tooltip(
            message: 'Selecionar modelo e velocidade',
            child: InkWell(
              onTap: onConfigure,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 184),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgIcon(
                      icon: AppIcons.gpt,
                      width: 14,
                      height: 14,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${model.name} • ${tier == null ? 'Padrão' : _serviceTierLabel(tier)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 15,
                      color: context.colors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatGptUsageBar extends StatelessWidget {
  final AppCodexUsage usage;

  const _ChatGptUsageBar({required this.usage});

  @override
  Widget build(BuildContext context) {
    final double percent = usage.remainingPercent;
    final Color color = percent <= 10
        ? context.colors.error
        : percent <= 25
        ? context.colors.secondary
        : context.colors.primary;
    final String formatted = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(
        children: [
          Text(
            'Limite disponível',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usage.remainingProgress,
                minHeight: 3,
                color: color,
                backgroundColor: color.withValues(alpha: 0.14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$formatted%',
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  final List<AppChatUpload> attachments;
  final bool enabled;
  final ValueChanged<AppChatUpload> onRemove;

  const _AttachmentStrip({
    required this.attachments,
    required this.enabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 6,
        runSpacing: 5,
        children: [
          for (final AppChatUpload attachment in attachments)
            InputChip(
              avatar: const Icon(Icons.description_outlined, size: 16),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              onDeleted: enabled ? () => onRemove(attachment) : null,
              deleteIcon: const Icon(Icons.close_rounded, size: 16),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: context.colors.divider),
              backgroundColor: context.colors.background,
            ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        children: [
          const _AssistantAvatar(size: 34),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.colors.divider),
            ),
            child: SizedBox(
              width: 38,
              child: LinearProgressIndicator(
                minHeight: 3,
                color: context.colors.primary,
                backgroundColor: context.colors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantAvatar extends StatelessWidget {
  final double size;

  const _AssistantAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.asset(
          'assets/images/profile.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final List<String> words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    return words.first
        .substring(0, words.first.length.clamp(1, 2))
        .toUpperCase();
  }
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}
