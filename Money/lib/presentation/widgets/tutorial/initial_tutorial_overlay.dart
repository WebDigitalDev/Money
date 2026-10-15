import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:money/money.dart';

class InitialTutorialOverlay extends StatefulWidget {
  final VoidCallback onStart;
  final bool playAudio;
  final bool requireUserAction;

  const InitialTutorialOverlay({
    super.key,
    required this.onStart,
    this.playAudio = true,
    this.requireUserAction = false,
  });

  @override
  State<InitialTutorialOverlay> createState() => _InitialTutorialOverlayState();
}

class _InitialTutorialOverlayState extends State<InitialTutorialOverlay>
    with SingleTickerProviderStateMixin {
  static const String _audioAsset = 'assets/audios/1.mp3';
  static const Duration _expectedDuration = Duration(milliseconds: 12487);
  static const Duration _appearanceDelay = Duration(seconds: 4);
  static const Duration _speechDelayAfterEntrance = Duration(milliseconds: 720);
  static const String _fullText =
      'Olá, Seja bem-vindo! Eu sou a Money, uma assistente virtual financeira.\n'
      'Percebi aqui que esse é seu primeiro acesso, então vou iniciar uma demostração do sistema.\n'
      'Clique em começar que já iniciaremos.';

  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: true,
    androidApplyAudioAttributes: true,
    handleAudioSessionActivation: true,
  );
  late final AnimationController _entranceController;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  Timer? _autoplayGuard;
  Timer? _entranceDelay;
  Timer? _playbackDelay;

  Duration _duration = _expectedDuration;
  String _visibleText = '';
  bool _audioLoaded = false;
  bool _speechCompleted = false;
  bool _manualPlaybackRequired = false;
  bool _entranceStarted = false;

  @override
  void initState() {
    super.initState();
    _manualPlaybackRequired = widget.playAudio && widget.requireUserAction;
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _entranceDelay = Timer(_appearanceDelay, () {
      if (!mounted) return;
      _entranceStarted = true;
      _entranceController.forward();
      _schedulePlayback();
    });
    _positionSubscription = _player
        .createPositionStream(
          steps: 1200,
          minPeriod: const Duration(milliseconds: 16),
          maxPeriod: const Duration(milliseconds: 32),
        )
        .listen(_updateText);
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerState,
    );
    _errorSubscription = _player.errorStream.listen((_) {
      if (kIsWeb && _audioLoaded && _player.position == Duration.zero) {
        _showManualPlayback();
        return;
      }
      _showAudioUnavailable();
    });

    if (widget.playAudio) {
      unawaited(_loadAndPlay());
    } else {
      _visibleText = _fullText;
      _speechCompleted = true;
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _autoplayGuard?.cancel();
    _entranceDelay?.cancel();
    _playbackDelay?.cancel();
    unawaited(_positionSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _loadAndPlay() async {
    try {
      await _configureSpeechAudioSession();
      final Duration? loadedDuration = await _player.setAudioSource(
        AudioSource.asset(_audioAsset),
      );
      if (!mounted) return;

      setState(() {
        _duration = loadedDuration ?? _expectedDuration;
        _audioLoaded = true;
      });
      _schedulePlayback();
    } catch (_) {
      _showAudioUnavailable();
    }
  }

  Future<void> _configureSpeechAudioSession() async {
    final AudioSession session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    // 1.0 preserva o volume original do MP3 sem ganho ou amplificação.
    await _player.setVolume(1.0);
  }

  void _schedulePlayback() {
    if (widget.requireUserAction ||
        !_entranceStarted ||
        !_audioLoaded ||
        _playbackDelay != null) {
      return;
    }

    _playbackDelay = Timer(_speechDelayAfterEntrance, () {
      if (!mounted) return;
      _playbackDelay = null;
      unawaited(_startPlayback());
    });
  }

  Future<void> _startPlayback({bool restart = false}) async {
    if (!_audioLoaded) return;

    try {
      if (restart || _player.processingState == ProcessingState.completed) {
        // No navegador, o player pode permanecer com playing=true depois do
        // evento ended. stop() limpa esse estado antes de voltar ao início.
        await _player.stop();
        await _player.seek(Duration.zero);
      }

      if (mounted) {
        setState(() {
          _visibleText = '';
          _speechCompleted = false;
          _manualPlaybackRequired = false;
        });
      }

      _guardPlaybackStart();
      await _player.play();
    } catch (_) {
      _showManualPlayback();
    }
  }

  void _guardPlaybackStart() {
    _autoplayGuard?.cancel();
    final Duration startingPosition = _player.position;
    _autoplayGuard = Timer(const Duration(milliseconds: 1500), () {
      final Duration progress = _player.position - startingPosition;
      if (!mounted || progress >= const Duration(milliseconds: 400)) return;
      _showManualPlayback();
    });
  }

  void _showManualPlayback() {
    if (!mounted) return;
    _autoplayGuard?.cancel();
    unawaited(_player.pause());
    setState(() {
      _visibleText = '';
      _speechCompleted = false;
      _manualPlaybackRequired = true;
    });
  }

  void _showAudioUnavailable() {
    if (!mounted) return;
    setState(() {
      _visibleText = _fullText;
      _speechCompleted = true;
      _manualPlaybackRequired = false;
    });
  }

  void _handlePlayerState(PlayerState state) {
    if (!mounted) return;

    final bool completed = state.processingState == ProcessingState.completed;
    setState(() {
      if (completed) {
        _autoplayGuard?.cancel();
        _visibleText = _fullText;
        _speechCompleted = true;
        _manualPlaybackRequired = false;
      }
    });
  }

  void _updateText(Duration position) {
    if (!mounted || _manualPlaybackRequired) return;
    final bool completedByPosition = position >= _duration;
    final String nextText = completedByPosition
        ? _fullText
        : _textForPosition(position);
    if (nextText == _visibleText &&
        (!completedByPosition || _speechCompleted)) {
      return;
    }
    setState(() {
      _visibleText = nextText;
      if (completedByPosition) {
        _autoplayGuard?.cancel();
        _speechCompleted = true;
        _manualPlaybackRequired = false;
      }
    });
  }

  String _textForPosition(Duration position) {
    final int totalMicroseconds = _duration.inMicroseconds > 0
        ? _duration.inMicroseconds
        : _expectedDuration.inMicroseconds;
    final double progress = (position.inMicroseconds / totalMicroseconds).clamp(
      0,
      1,
    );
    final int characterCount = (_fullText.length * progress).ceil().clamp(
      0,
      _fullText.length,
    );
    return _fullText.substring(0, characterCount);
  }

  Future<void> _replaySpeech() async {
    if (!widget.playAudio) {
      setState(() {
        _visibleText = '';
        _speechCompleted = false;
        _manualPlaybackRequired = false;
      });
      return;
    }

    if (!_audioLoaded) {
      setState(() {
        _visibleText = '';
        _speechCompleted = false;
        _manualPlaybackRequired = false;
      });
      await _loadAndPlay();
      return;
    }

    await _startPlayback(restart: true);
  }

  void _finishIntroduction() {
    unawaited(_player.stop());
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return PopScope<void>(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: ModalBarrier(
                  dismissible: false,
                  color: Colors.black.withValues(alpha: 0.42),
                  semanticsLabel: 'Tutorial em andamento',
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool desktop = kIsWeb && constraints.maxWidth >= 1024;
                  return desktop
                      ? _buildDesktop(context, constraints, reduceMotion)
                      : _buildMobile(context, constraints, reduceMotion);
                },
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
    const double panelHeight = 238;
    final double imageHeight = (constraints.maxHeight * 0.54).clamp(
      300.0,
      480.0,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -18,
          bottom: panelHeight * 0.34,
          child: _buildEntranceAnimation(
            key: const ValueKey('tutorial_character_entrance'),
            reduceMotion: reduceMotion,
            start: 0,
            end: 0.68,
            beginOffset: const Offset(38, 64),
            beginScale: 0.92,
            alignment: Alignment.bottomRight,
            child: IgnorePointer(
              child: Image.asset(
                AppImages.virtualAssistant,
                height: imageHeight,
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: _buildEntranceAnimation(
              key: const ValueKey('tutorial_panel_entrance'),
              reduceMotion: reduceMotion,
              start: 0.18,
              end: 1,
              beginOffset: const Offset(0, 48),
              beginScale: 0.9,
              curve: Curves.easeOutBack,
              alignment: Alignment.bottomCenter,
              child: _buildDialoguePanel(
                context,
                height: panelHeight,
                maxWidth: 520,
                textSize: constraints.maxWidth < 360 ? 13.4 : 14.4,
                mobile: true,
              ),
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
    final double imageHeight = (constraints.maxHeight * 0.76).clamp(
      460.0,
      700.0,
    );
    final double characterRight = math.max(
      24,
      ((constraints.maxWidth - 780) / 2) - 250,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          key: const ValueKey('tutorial_desktop_character_position'),
          right: characterRight,
          bottom: -42,
          child: _buildEntranceAnimation(
            key: const ValueKey('tutorial_character_entrance'),
            reduceMotion: reduceMotion,
            start: 0,
            end: 0.68,
            beginOffset: const Offset(58, 76),
            beginScale: 0.92,
            alignment: Alignment.bottomRight,
            child: IgnorePointer(
              child: Image.asset(
                AppImages.virtualAssistant,
                height: imageHeight,
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(42, 32, 42, 42),
            child: _buildEntranceAnimation(
              key: const ValueKey('tutorial_panel_entrance'),
              reduceMotion: reduceMotion,
              start: 0.18,
              end: 1,
              beginOffset: const Offset(0, 54),
              beginScale: 0.9,
              curve: Curves.easeOutBack,
              alignment: Alignment.bottomCenter,
              child: _buildDialoguePanel(
                context,
                height: 216,
                maxWidth: 780,
                textSize: 17,
                mobile: false,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEntranceAnimation({
    required Key key,
    required Widget child,
    required bool reduceMotion,
    required double start,
    required double end,
    required Offset beginOffset,
    required double beginScale,
    required Alignment alignment,
    Curve curve = Curves.easeOutCubic,
  }) {
    if (reduceMotion) {
      return Opacity(key: key, opacity: 1, child: child);
    }

    return AnimatedBuilder(
      animation: _entranceController,
      child: child,
      builder: (context, child) {
        final double rawProgress =
            ((_entranceController.value - start) / (end - start)).clamp(0, 1);
        final double motionProgress = curve.transform(rawProgress);
        final double opacity = Curves.easeOut.transform(rawProgress);

        return Opacity(
          key: key,
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(
              beginOffset.dx * (1 - motionProgress),
              beginOffset.dy * (1 - motionProgress),
            ),
            child: Transform.scale(
              scale: beginScale + ((1 - beginScale) * motionProgress),
              alignment: alignment,
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
    final Color surface = context.colors.surface;
    final Color textColor = context.colors.textPrimary;
    final Color neutralButton = context.isDark
        ? const Color(0xFF282B29)
        : const Color(0xFFF0F2F1);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Apresentação da assistente Money. $_fullText',
      child: ConstrainedBox(
        key: const ValueKey('tutorial_dialogue_panel'),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface,
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
                            fullText: _fullText,
                            visibleText: _visibleText,
                            color: textColor,
                            preferredFontSize: textSize,
                          ),
                        ),
                        const SizedBox(height: 7),
                        SizedBox(
                          height: 44,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.82,
                                      end: 1,
                                    ).animate(animation),
                                    alignment: Alignment.bottomCenter,
                                    child: child,
                                  ),
                                ),
                            child: _speechCompleted
                                ? Row(
                                    key: const ValueKey(
                                      'tutorial_completed_controls',
                                    ),
                                    children: [
                                      IconButton(
                                        key: const ValueKey(
                                          'tutorial_audio_button',
                                        ),
                                        onPressed: _replaySpeech,
                                        tooltip: 'Ouvir novamente',
                                        style: IconButton.styleFrom(
                                          backgroundColor: neutralButton,
                                          foregroundColor:
                                              context.colors.textSecondary,
                                          fixedSize: const Size.square(42),
                                          shape: const CircleBorder(),
                                          side: BorderSide(
                                            color: context.colors.divider,
                                            width: 1,
                                          ),
                                        ),
                                        icon: TutorialReplayAudioIcon(
                                          color: context.colors.textSecondary,
                                        ),
                                      ),
                                      const Spacer(),
                                      FilledButton.icon(
                                        key: const ValueKey(
                                          'tutorial_start_button',
                                        ),
                                        onPressed: _finishIntroduction,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: primary,
                                          foregroundColor: Colors.white,
                                          minimumSize: Size(
                                            mobile ? 126 : 156,
                                            44,
                                          ),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: mobile ? 16 : 22,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                          ),
                                        ),
                                        iconAlignment: IconAlignment.end,
                                        icon: const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 20,
                                        ),
                                        label: const Text(
                                          'COMEÇAR',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : _manualPlaybackRequired
                                ? Align(
                                    key: const ValueKey(
                                      'tutorial_manual_audio_control',
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      key: const ValueKey(
                                        'tutorial_manual_audio_button',
                                      ),
                                      onPressed: _audioLoaded
                                          ? _replaySpeech
                                          : null,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: primary,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            context.colors.disabled,
                                        minimumSize: const Size(190, 42),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                        ),
                                      ),
                                      icon: _audioLoaded
                                          ? const Icon(
                                              Icons.volume_up_rounded,
                                              size: 19,
                                            )
                                          : const SizedBox.square(
                                              dimension: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                      label: Text(
                                        _audioLoaded
                                            ? 'OUVIR APRESENTAÇÃO'
                                            : 'CARREGANDO ÁUDIO',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.expand(
                                    key: ValueKey(
                                      'tutorial_completed_controls_hidden',
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
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.32),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
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

class TutorialReplayAudioIcon extends StatelessWidget {
  final Color color;

  const TutorialReplayAudioIcon({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 27,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ReplayArrowsPainter(color)),
          ),
          Icon(Icons.volume_up_rounded, size: 17, color: color),
        ],
      ),
    );
  }
}

class _ReplayArrowsPainter extends CustomPainter {
  final Color color;

  const _ReplayArrowsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Rect arcBounds = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);

    const double upperStart = 2.72;
    const double upperSweep = 2.82;
    const double lowerStart = -0.42;
    const double lowerSweep = 2.9;
    canvas.drawArc(arcBounds, upperStart, upperSweep, false, paint);
    canvas.drawArc(arcBounds, lowerStart, lowerSweep, false, paint);

    _drawArrowHead(canvas, arcBounds, upperStart + upperSweep, paint);
    _drawArrowHead(canvas, arcBounds, lowerStart + lowerSweep, paint);
  }

  void _drawArrowHead(
    Canvas canvas,
    Rect bounds,
    double endAngle,
    Paint paint,
  ) {
    final Offset center = bounds.center;
    final double radius = bounds.width / 2;
    final Offset tip = Offset(
      center.dx + (radius * math.cos(endAngle)),
      center.dy + (radius * math.sin(endAngle)),
    );
    final double direction = endAngle + (math.pi / 2);
    const double headLength = 4.2;
    const double spread = 0.68;
    final Offset first = Offset(
      tip.dx - (headLength * math.cos(direction - spread)),
      tip.dy - (headLength * math.sin(direction - spread)),
    );
    final Offset second = Offset(
      tip.dx - (headLength * math.cos(direction + spread)),
      tip.dy - (headLength * math.sin(direction + spread)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(first.dx, first.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(second.dx, second.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ReplayArrowsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class TutorialFittedTranscript extends StatelessWidget {
  final String fullText;
  final String visibleText;
  final Color color;
  final double preferredFontSize;

  const TutorialFittedTranscript({
    super.key,
    required this.fullText,
    required this.visibleText,
    required this.color,
    required this.preferredFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final TextScaler textScaler = MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: 1.15);
        final TextDirection textDirection = Directionality.of(context);
        double fontSize = preferredFontSize;
        TextStyle style = _style(fontSize);

        while (fontSize > 10.5) {
          final TextPainter painter = TextPainter(
            text: TextSpan(text: fullText, style: style),
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout(maxWidth: constraints.maxWidth);
          if (painter.height <= constraints.maxHeight) break;
          fontSize -= 0.25;
          style = _style(fontSize);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0,
              child: Text(
                fullText,
                style: style,
                textScaler: textScaler,
                overflow: TextOverflow.clip,
              ),
            ),
            Align(
              alignment: Alignment.topLeft,
              child: ExcludeSemantics(
                child: Text(
                  visibleText,
                  key: const ValueKey('tutorial_visible_text'),
                  style: style,
                  textScaler: textScaler,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  TextStyle _style(double fontSize) => TextStyle(
    color: color,
    fontSize: fontSize,
    height: 1.28,
    fontWeight: FontWeight.w500,
  );
}
