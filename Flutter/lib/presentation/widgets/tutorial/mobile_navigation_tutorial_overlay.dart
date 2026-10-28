import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:money/money.dart';

class MobileNavigationTutorialOverlay extends StatefulWidget {
  final TutorialGuideController controller;

  const MobileNavigationTutorialOverlay({super.key, required this.controller});

  @override
  State<MobileNavigationTutorialOverlay> createState() =>
      _MobileNavigationTutorialOverlayState();
}

class _MobileNavigationTutorialOverlayState
    extends State<MobileNavigationTutorialOverlay>
    with TickerProviderStateMixin {
  static const String _audioAsset = 'assets/audios/mob0.mp3';
  static const Duration _expectedDuration = Duration(milliseconds: 13322);
  static const String _script =
      'Como você está com layout mobile, para abrir o menu das páginas, basta clicar no botão superior ou deslizar da direita para esquerda que assim será exebido o menu de opções.\n'
      'Agora vamos continuar';

  final AudioPlayer _player = AudioPlayer(
    handleInterruptions: true,
    androidApplyAudioAttributes: true,
    handleAudioSessionActivation: true,
  );
  late final AnimationController _pulseController;
  late final AnimationController _swipeController;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  Timer? _targetRefreshTimer;
  Timer? _playbackGuard;
  Timer? _fallbackOpenTimer;
  Timer? _fallbackCloseTimer;
  Timer? _fallbackFinishTimer;

  Duration _duration = _expectedDuration;
  Rect? _menuButtonRect;
  bool _initialized = false;
  bool _audioLoaded = false;
  bool _menuOpened = false;
  bool _continuationStarted = false;
  bool _finished = false;
  bool _fallbackRunning = false;

  bool get _highlightMenuButton => !_menuOpened && !_continuationStarted;
  bool get _showSwipe => _menuOpened && !_continuationStarted;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
    _targetRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _refreshMenuButtonRect(),
    );
    _positionSubscription = _player
        .createPositionStream(
          steps: 900,
          minPeriod: const Duration(milliseconds: 16),
          maxPeriod: const Duration(milliseconds: 32),
        )
        .listen(_handlePosition);
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerState,
    );
    _errorSubscription = _player.errorStream.listen(
      (_) => _handlePlaybackUnavailable(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshMenuButtonRect();
    });
    unawaited(_loadAndPlay());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _swipeController.dispose();
    _targetRefreshTimer?.cancel();
    _playbackGuard?.cancel();
    _fallbackOpenTimer?.cancel();
    _fallbackCloseTimer?.cancel();
    _fallbackFinishTimer?.cancel();
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
        AudioSource.asset(_audioAsset),
      );
      if (!mounted) return;
      _duration = loadedDuration ?? _expectedDuration;
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

  void _handlePosition(Duration position) {
    if (!mounted || _duration <= Duration.zero || _fallbackRunning) return;
    final double progress = (position.inMicroseconds / _duration.inMicroseconds)
        .clamp(0, 1);
    final int characterCount = (_script.length * progress).ceil().clamp(
      0,
      _script.length,
    );
    if (!_menuOpened && characterCount >= _after(_script, 'botão superior')) {
      _openMenuAndShowSwipe();
    }
    if (!_continuationStarted &&
        characterCount >= _before(_script, 'Agora vamos continuar')) {
      _startContinuation();
    }
  }

  void _handlePlayerState(PlayerState state) {
    if (!mounted || state.processingState != ProcessingState.completed) return;
    _playbackGuard?.cancel();
    _startContinuation();
    _finishNavigationTutorial();
  }

  void _openMenuAndShowSwipe() {
    if (!mounted || _menuOpened || _continuationStarted) return;
    _swipeController
      ..reset()
      ..repeat();
    setState(() {
      _menuOpened = true;
      _menuButtonRect = null;
    });
    widget.controller.openMobileSidebar();
  }

  void _startContinuation() {
    if (!mounted || _continuationStarted) return;
    _swipeController.stop();
    setState(() => _continuationStarted = true);
    widget.controller.closeMobileSidebar();
  }

  void _finishNavigationTutorial() {
    if (_finished) return;
    _finished = true;
    widget.controller.beginFinancialWalkthrough();
  }

  void _handlePlaybackUnavailable() {
    if (!mounted || _fallbackRunning || _finished) return;
    _fallbackRunning = true;
    unawaited(_player.stop());
    _fallbackOpenTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) _openMenuAndShowSwipe();
    });
    _fallbackCloseTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) _startContinuation();
    });
    _fallbackFinishTimer = Timer(const Duration(milliseconds: 3450), () {
      if (mounted) _finishNavigationTutorial();
    });
  }

  int _before(String text, String fragment) {
    final int index = text.indexOf(fragment);
    return index < 0 ? text.length : index;
  }

  int _after(String text, String fragment) {
    final int index = text.indexOf(fragment);
    return index < 0 ? text.length : index + fragment.length;
  }

  void _refreshMenuButtonRect() {
    if (!mounted || !_highlightMenuButton) return;
    final RenderObject? overlayObject = context.findRenderObject();
    final RenderObject? targetObject = widget
        .controller
        .mobileSidebarMenuButtonKey
        .currentContext
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
    final Rect overlayBounds = Offset.zero & overlayObject.size;
    final Rect next = ((targetGlobal - overlayGlobal) & targetObject.size)
        .inflate(8)
        .intersect(overlayBounds);
    if (_menuButtonRect == next) return;
    setState(() => _menuButtonRect = next);
  }

  @override
  Widget build(BuildContext context) {
    final Rect? spotlight = _highlightMenuButton ? _menuButtonRect : null;
    return PopScope<void>(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: _MobileMenuOutsideClipper(spotlight),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.46)),
              ),
            ),
            const ModalBarrier(
              dismissible: false,
              color: Colors.transparent,
              semanticsLabel: 'Apresentação do menu de páginas',
            ),
            if (spotlight != null)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => _MobileMenuButtonPulse(
                  rect: spotlight,
                  progress: _pulseController.value,
                ),
              ),
            if (_showSwipe)
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      _SwipeRightIndicator(
                        animation: _swipeController,
                        availableSize: constraints.biggest,
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

class _MobileMenuOutsideClipper extends CustomClipper<Path> {
  final Rect? spotlight;

  const _MobileMenuOutsideClipper(this.spotlight);

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
  bool shouldReclip(covariant _MobileMenuOutsideClipper oldClipper) =>
      oldClipper.spotlight != spotlight;
}

class _MobileMenuButtonPulse extends StatelessWidget {
  final Rect rect;
  final double progress;

  const _MobileMenuButtonPulse({required this.rect, required this.progress});

  @override
  Widget build(BuildContext context) {
    final Color primary = context.colors.primary;
    final double expansion = 4 + (progress * 16);
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect.inflate(expansion),
          child: IgnorePointer(
            child: Opacity(
              opacity: (1 - progress).clamp(0, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18 + expansion),
                  border: Border.all(color: primary, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.38),
                      blurRadius: 18,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: rect.inflate(3),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: primary, width: 2.6),
              ),
            ),
          ),
        ),
        Positioned(
          left: math.max(8, rect.left),
          top: rect.bottom + 10,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                child: Text(
                  'MENU DE PÁGINAS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.25,
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

class _SwipeRightIndicator extends StatelessWidget {
  final Animation<double> animation;
  final Size availableSize;

  const _SwipeRightIndicator({
    required this.animation,
    required this.availableSize,
  });

  @override
  Widget build(BuildContext context) {
    final double width = math.min(availableSize.width - 44, 310);
    return Positioned(
      left: (availableSize.width - width) / 2,
      bottom: 138,
      width: width,
      height: 82,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double fingerSize = 50;
            final double travel = constraints.maxWidth - fingerSize;
            return Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int index = 0; index < 4; index++)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(
                          alpha: 0.24 + (index * 0.09),
                        ),
                        size: 32,
                      ),
                  ],
                ),
                AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final double progress = animation.value;
                    final double opacity =
                        0.32 + (math.sin(math.pi * progress) * 0.48);
                    return Positioned(
                      left: travel * progress,
                      child: Opacity(
                        opacity: opacity.clamp(0, 1),
                        child: Container(
                          width: fingerSize,
                          height: fingerSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.44),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.22),
                                blurRadius: 18,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.touch_app_rounded,
                            color: Colors.white.withValues(alpha: 0.82),
                            size: 29,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
