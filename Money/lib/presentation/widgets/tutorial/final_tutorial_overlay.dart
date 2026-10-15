import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:money/money.dart';

class FinalTutorialOverlay extends StatefulWidget {
  final TutorialGuideController controller;
  final Future<void> Function() onComplete;

  const FinalTutorialOverlay({
    super.key,
    required this.controller,
    required this.onComplete,
  });

  @override
  State<FinalTutorialOverlay> createState() => _FinalTutorialOverlayState();
}

class _FinalTutorialOverlayState extends State<FinalTutorialOverlay>
    with TickerProviderStateMixin {
  static const String _desktopAudio = 'assets/audios/deskt2.mp3';
  static const String _mobileAudio = 'assets/audios/mob2.mp3';
  static const Duration _desktopDuration = Duration(milliseconds: 19043);
  static const Duration _mobileDuration = Duration(milliseconds: 19958);
  static const String _desktopText =
      'Viu como é fácil? Vou só demostrar essa parte do sistema.\n'
      'Agora é com você! é só clicar em concluir que finalizamos por aqui.\n'
      'Ahh só lembrando... se precisar de alguma consulta rápida ou alguma informação financeira pode contar comigo! é só clicar no botão flutuante que estarei pronta para lhe ajudar.';
  static const String _mobileText =
      'Viu como é fácil? Vou só demostrar essa parte do sistema.\n'
      'Agora é com você! é só clicar em concluir que finalizamos por aqui.\n'
      'Ahh só lembrando... se precisar de alguma consulta rápida ou alguma informação financeira pode contar comigo! é só ir em chat que estarei pronta para lhe ajudar.';

  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: true,
    androidApplyAudioAttributes: true,
    handleAudioSessionActivation: true,
  );
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  Timer? _targetRefreshTimer;
  Timer? _playbackDelay;
  Timer? _playbackGuard;

  bool _initialized = false;
  bool _desktop = false;
  bool _audioLoaded = false;
  bool _speechCompleted = false;
  bool _highlightChat = false;
  bool _saving = false;
  bool _restarting = false;
  Duration _duration = Duration.zero;
  String _script = '';
  String _visibleText = '';
  Rect? _chatRect;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
    _positionSubscription = _player
        .createPositionStream(
          steps: 1200,
          minPeriod: const Duration(milliseconds: 16),
          maxPeriod: const Duration(milliseconds: 32),
        )
        .listen(_updateFromPosition);
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerState,
    );
    _errorSubscription = _player.errorStream.listen(
      (_) => _showPlaybackUnavailable(),
    );
    _targetRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _refreshChatRect(),
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
    unawaited(_loadAudio());
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _targetRefreshTimer?.cancel();
    _playbackDelay?.cancel();
    _playbackGuard?.cancel();
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _loadAudio() async {
    try {
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await _player.setVolume(1);
      final Duration? loadedDuration = await _player.setAudioSource(
        AudioSource.asset(_desktop ? _desktopAudio : _mobileAudio),
      );
      if (!mounted) return;
      setState(() {
        _duration = loadedDuration ?? _duration;
        _audioLoaded = true;
      });
      _playbackDelay = Timer(const Duration(milliseconds: 120), () {
        if (mounted) unawaited(_startPlayback());
      });
    } catch (_) {
      _showPlaybackUnavailable();
    }
  }

  Future<void> _startPlayback() async {
    if (!_audioLoaded || !mounted) return;
    try {
      setState(() {
        _visibleText = '';
        _speechCompleted = false;
        _highlightChat = false;
        _chatRect = null;
      });
      _guardPlaybackStart();
      await _player.play();
    } catch (_) {
      _showPlaybackUnavailable();
    }
  }

  void _guardPlaybackStart() {
    _playbackGuard?.cancel();
    final Duration startingPosition = _player.position;
    _playbackGuard = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted || _player.position > startingPosition) return;
      _showPlaybackUnavailable();
    });
  }

  void _showPlaybackUnavailable() {
    if (!mounted) return;
    setState(() {
      _visibleText = _script;
      _highlightChat = false;
      _chatRect = null;
      _speechCompleted = true;
    });
  }

  void _handlePlayerState(PlayerState state) {
    if (!mounted || state.processingState != ProcessingState.completed) return;
    _playbackGuard?.cancel();
    setState(() {
      _visibleText = _script;
      _highlightChat = false;
      _chatRect = null;
      _speechCompleted = true;
    });
  }

  void _updateFromPosition(Duration position) {
    if (!mounted || _duration <= Duration.zero || _speechCompleted) return;
    final double progress = (position.inMicroseconds / _duration.inMicroseconds)
        .clamp(0, 1);
    final int characterCount = (_script.length * progress).ceil().clamp(
      0,
      _script.length,
    );
    final String nextText = _script.substring(0, characterCount);
    final int chatCue = _desktop
        ? _before(_script, 'botão flutuante')
        : _before(_script, 'chat que estarei');
    final bool nextHighlight = characterCount >= chatCue;
    if (nextText == _visibleText && nextHighlight == _highlightChat) return;
    setState(() {
      _visibleText = nextText;
      _highlightChat = nextHighlight;
    });
    if (nextHighlight) _refreshChatRect();
  }

  int _before(String text, String fragment) {
    final int index = text.indexOf(fragment);
    return index < 0 ? text.length : index;
  }

  GlobalKey get _chatKey => _desktop
      ? widget.controller.desktopChatButtonKey
      : widget.controller.mobileChatButtonKey;

  void _refreshChatRect() {
    if (!mounted || !_highlightChat) return;
    final RenderObject? overlayObject = context.findRenderObject();
    final RenderObject? targetObject = _chatKey.currentContext
        ?.findRenderObject();
    if (overlayObject is! RenderBox ||
        targetObject is! RenderBox ||
        !overlayObject.attached ||
        !targetObject.attached ||
        !overlayObject.hasSize ||
        !targetObject.hasSize) {
      return;
    }
    final Offset overlayGlobal = overlayObject.localToGlobal(Offset.zero);
    final Offset targetGlobal = targetObject.localToGlobal(Offset.zero);
    final Rect next = ((targetGlobal - overlayGlobal) & targetObject.size)
        .inflate(_desktop ? 8 : 7)
        .intersect(Offset.zero & overlayObject.size);
    if (_chatRect == next) return;
    setState(() => _chatRect = next);
  }

  Future<void> _restartWalkthrough() async {
    if (_restarting || _saving) return;
    setState(() {
      _restarting = true;
      _errorMessage = null;
    });
    await _player.stop();
    await widget.controller.restartWalkthrough();
  }

  Future<void> _completeTutorial() async {
    if (_saving || _restarting) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await widget.onComplete();
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
        _errorMessage = 'Não foi possível concluir. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Rect? spotlight = _highlightChat ? _chatRect : null;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return PopScope<void>(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: _FinalSpotlightClipper(spotlight),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
              ),
            ),
            const ModalBarrier(
              dismissible: false,
              color: Colors.transparent,
              semanticsLabel: 'Conclusão do tutorial em andamento',
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => _desktop
                    ? _buildDesktop(context, constraints, reduceMotion)
                    : _buildMobile(context, constraints, reduceMotion),
              ),
            ),
            if (spotlight != null)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => _FinalSpotlightFrame(
                  rect: spotlight,
                  progress: _pulseController.value,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    BoxConstraints constraints,
    bool reduceMotion,
  ) {
    const double panelHeight = 276;
    const double panelBottom = 108;
    final double imageHeight = (constraints.maxHeight * 0.50).clamp(
      280.0,
      450.0,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -16,
          bottom: panelBottom + (panelHeight * 0.30),
          child: _buildEntrance(
            reduceMotion: reduceMotion,
            start: 0,
            end: 0.68,
            beginOffset: const Offset(38, 64),
            beginScale: 0.92,
            child: IgnorePointer(
              child: Image.asset(
                AppImages.virtualAssistant,
                height: imageHeight,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: panelBottom,
          child: _buildEntrance(
            reduceMotion: reduceMotion,
            start: 0.18,
            end: 1,
            beginOffset: const Offset(0, 48),
            beginScale: 0.9,
            curve: Curves.easeOutBack,
            child: _buildDialoguePanel(
              context,
              height: panelHeight,
              maxWidth: 520,
              textSize: constraints.maxWidth < 360 ? 12.6 : 13.8,
              mobile: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    BoxConstraints constraints,
    bool reduceMotion,
  ) {
    final double imageHeight = (constraints.maxHeight * 0.74).clamp(
      450.0,
      680.0,
    );
    final double characterRight = math.max(
      86,
      ((constraints.maxWidth - 780) / 2) - 235,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: characterRight,
          bottom: -42,
          child: _buildEntrance(
            reduceMotion: reduceMotion,
            start: 0,
            end: 0.68,
            beginOffset: const Offset(58, 76),
            beginScale: 0.92,
            child: IgnorePointer(
              child: Image.asset(
                AppImages.virtualAssistant,
                height: imageHeight,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        Positioned(
          left: 42,
          right: 42,
          bottom: 42,
          child: Center(
            heightFactor: 1,
            child: _buildEntrance(
              reduceMotion: reduceMotion,
              start: 0.18,
              end: 1,
              beginOffset: const Offset(0, 54),
              beginScale: 0.9,
              curve: Curves.easeOutBack,
              child: _buildDialoguePanel(
                context,
                height: 236,
                maxWidth: 780,
                textSize: 16.2,
                mobile: false,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEntrance({
    required Widget child,
    required bool reduceMotion,
    required double start,
    required double end,
    required Offset beginOffset,
    required double beginScale,
    Curve curve = Curves.easeOutCubic,
  }) {
    if (reduceMotion) return child;
    return AnimatedBuilder(
      animation: _entranceController,
      child: child,
      builder: (context, child) {
        final double raw = ((_entranceController.value - start) / (end - start))
            .clamp(0, 1);
        final double motion = curve.transform(raw);
        return Opacity(
          opacity: Curves.easeOut.transform(raw),
          child: Transform.translate(
            offset: beginOffset * (1 - motion),
            child: Transform.scale(
              scale: beginScale + ((1 - beginScale) * motion),
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialoguePanel(
    BuildContext context, {
    required double height,
    required double maxWidth,
    required double textSize,
    required bool mobile,
  }) {
    final Color primary = context.colors.primary;
    final Color neutralButton = context.isDark
        ? const Color(0xFF282B29)
        : const Color(0xFFF0F2F1);
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(mobile ? 26 : 30),
                    border: Border.all(color: primary, width: 1.7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 18 : 26,
                      mobile ? 27 : 30,
                      mobile ? 16 : 22,
                      mobile ? 12 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: TutorialFittedTranscript(
                            fullText: _script,
                            visibleText: _visibleText,
                            color: context.colors.textPrimary,
                            preferredFontSize: textSize,
                          ),
                        ),
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              _errorMessage!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.error,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 7),
                        SizedBox(
                          height: 44,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            child: _speechCompleted
                                ? Row(
                                    key: const ValueKey(
                                      'tutorial_conclusion_controls',
                                    ),
                                    children: [
                                      IconButton(
                                        onPressed: _saving || _restarting
                                            ? null
                                            : _restartWalkthrough,
                                        tooltip: 'Reiniciar demonstração',
                                        style: IconButton.styleFrom(
                                          backgroundColor: neutralButton,
                                          foregroundColor:
                                              context.colors.textSecondary,
                                          fixedSize: const Size.square(42),
                                          shape: const CircleBorder(),
                                          side: BorderSide(
                                            color: context.colors.divider,
                                          ),
                                        ),
                                        icon: _restarting
                                            ? const SizedBox.square(
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : TutorialReplayAudioIcon(
                                                color: context
                                                    .colors
                                                    .textSecondary,
                                              ),
                                      ),
                                      const Spacer(),
                                      FilledButton.icon(
                                        onPressed: _saving || _restarting
                                            ? null
                                            : _completeTutorial,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: primary,
                                          foregroundColor: Colors.white,
                                          minimumSize: Size(
                                            mobile ? 126 : 156,
                                            44,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                          ),
                                        ),
                                        iconAlignment: IconAlignment.end,
                                        icon: _saving
                                            ? const SizedBox.square(
                                                dimension: 17,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.check_rounded,
                                                size: 20,
                                              ),
                                        label: const Text(
                                          'CONCLUIR',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.expand(
                                    key: ValueKey(
                                      'tutorial_conclusion_controls_hidden',
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: mobile ? 21 : 30,
                top: -15,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 19, vertical: 7),
                    child: Text(
                      'Money',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
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

class _FinalSpotlightClipper extends CustomClipper<Path> {
  final Rect? spotlight;

  const _FinalSpotlightClipper(this.spotlight);

  @override
  Path getClip(Size size) {
    final Path path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    final Rect? target = spotlight;
    if (target != null) {
      path.addRRect(RRect.fromRectAndRadius(target, const Radius.circular(16)));
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _FinalSpotlightClipper oldClipper) =>
      oldClipper.spotlight != spotlight;
}

class _FinalSpotlightFrame extends StatelessWidget {
  final Rect rect;
  final double progress;

  const _FinalSpotlightFrame({required this.rect, required this.progress});

  @override
  Widget build(BuildContext context) {
    final Color primary = context.colors.primary;
    final double secondPulse = (progress + 0.5) % 1;
    return Stack(
      children: [
        _PulseRing(rect: rect, progress: progress, color: primary),
        _PulseRing(rect: rect, progress: secondPulse, color: primary),
        Positioned.fromRect(
          rect: rect.inflate(4),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: primary, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.55),
                    blurRadius: 20,
                    spreadRadius: 4,
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

class _PulseRing extends StatelessWidget {
  final Rect rect;
  final double progress;
  final Color color;

  const _PulseRing({
    required this.rect,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final double expansion = 9 + (progress * 28);
    return Positioned.fromRect(
      rect: rect.inflate(expansion),
      child: IgnorePointer(
        child: Opacity(
          opacity: (1 - progress).clamp(0, 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22 + expansion),
              border: Border.all(color: color, width: 3.2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.34),
                  blurRadius: 18,
                  spreadRadius: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
