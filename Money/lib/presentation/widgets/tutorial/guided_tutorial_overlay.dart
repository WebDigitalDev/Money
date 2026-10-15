import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:money/money.dart';

class GuidedTutorialOverlay extends StatefulWidget {
  final TutorialGuideController controller;

  const GuidedTutorialOverlay({super.key, required this.controller});

  @override
  State<GuidedTutorialOverlay> createState() => _GuidedTutorialOverlayState();
}

class _GuidedTutorialOverlayState extends State<GuidedTutorialOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _targetWaitTimeout = Duration(seconds: 8);
  static const String _desktopAudio = 'assets/audios/desk1.mp3';
  static const String _mobileAudio = 'assets/audios/mob1.mp3';
  static const Duration _desktopDuration = Duration(milliseconds: 31425);
  static const Duration _mobileDuration = Duration(milliseconds: 28839);
  static const String _desktopText =
      'Primeiramente, para criar um novo empréstimo no sistema basta ir na aba de empréstimos, ao abrir clique no botão novo empréstimo.\n'
      'Feito isso vai abrir a página de clientes, onde poderá pesquisar pelo nome do cliente no sistema e caso o cliente não esteja na lista cadastrado é só clicar no botão novo cliente e realizar o cadastro.\n'
      'Se o cliente já estiver na lista, é só clicar que vai abrir o dados do cliente para você conferir e depois clicar em novo empréstimo.';
  static const String _mobileText =
      'Primeiramente, para criar um empréstimo no sistema basta clicar no botão central da aplicação e escolher a opção novo empréstimo.\n'
      'Feito isso vai abrir a página de clientes, onde poderá pesquisar pelo nome do cliente no sistema e caso o cliente não esteja na lista cadastrado é só clicar no botão central novamente que abrirá a página de cadastro.\n'
      'Se o cliente já estiver na lista, é só clicar que vai abrir os dados do cliente para você conferir e depois clicar em novo empréstimo.';

  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: true,
    androidApplyAudioAttributes: true,
    handleAudioSessionActivation: true,
  );
  late final AnimationController _pulseController;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  Timer? _targetRefreshTimer;
  Timer? _playbackGuard;
  Timer? _conclusionTimer;
  bool _initialized = false;
  bool _desktop = false;
  bool _audioLoaded = false;
  Duration _duration = Duration.zero;
  String _script = '';
  String _visibleText = '';
  List<_GuideCue> _cues = const [];
  int _nextCue = 0;
  TutorialTarget? _target;
  List<Rect> _targetRects = const [];
  bool _waitingForTarget = false;
  bool _audioCompleted = false;
  int _targetWaitVersion = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _targetRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 90),
      (_) => _refreshTargetRect(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    _script = _desktop ? _desktopText : _mobileText;
    _duration = _desktop ? _desktopDuration : _mobileDuration;
    _cues = _desktop ? _buildDesktopCues() : _buildMobileCues();
    _target = _desktop
        ? TutorialTarget.desktopLoansTab
        : TutorialTarget.mobileCentralAction;
    _positionSubscription = _player
        .createPositionStream(
          steps: 1600,
          minPeriod: const Duration(milliseconds: 16),
          maxPeriod: const Duration(milliseconds: 32),
        )
        .listen(_updateFromPosition);
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerState,
    );
    _errorSubscription = _player.errorStream.listen(
      (_) => _handlePlaybackUnavailable(),
    );
    unawaited(_loadAndPlay());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _targetRefreshTimer?.cancel();
    _playbackGuard?.cancel();
    _conclusionTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _loadAndPlay() async {
    try {
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await _player.setVolume(1);
      final Duration? loadedDuration = await _player.setAudioSource(
        AudioSource.asset(_desktop ? _desktopAudio : _mobileAudio),
      );
      if (!mounted) return;
      _duration = loadedDuration ?? _duration;
      _audioLoaded = true;
      _guardPlaybackStart();
      await _player.play();
    } catch (_) {
      _handlePlaybackUnavailable();
    }
  }

  void _guardPlaybackStart() {
    _playbackGuard?.cancel();
    _playbackGuard = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted || !_audioLoaded || _player.position > Duration.zero) return;
      _handlePlaybackUnavailable();
    });
  }

  void _handlePlaybackUnavailable() {
    if (!mounted) return;
    setState(() {
      _visibleText = _script;
      _audioCompleted = true;
    });
    _runRemainingCues();
    _maybeScheduleConclusion();
  }

  void _handlePlayerState(PlayerState state) {
    if (!mounted || state.processingState != ProcessingState.completed) return;
    _playbackGuard?.cancel();
    setState(() {
      _visibleText = _script;
      _audioCompleted = true;
    });
    _runRemainingCues();
    _maybeScheduleConclusion();
  }

  void _updateFromPosition(Duration position) {
    if (!mounted || _duration <= Duration.zero) return;
    final double progress = (position.inMicroseconds / _duration.inMicroseconds)
        .clamp(0, 1);
    final int characterCount = (_script.length * progress).ceil().clamp(
      0,
      _script.length,
    );
    final String nextText = _script.substring(0, characterCount);
    if (_desktop && nextText != _visibleText) {
      setState(() => _visibleText = nextText);
    }
    _runCuesThrough(characterCount);
  }

  void _runCuesThrough(int characterCount) {
    if (_waitingForTarget) return;
    while (_nextCue < _cues.length &&
        characterCount >= _cues[_nextCue].characterIndex) {
      final _GuideCue cue = _cues[_nextCue++];
      _activateCue(cue);
      return;
    }
  }

  void _runRemainingCues() {
    if (_waitingForTarget) return;
    while (_nextCue < _cues.length) {
      final _GuideCue cue = _cues[_nextCue++];
      _activateCue(cue);
      return;
    }
  }

  void _activateCue(_GuideCue cue) {
    if (!mounted) return;
    final int waitVersion = ++_targetWaitVersion;
    setState(() {
      _target = cue.target;
      _targetRects = const [];
      _waitingForTarget = true;
    });
    _performAction(cue.action);
    unawaited(
      _waitUntilTargetIsVisible(
        cue.target,
        waitVersion,
        pauseForTarget: cue.pauseForTarget,
      ),
    );
  }

  Future<void> _waitUntilTargetIsVisible(
    TutorialTarget target,
    int waitVersion, {
    required bool pauseForTarget,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || waitVersion != _targetWaitVersion || _target != target) {
      return;
    }

    List<Rect> targetRects = _readTargetRects(target);
    bool pausedForTarget = false;
    if (targetRects.isEmpty) {
      if (pauseForTarget) {
        pausedForTarget = true;
        try {
          await _player.pause();
        } catch (_) {
          _handlePlaybackUnavailable();
          return;
        }
      }
      final DateTime waitDeadline = DateTime.now().add(_targetWaitTimeout);
      while (mounted &&
          waitVersion == _targetWaitVersion &&
          _target == target &&
          targetRects.isEmpty &&
          DateTime.now().isBefore(waitDeadline)) {
        await _revealTarget(target);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (!mounted) return;
        targetRects = _readTargetRects(target);
      }
    }

    if (!mounted || waitVersion != _targetWaitVersion || _target != target) {
      return;
    }
    if (targetRects.isEmpty) {
      setState(() {
        _targetRects = const [];
        _waitingForTarget = false;
      });
      await _resumeAfterTargetWait(pausedForTarget);
      return;
    }
    setState(() {
      _targetRects = targetRects;
      _waitingForTarget = false;
    });

    await _resumeAfterTargetWait(pausedForTarget);
  }

  Future<void> _resumeAfterTargetWait(bool pausedForTarget) async {
    if (!mounted) return;
    if (pausedForTarget &&
        _player.processingState != ProcessingState.completed) {
      try {
        await _player.play();
      } catch (_) {
        _handlePlaybackUnavailable();
      }
    }
    if (!pausedForTarget &&
        _player.processingState == ProcessingState.completed) {
      _runRemainingCues();
    }
    _maybeScheduleConclusion();
  }

  void _maybeScheduleConclusion() {
    if (!_audioCompleted ||
        _waitingForTarget ||
        _nextCue < _cues.length ||
        _conclusionTimer != null) {
      return;
    }
    _conclusionTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      unawaited(widget.controller.beginConclusion());
    });
  }

  Future<void> _revealTarget(TutorialTarget target) async {
    for (final GlobalKey key in widget.controller.keysFor(target)) {
      final BuildContext? targetContext = key.currentContext;
      if (targetContext == null) continue;
      try {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } on Object {
        // A próxima atualização tenta novamente se a tela ainda estiver mudando.
      }
    }
  }

  void _performAction(_GuideAction? action) {
    switch (action) {
      case _GuideAction.openLoansPage:
        widget.controller.openLoansPage();
        break;
      case _GuideAction.openClientsPage:
        widget.controller.openClientsPage();
        break;
      case _GuideAction.openMobileQuickActions:
        widget.controller.openMobileQuickActions();
        break;
      case _GuideAction.selectMobileNewLoan:
        widget.controller.selectMobileNewLoan();
        break;
      case _GuideAction.ensureTutorialClient:
        unawaited(widget.controller.ensureTutorialClient());
        break;
      case _GuideAction.openTutorialClient:
        unawaited(widget.controller.openTutorialClient());
        break;
      case null:
        break;
    }
  }

  List<_GuideCue> _buildDesktopCues() => [
    _GuideCue(
      characterIndex: _after(_desktopText, 'aba de empréstimos,'),
      target: TutorialTarget.desktopNewLoanButton,
      action: _GuideAction.openLoansPage,
    ),
    _GuideCue(
      characterIndex: _after(_desktopText, 'botão novo empréstimo.'),
      target: TutorialTarget.clientSearch,
      action: _GuideAction.openClientsPage,
    ),
    _GuideCue(
      characterIndex: _before(_desktopText, 'botão novo cliente'),
      target: TutorialTarget.desktopNewClientButton,
    ),
    _GuideCue(
      characterIndex: _before(_desktopText, 'Se o cliente já estiver'),
      target: TutorialTarget.tutorialClient,
      action: _GuideAction.ensureTutorialClient,
    ),
    _GuideCue(
      characterIndex: _after(
        _desktopText,
        'Se o cliente já estiver na lista, é só clicar',
      ),
      target: TutorialTarget.clientNewLoanButton,
      action: _GuideAction.openTutorialClient,
      pauseForTarget: false,
    ),
  ];

  List<_GuideCue> _buildMobileCues() => [
    _GuideCue(
      characterIndex: _after(_mobileText, 'botão central da aplicação'),
      target: TutorialTarget.mobileNewLoanOption,
      action: _GuideAction.openMobileQuickActions,
      pauseForTarget: false,
    ),
    _GuideCue(
      characterIndex: _after(_mobileText, 'opção novo empréstimo.'),
      target: TutorialTarget.clientSearch,
      action: _GuideAction.selectMobileNewLoan,
    ),
    _GuideCue(
      characterIndex: _before(_mobileText, 'botão central novamente'),
      target: TutorialTarget.mobileCentralAction,
    ),
    _GuideCue(
      characterIndex: _before(_mobileText, 'Se o cliente já estiver'),
      target: TutorialTarget.tutorialClient,
      action: _GuideAction.ensureTutorialClient,
    ),
    _GuideCue(
      characterIndex: _after(
        _mobileText,
        'Se o cliente já estiver na lista, é só clicar',
      ),
      target: TutorialTarget.clientNewLoanButton,
      action: _GuideAction.openTutorialClient,
      pauseForTarget: false,
    ),
  ];

  int _before(String text, String fragment) {
    final int index = text.indexOf(fragment);
    return index < 0 ? text.length : index;
  }

  int _after(String text, String fragment) {
    final int index = text.indexOf(fragment);
    return index < 0 ? text.length : index + fragment.length;
  }

  void _refreshTargetRect() {
    if (!mounted || _target == null) return;
    final List<Rect> nextRects = _readTargetRects(_target!);
    if (nextRects.isEmpty) {
      if (_targetRects.isNotEmpty) {
        setState(() => _targetRects = const []);
      }
      return;
    }
    if (listEquals(_targetRects, nextRects)) return;
    setState(() => _targetRects = nextRects);
  }

  List<Rect> _readTargetRects(TutorialTarget target) {
    if (!mounted) return const [];
    final RenderObject? overlayRenderObject = context.findRenderObject();
    if (overlayRenderObject is! RenderBox ||
        !overlayRenderObject.attached ||
        !overlayRenderObject.hasSize) {
      return const [];
    }
    final Offset overlayGlobal = overlayRenderObject.localToGlobal(Offset.zero);
    final Rect overlayBounds = Offset.zero & overlayRenderObject.size;
    final List<Rect> result = [];
    for (final GlobalKey key in widget.controller.keysFor(target)) {
      final RenderObject? targetRenderObject = key.currentContext
          ?.findRenderObject();
      if (targetRenderObject is! RenderBox ||
          !targetRenderObject.attached ||
          !targetRenderObject.hasSize) {
        return const [];
      }
      final Offset targetGlobal = targetRenderObject.localToGlobal(Offset.zero);
      final Rect targetRect =
          (targetGlobal - overlayGlobal) & targetRenderObject.size;
      if (!targetRect.overlaps(overlayBounds)) return const [];
      result.add(targetRect.intersect(overlayBounds));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final List<Rect> spotlights = [
      for (final Rect rect in _targetRects) rect.inflate(_desktop ? 7 : 9),
    ];
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _SpotlightOutsideClipper(spotlights),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: _desktop ? 0.46 : 0.50),
              ),
            ),
          ),
          const ModalBarrier(
            dismissible: false,
            color: Colors.transparent,
            semanticsLabel: 'Demonstração guiada em andamento',
          ),
          if (spotlights.isNotEmpty)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) => Stack(
                children: [
                  for (int index = 0; index < spotlights.length; index++)
                    _SpotlightFrame(
                      rect: spotlights[index],
                      progress: _pulseController.value,
                      label: index == 0 ? _labelForTarget(_target!) : null,
                    ),
                ],
              ),
            ),
          if (_desktop) _buildDesktopAssistant(context),
        ],
      ),
    );
  }

  Widget _buildDesktopAssistant(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double panelWidth = math.min(760, size.width * 0.54);
    const double panelHeight = 235;
    final double imageHeight = (size.height * 0.64).clamp(430, 620);
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            right: 34,
            bottom: -38,
            child: IgnorePointer(
              child: Image.asset(
                AppImages.virtualAssistant,
                height: imageHeight,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Positioned(
            right: 28,
            bottom: 28,
            child: Container(
              width: panelWidth,
              height: panelHeight,
              padding: const EdgeInsets.fromLTRB(24, 30, 22, 18),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: context.colors.primary, width: 1.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Text(
                _visibleText,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 14.2,
                  height: 1.38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Positioned(
            right: panelWidth - 95,
            bottom: panelHeight + 11,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 7),
              decoration: BoxDecoration(
                color: context.colors.primary,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text(
                'Money',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _labelForTarget(TutorialTarget target) => switch (target) {
    TutorialTarget.desktopLoansTab => 'EMPRÉSTIMOS',
    TutorialTarget.desktopNewLoanButton => 'NOVO EMPRÉSTIMO',
    TutorialTarget.clientSearch => 'PESQUISAR CLIENTE',
    TutorialTarget.desktopNewClientButton => 'NOVO CLIENTE',
    TutorialTarget.mobileCentralAction => 'BOTÃO CENTRAL',
    TutorialTarget.mobileNewLoanOption => 'NOVO EMPRÉSTIMO',
    TutorialTarget.tutorialClient => 'WEBDIGITAL DEVELOPMENT',
    TutorialTarget.clientNewLoanButton => 'NOVO EMPRÉSTIMO',
    TutorialTarget.desktopChatButton => 'ASSISTENTE MONEY',
    TutorialTarget.mobileChatButton => 'CHAT',
    TutorialTarget.mobileSidebarMenuButton => 'MENU DE PÁGINAS',
  };
}

enum _GuideAction {
  openLoansPage,
  openClientsPage,
  openMobileQuickActions,
  selectMobileNewLoan,
  ensureTutorialClient,
  openTutorialClient,
}

class _GuideCue {
  final int characterIndex;
  final TutorialTarget target;
  final _GuideAction? action;
  final bool pauseForTarget;

  const _GuideCue({
    required this.characterIndex,
    required this.target,
    this.action,
    this.pauseForTarget = true,
  });
}

class _SpotlightOutsideClipper extends CustomClipper<Path> {
  final List<Rect> spotlights;

  const _SpotlightOutsideClipper(this.spotlights);

  @override
  Path getClip(Size size) {
    final Path path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    for (final Rect spotlight in spotlights) {
      path.addRRect(
        RRect.fromRectAndRadius(spotlight, const Radius.circular(14)),
      );
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _SpotlightOutsideClipper oldClipper) =>
      !listEquals(oldClipper.spotlights, spotlights);
}

class _SpotlightFrame extends StatelessWidget {
  final Rect rect;
  final double progress;
  final String? label;

  const _SpotlightFrame({
    required this.rect,
    required this.progress,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = context.colors.primary;
    final double pulse = 2 + (progress * 5);
    final bool showBelow = rect.top < 56;
    final double labelTop = showBelow ? rect.bottom + 9 : rect.top - 38;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect.inflate(pulse),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16 + pulse),
                border: Border.all(color: primary, width: 2.4),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.28 - (progress * 0.10)),
                    blurRadius: 13 + (progress * 10),
                    spreadRadius: 2 + progress,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (label != null)
          Positioned(
            left: rect.left,
            top: math.max(8.0, labelTop),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 9,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    label!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
