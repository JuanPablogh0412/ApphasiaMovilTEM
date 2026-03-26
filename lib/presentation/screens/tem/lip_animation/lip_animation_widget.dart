import 'dart:async';
import 'dart:math' as math; // CHANGES: Para generar fases aleatorias de trill

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'lip_viseme.dart';
import 'lip_animation_engine.dart';
import 'lip_timeline.dart';
import 'lip_painter.dart';

// CHANGES: Added PlaybackState enum and exposed controller state publicly
// CHANGES: Added debug mode support and offsetMs parameter
// CHANGES: Extended with tongue animation timing support (v2.1 - Feb 2026)

/// Estados del reproductor de animación labial
enum PlaybackState {
  idle, // No iniciada
  playing, // Reproduciendo
  paused, // Pausada
  finished, // Finalizada
}

/// Widget principal de animación labial 2D para TEM
///
/// Módulo minimalista y paramétrico que anima visemas
/// en función de texto/sílabas con control temporal.
///
/// CHANGES: Ahora expone LipAnimationControllerState vía GlobalKey
/// para control externo (pause/resume/restart)
///
/// Uso básico:
/// ```dart
/// LipAnimationWidget(
///   text: 'mama',
///   durationPerSyllable: Duration(milliseconds: 800),
/// )
/// ```
///
/// Uso con control externo:
/// ```dart
/// final key = GlobalKey<LipAnimationControllerState>();
///
/// LipAnimationWidget(
///   key: key,
///   text: 'mama',
///   debug: true,
/// )
///
/// // Luego:
/// key.currentState?.pause();
/// key.currentState?.resume();
/// key.currentState?.restart();
/// ```

class LipAnimationWidget extends StatefulWidget {
  /// Texto a animar (palabra o frase)
  final String text;

  /// Duración por sílaba (default: 800ms)
  final Duration durationPerSyllable;

  /// Factor de elongación vocálica (default: 1.0)
  final double vowelStretchFactor;

  /// Color de los labios
  final Color lipColor;

  /// Si la animación debe repetirse en bucle
  final bool loop;

  /// CHANGES: Offset temporal en milisegundos (para sincronización externa)
  final int offsetMs;

  /// CHANGES: Modo debug (muestra puntos de control y barra de timeline)
  final bool debug;

  // ---- Campos para modo fromTimeline (esclavo del AudioPlayer) ----

  /// Timeline externa provista por [LipAnimationWidget.fromTimeline].
  /// Si es null, el widget genera la timeline desde [text].
  final LipTimeline? externalTimeline;

  /// Stream de posición del AudioPlayer (positionStream de just_audio).
  /// Solo se usa en modo [fromTimeline]. Si es null, el AnimationController
  /// corre de forma autónoma.
  final Stream<Duration>? audioPosition;

  const LipAnimationWidget({
    super.key,
    required this.text,
    this.durationPerSyllable = const Duration(milliseconds: 800),
    this.vowelStretchFactor = 1.0,
    this.lipColor = const Color(0xFFB71C1C),
    this.loop = false,
    this.offsetMs = 0,
    this.debug = false,
  }) : externalTimeline = null,
       audioPosition = null;

  /// Constructor nombrado para modo “esclavo del audio”.
  ///
  /// El [AnimationController] no corre autónomo: recibe la posición del
  /// [AudioPlayer] vía [audioPosition] y actualiza [controller.value]
  /// directamente, manteniendo labios y audio perfectamente sincronizados.
  ///
  /// Uso:
  /// ```dart
  /// LipAnimationWidget.fromTimeline(
  ///   timeline: LipTimeline.fromStimulusJson(jsonData),
  ///   audioPosition: audioPlayer.positionStream,
  /// )
  /// ```
  const LipAnimationWidget.fromTimeline({
    super.key,
    required LipTimeline timeline,
    required Stream<Duration> audioPositionStream,
    this.lipColor = const Color(0xFFB71C1C),
    this.debug = false,
    this.loop = false,
  }) : text = '',
       durationPerSyllable = const Duration(milliseconds: 800),
       vowelStretchFactor = 1.0,
       offsetMs = 0,
       externalTimeline = timeline,
       audioPosition = audioPositionStream;

  @override
  State<LipAnimationWidget> createState() => LipAnimationControllerState();
}

/// CHANGES: Renombrado y expuesto públicamente para control externo
///
/// API pública:
/// - pause(): Pausa la animación
/// - resume(): Reanuda la animación
/// - restart(): Reinicia desde el principio
/// - start(): Inicia/reinicia la animación (alias de restart)
/// - currentState: PlaybackState actual
///
/// CHANGES: Cambiado a TickerProviderStateMixin para permitir recreación de controllers
/// CHANGES: Añadido tracking de tiempo de evento para micro-animaciones (v2.1)
class LipAnimationControllerState extends State<LipAnimationWidget>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  late LipTimeline _timeline;
  Viseme _currentViseme = Visemes.neutral;
  PlaybackState _playbackState = PlaybackState.idle;

  // CHANGES: Estado de micro-animaciones de lengua (v2.1)
  Duration _currentEventStartTime = Duration.zero; // Inicio del evento activo
  double _trillPhase = 0.0; // Fase aleatoria del trill (radianes)

  // fromTimeline mode: suscripción al positionStream del AudioPlayer
  StreamSubscription<Duration>? _audioSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
  }

  @override
  void didUpdateWidget(LipAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Modo fromTimeline: reinicializar si la timeline externa cambió
    // (identidad del objeto, no contenido — cada nuevo estímulo crea una nueva
    // instancia de LipTimeline, así que esto detecta el cambio de estímulo)
    if (!identical(oldWidget.externalTimeline, widget.externalTimeline) &&
        widget.externalTimeline != null) {
      _initializeAnimation();
      return;
    }

    // Modo autónomo: reiniciar si cambian los parámetros de texto/duración
    if (oldWidget.text != widget.text ||
        oldWidget.durationPerSyllable != widget.durationPerSyllable ||
        oldWidget.vowelStretchFactor != widget.vowelStretchFactor) {
      _initializeAnimation();
    }
  }

  void _initializeAnimation() {
    // CHANGES: Disponer controller anterior si existe (evita error de múltiples tickers)
    _audioSubscription?.cancel();
    _controller?.dispose();

    if (widget.externalTimeline != null) {
      // ---- Modo fromTimeline: timeline provista externamente ----
      _timeline = widget.externalTimeline!;

      _controller = AnimationController(
        vsync: this,
        duration: _timeline.totalDuration,
      );

      // Suscribirse al stream del AudioPlayer y espejar su posición en el controller
      if (widget.audioPosition != null) {
        if (kDebugMode) {
          debugPrint(
            '[LipSync] Widget inicializado | '
            'timeline=${_timeline.events.length} eventos | '
            'total=${_timeline.totalDuration.inMilliseconds}ms',
          );
        }
        _audioSubscription = widget.audioPosition!.listen((position) {
          if (!mounted || _controller == null) return;
          final totalUs = _timeline.totalDuration.inMicroseconds;
          if (totalUs <= 0) return;
          final value = (position.inMicroseconds / totalUs).clamp(0.0, 1.0);
          _controller!.value = value;
          _updateVisemeFromController();
        });
        setState(() => _playbackState = PlaybackState.playing);
      }
      return;
    }

    // ---- Modo autónomo: generar timeline desde texto ----
    final engine = LipAnimationEngine(
      durationPerSyllable: widget.durationPerSyllable,
      vowelStretchFactor: widget.vowelStretchFactor,
    );

    // Generar timeline desde el texto
    _timeline = engine.generateTimeline(widget.text);

    // Configurar controller
    _controller = AnimationController(
      vsync: this,
      duration: _timeline.totalDuration,
    );

    // Listener para actualizar visema actual
    _controller!.addListener(_updateVisemeFromController);

    // Listener para bucle o reset
    _controller!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _playbackState = PlaybackState.finished;
        });

        if (widget.loop) {
          restart();
        } else {
          // Al terminar, volver a neutral
          setState(() {
            _currentViseme = Visemes.neutral;
          });
        }
      } else if (status == AnimationStatus.forward) {
        setState(() {
          _playbackState = PlaybackState.playing;
        });
      } else if (status == AnimationStatus.dismissed) {
        setState(() {
          _playbackState = PlaybackState.idle;
        });
      }
    });

    // Iniciar animación automáticamente
    start();
  }

  // Lógica de actualización del visema compartida entre modo autónomo y fromTimeline
  void _updateVisemeFromController() {
    if (_controller == null) return;
    final elapsed = Duration(
      microseconds:
          (_controller!.value * _timeline.totalDuration.inMicroseconds).round(),
    );

    // Aplicar offset temporal
    final currentTime = elapsed + Duration(milliseconds: widget.offsetMs);

    // CHANGES: Detectar cambio de evento para resetear timing de micro-animaciones (v2.1)
    final newViseme = _timeline.getVisemeAtTime(currentTime);

    // Si cambió el visema (nuevo evento)
    if (newViseme.name != _currentViseme.name) {
      if (kDebugMode) {
        debugPrint(
          '[LipSync] @${elapsed.inMilliseconds}ms  '
          '${_currentViseme.name} → ${newViseme.name}',
        );
      }
      // Buscar el evento activo para obtener su start time
      for (var event in _timeline.events) {
        if (currentTime >= event.startTime && currentTime <= event.endTime) {
          _currentEventStartTime = event.startTime;

          // CHANGES: Generar nueva fase aleatoria para trills (v2.1)
          if (newViseme.tongueVibrateEnabled) {
            _trillPhase = math.Random().nextDouble() * 2.0 * math.pi;
          }
          break;
        }
      }
    }

    setState(() {
      _currentViseme = newViseme;
    });
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // ==================== API PÚBLICA ====================

  /// Estado actual del reproductor
  PlaybackState get currentState => _playbackState;

  // CHANGES (v2.1.1): Exponer controller para AnimatedBuilder
  /// AnimationController para sincronización externa (ej: syllable highlighting)
  AnimationController? get controller => _controller;

  // CHANGES (v2.1.1): Exponer tiempo actual de animación
  /// Tiempo actual de la animación en milisegundos (considerando offset)
  int get currentTimeMs {
    if (_controller == null) return 0;
    final elapsed = Duration(
      microseconds:
          (_controller!.value * _timeline.totalDuration.inMicroseconds).round(),
    );
    final currentTime = elapsed + Duration(milliseconds: widget.offsetMs);
    return currentTime.inMilliseconds;
  }

  /// Inicia/reinicia la animación desde el principio
  void start() {
    _controller?.reset();
    _controller?.forward();
    setState(() {
      _playbackState = PlaybackState.playing;
    });
  }

  /// Reinicia la animación desde el principio (alias de start)
  void restart() => start();

  /// Pausa la animación
  void pause() {
    if (_playbackState == PlaybackState.playing) {
      _controller?.stop();
      setState(() {
        _playbackState = PlaybackState.paused;
      });
    }
  }

  /// Reanuda la animación desde donde se pausó
  void resume() {
    if (_playbackState == PlaybackState.paused) {
      _controller?.forward();
      setState(() {
        _playbackState = PlaybackState.playing;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calcular progreso para barra de timeline en debug
    final timelineProgress = _timeline.totalDuration.inMicroseconds > 0
        ? (_controller?.value ?? 0.0)
        : 0.0;

    // CHANGES: Calcular tiempo transcurrido del evento actual para micro-animaciones (v2.1)
    final elapsed = Duration(
      microseconds:
          ((_controller?.value ?? 0.0) * _timeline.totalDuration.inMicroseconds)
              .round(),
    );
    final currentTime = elapsed + Duration(milliseconds: widget.offsetMs);
    final elapsedEventMs =
        (currentTime - _currentEventStartTime).inMicroseconds / 1000.0;

    return CustomPaint(
      painter: LipPainter(
        viseme: _currentViseme,
        lipColor: widget.lipColor,
        debugMode: widget.debug,
        timelineProgress: widget.debug ? timelineProgress : null,
        // CHANGES: Pasar parámetros de micro-animación (v2.1)
        elapsedEventMs: elapsedEventMs.clamp(0.0, double.infinity),
        trillPhase: _trillPhase,
      ),
      size: Size.infinite,
    );
  }
}
