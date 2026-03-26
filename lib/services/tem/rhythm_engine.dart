import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../../data/models/tem/lip_timeline.dart';
import '../../data/models/tem/lip_viseme.dart';

// ---------------------------------------------------------------------------
//  Eventos del RhythmEngine
// ---------------------------------------------------------------------------

/// Clase base sellada para todos los eventos que emite el RhythmEngine.
sealed class RhythmEvent {}

/// El visema activo cambió — la UI debe actualizar la animación labial.
class VisemeChangeEvent extends RhythmEvent {
  final Viseme viseme;
  VisemeChangeEvent(this.viseme);
}

/// Se activó la sílaba de índice [syllableIndex] — resaltar en la UI.
class SyllableActivateEvent extends RhythmEvent {
  final int syllableIndex;
  SyllableActivateEvent(this.syllableIndex);
}

/// Clic de metrónomo (inicio de sílaba según onsets_ms).
/// El RhythmEngine reproduce el clic via un segundo AudioPlayer dedicado.
/// La vibración háptica fue eliminada del protocolo — se usa metrónomo audible.
class MetronomeClickEvent extends RhythmEvent {}

/// El audio terminó de reproducirse.
class PlaybackEndEvent extends RhythmEvent {}

// ---------------------------------------------------------------------------
//  RhythmEngine
// ---------------------------------------------------------------------------

/// Coordinador de audio + metrónomo + eventos de visema para TEM.
/// Emite [RhythmEvent] via [events] a medida que avanza el audio.
///
/// El patrón de metrónomo se DERIVA de [timeline.onsetsMs] — no se
/// recibe como parámetro externo.
///
/// Sprint 1 — implementación completa de play() con positionStream.
class RhythmEngine {
  final LipTimeline timeline;
  final AudioPlayer audioPlayer;

  /// Player secundario para el clic audible del metrónomo.
  /// Si es null no hay clic audible, pero se emiten [MetronomeClickEvent].
  /// El caller es responsable de inicializar la fuente de audio antes de
  /// pasar este player.
  final AudioPlayer? metronomePlayer;

  /// Offset en ms para compensar latencia del micrófono del dispositivo.
  /// Leído desde pacientes/{pacienteId}/calibracion.offset_ms (Sprint 3).
  final int offsetMs;

  final _controller = StreamController<RhythmEvent>.broadcast();

  // Suscripciones activas durante la reproducción
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  /// Índice de la última sílaba procesada (-1 = ninguna).
  int _lastSyllableIndex = -1;

  RhythmEngine({
    required this.timeline,
    required this.audioPlayer,
    this.metronomePlayer,
    this.offsetMs = 0,
  });

  /// El patrón de metrónomo se deriva de los onsets del timeline.
  /// Equivale exactamente a los tiempos de inicio de cada sílaba.
  List<int> get hapticPatternMs => List<int>.from(timeline.onsetsMs);

  /// Stream de eventos de ritmo que la UI escucha.
  Stream<RhythmEvent> get events => _controller.stream;

  /// Inicia la reproducción coordinada audio + metrónomo + visemas.
  ///
  /// Escucha [audioPlayer.positionStream] y emite [MetronomeClickEvent],
  /// [SyllableActivateEvent] y [VisemeChangeEvent] en los tiempos
  /// correctos según el [timeline]. Emite [PlaybackEndEvent] al finalizar.
  Future<void> play() async {
    if (_controller.isClosed) return;

    // Reiniciar tracking de sílabas
    _lastSyllableIndex = -1;

    // Cancelar suscripciones anteriores si las hay
    await _positionSub?.cancel();
    await _stateSub?.cancel();

    final onsetsMs = timeline.onsetsMs;

    // Suscribirse al stream de posición del AudioPlayer
    _positionSub = audioPlayer.positionStream.listen((position) {
      if (_controller.isClosed) return;

      final posMs = position.inMilliseconds - offsetMs;

      // ---- Detectar cambio de sílaba ----
      int currentIndex = -1;
      for (int i = onsetsMs.length - 1; i >= 0; i--) {
        if (posMs >= onsetsMs[i]) {
          currentIndex = i;
          break;
        }
      }

      if (currentIndex != _lastSyllableIndex && currentIndex >= 0) {
        _lastSyllableIndex = currentIndex;

        // Emitir clic de metrónomo
        _controller.add(MetronomeClickEvent());

        // Reproducir clic audible si hay player configurado
        final mp = metronomePlayer;
        if (mp != null) {
          mp.seek(Duration.zero).then((_) => mp.play());
        }

        // Emitir activación de sílaba
        _controller.add(SyllableActivateEvent(currentIndex));
      }

      // ---- Emitir visema activo continuamente ----
      _controller.add(VisemeChangeEvent(timeline.getVisemeAtTime(position)));
    });

    // Suscribirse al estado del player para detectar fin de reproducción
    _stateSub = audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!_controller.isClosed) {
          _controller.add(PlaybackEndEvent());
        }
        _positionSub?.cancel();
        _stateSub?.cancel();
      }
    });

    // Iniciar reproducción
    await audioPlayer.play();
  }

  /// Pausa la reproducción.
  Future<void> pause() async {
    await audioPlayer.pause();
  }

  /// Detiene y reinicia a posición 0.
  Future<void> stop() async {
    await _positionSub?.cancel();
    await _stateSub?.cancel();
    await audioPlayer.stop();
    _lastSyllableIndex = -1;
  }

  /// Libera recursos.
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _controller.close();
    audioPlayer.dispose();
    metronomePlayer?.dispose();
  }
}
