import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../../../services/tem/narration_service.dart';
import '../../widgets/mute_button.dart';
import '../../widgets/voice_transition_overlay.dart';
import '../../viewmodels/tem/tem_session_viewmodel.dart';
import 'speaking_indicator.dart';
import 'syllable_highlight_widget.dart';
import 'tem_page_header.dart';
import 'tem_session_summary_screen.dart';
import 'tem_video_player_widget.dart';

/// Fuente de audio en memoria para el clic del metrónomo.
///
/// just_audio NO soporta `data:` URIs en Android/iOS (ExoPlayer/AVFoundation
/// los rechazan silenciosamente), así que servimos los bytes WAV via
/// [StreamAudioSource], que sí funciona en todas las plataformas.
class _ClickAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _ClickAudioSource(this._bytes) : super(tag: 'metro_click');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

/// Pantalla de ejercicio activo TEM — protocolo MIT multiNivel.
///
/// **Nivel 1 — 5 pasos:**
/// Paso 1 — ESCUCHA:     App reproduce audio 2×.  Sin grabación.
/// Paso 2 — UNÍSONO:     Paciente canta junto al audio 4×.  Graba 4 audios.
/// Paso 3 — COMPLETION:  Audio se silencia a la mitad; paciente completa 4×.
/// Paso 4 — REPETICIÓN:  Paciente escucha 1× y luego repite solo.
/// Paso 5 — PREGUNTA:    Muestra la pregunta; paciente responde.
///
/// **Nivel 2 — 4 pasos (con retroceso y pausa 6 s):**
/// Paso 1 — INTRODUCCIÓN:           App entona estímulo 2× con golpeteo.
/// Paso 2 — UNÍSONO DESVANECER:     Audio + desvanecimiento a mitad, 2-4 reps.
/// Paso 3 — REPETICIÓN CON PAUSA:   Audio → 6 s pausa → paciente solo.
/// Paso 4 — PREGUNTA CON PAUSA:     6 s pausa → pregunta texto → respuesta.
///
/// Todo el flujo es automático (guiado por la app).
/// El backend Python evalúa los audios.
class TemExerciseScreen extends StatefulWidget {
  const TemExerciseScreen({super.key, this.narration}) : args = const {};
  const TemExerciseScreen.withArgs({
    super.key,
    required this.args,
    this.narration,
  });

  final Map<String, dynamic> args;

  /// Servicio de narración TTS (opcional, inyectado desde PreSession).
  final NarrationService? narration;

  @override
  State<TemExerciseScreen> createState() => _TemExerciseScreenState();
}

class _TemExerciseScreenState extends State<TemExerciseScreen> {
  static const _bgColor = Color(0xFFFFF7F2);
  static const _accentColor = Color(0xFFF48A63);

  // ── Audio principal ────────────────────────────────────────────────
  // handleInterruptions: false → just_audio NO reacciona a eventos de foco.
  // handleAudioSessionActivation: false → play() NO llama
  //   audioSession.setActive(true), que internamente ejecuta
  //   requestAudioFocus(AUDIOFOCUS_GAIN).  Sin esto, cada play() robaba el
  //   AudioFocus al paquete record, cuyo AudioRecorder nativo pausa la
  //   grabación ante CUALQUIER tipo de AUDIOFOCUS_LOSS.
  final _audioPlayer = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  String? _loadedAudioUrl;

  // ── Metrónomo ──────────────────────────────────────────────────────
  AudioPlayer? _metronomePlayer;
  Uint8List? _clickBytes;
  StreamSubscription<dynamic>? _metronome;
  final List<Timer> _clickTimers = [];

  // ── Voice transition overlay ─────────────────────────────────────
  bool _showVoiceTransition = false;
  String _transitionKey = '';
  String _transitionLabel = '';
  IconData _transitionIcon = Icons.music_note_rounded;

  // ── Estado visual del paso en curso ───────────────────────────────
  /// Paso 1: cuántas reproducciones van (0, 1, 2).
  int _paso1Plays = 0;

  /// Pasos 2/3: repetición actual 1-4.
  int _currentRepetition = 0;

  /// Paso 4: ¿ya terminó la fase de escucha?
  bool _step4ListenDone = false;

  // ── Pausa de 6 s (Nivel 2 pasos 3-4) ─────────────────────────
  bool _pauseTimerActive = false;
  int _pauseTimerTotal = 6;
  int _pauseTimerRemaining = 6;

  // ── Flags de retroceso inline N3 ─────────────────────────────
  bool _n3P1NeedRetroceso = false;
  bool _n3P3NeedRetroceso = false;

  // ── Video player del estímulo ─────────────────────────────────
  final _videoPlayerKey = GlobalKey<TemVideoPlayerWidgetState>();

  /// Campo Firestore que determina qué video mostrar.
  /// Cambia entre pasos N3: 'video_url', 'video_url_sprechgesang', 'video_url_habla_normal'.
  String _currentVideoField = 'video_url';

  /// El micrófono está abierto.
  bool _isRecording = false;

  /// Esperando respuesta del backend.
  bool _isEvaluating = false;

  /// Paso completado — esperando que el usuario pulse Continuar.
  bool _waitingForContinue = false;

  /// Indica si el paso fue aprobado (true) o no (false) — informará a _onContinuePressed.
  bool _lastStepPassed = true;

  /// Texto de instrucción que sobreescribe al del ViewModel.
  String? _instructionOverride;

  /// Bytes de la imagen del estímulo actual — sólo móvil (null en web).
  Uint8List? _resolvedImageBytes;

  /// URL HTTPS de la imagen del estímulo actual — sólo web (null en móvil).
  String? _resolvedImageUrl;

  /// gs:// URL que produjo la imagen resuelta — para detectar cambios.
  String? _lastImageSourceUrl;

  // ══════════════════════════════════════════════════════════════════
  // Ciclo de vida
  // ══════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    // Misma configuración que _audioPlayer — ver comentario arriba.
    _metronomePlayer = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // En iOS, AVAudioSession necesita la categoría playAndRecord para que
      // grabación y reproducción funcionen simultáneamente.
      // En Android: ya NO activamos la sesión aquí — los players usan
      //   handleAudioSessionActivation:false, así que play() nunca llama
      //   setActive(true) ni requestAudioFocus(). Esto permite que el
      //   paquete record mantenga su AudioFocus durante toda la grabación.
      try {
        final session = await AudioSession.instance;
        await session.configure(
          AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth,
            avAudioSessionMode: AVAudioSessionMode.defaultMode,
            androidAudioAttributes: const AndroidAudioAttributes(
              contentType: AndroidAudioContentType.music,
              flags: AndroidAudioFlags.none,
              usage: AndroidAudioUsage.media,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
            androidWillPauseWhenDucked: false,
          ),
        );
        // Activar sesión de audio — imprescindible en iOS para playAndRecord.
        // En Android esto solicita AUDIOFOCUS desde audio_session, pero como
        // los AudioPlayers no volverán a llamar setActive(true), el recorder
        // tomará el foco una sola vez y lo mantendrá sin interrupción.
        await session.setActive(true);
      } catch (e) {
        debugPrint('[AudioSession] configure error: $e');
      }
      _clickBytes = _generateClickBytes();
      debugPrint('[INIT] calling _loadAudio + _startVoiceTransition');
      await _loadAudio();
      _startVoiceTransition();
    });
  }

  @override
  void dispose() {
    _metronome?.cancel();
    _cancelClickTimers();
    _metronomePlayer?.dispose();
    _audioPlayer.dispose();
    // Video player se dispone a sí mismo vía su State.dispose()
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════
  // Audio helpers
  // ══════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════
  // Helpers de timing por tipo de audio (N3)
  // ══════════════════════════════════════════════════════════════════

  /// Devuelve los onsets_ms del audio activo según _currentVideoField.
  List<int> _getCurrentOnsetsMs(Map<String, dynamic>? stim) {
    if (stim == null) return [];
    final field = _currentVideoField == 'video_url_sprechgesang'
        ? 'onsets_ms_sprechgesang'
        : _currentVideoField == 'video_url_habla_normal'
        ? 'onsets_ms_habla_normal'
        : 'onsets_ms';
    final raw = stim[field] as List? ?? stim['onsets_ms'] as List? ?? [];
    return raw.map<int>((e) => (e as num).toInt()).toList();
  }

  /// Devuelve las durations_ms del audio activo según _currentVideoField.
  List<int> _getCurrentDurationsMs(Map<String, dynamic>? stim) {
    if (stim == null) return [];
    final field = _currentVideoField == 'video_url_sprechgesang'
        ? 'durations_ms_sprechgesang'
        : _currentVideoField == 'video_url_habla_normal'
        ? 'durations_ms_habla_normal'
        : 'durations_ms';
    final raw = stim[field] as List? ?? stim['durations_ms'] as List? ?? [];
    return raw.map<int>((e) => (e as num).toInt()).toList();
  }

  /// Devuelve audio_duration_ms del audio activo según _currentVideoField.
  int _getCurrentAudioDurationMs(Map<String, dynamic>? stim) {
    if (stim == null) return 3000;
    final field = _currentVideoField == 'video_url_sprechgesang'
        ? 'audio_duration_ms_sprechgesang'
        : _currentVideoField == 'video_url_habla_normal'
        ? 'audio_duration_ms_habla_normal'
        : 'audio_duration_ms';
    return (stim[field] as num?)?.toInt() ??
        (stim['audio_duration_ms'] as num?)?.toInt() ??
        3000;
  }

  /// Cambia el campo de video activo y espera hasta 3 s a que el
  /// nuevo video esté listo para reproducir (para sincronizar con el audio).
  Future<void> _switchVideoField(String field) async {
    if (_currentVideoField == field) return;
    setState(() => _currentVideoField = field);
    int ms = 0;
    while (mounted &&
        _videoPlayerKey.currentState?.isReady == false &&
        ms < 3000) {
      await Future.delayed(const Duration(milliseconds: 50));
      ms += 50;
    }
    debugPrint(
      '[VID] _switchVideoField → $field | ready=${_videoPlayerKey.currentState?.isReady} after ${ms}ms',
    );
  }

  Future<String?> _resolveAudioUrl({String audioField = 'audio_url'}) async {
    final vm = context.read<TemSessionViewModel>();
    final raw = vm.currentStimulus?[audioField] as String?;
    debugPrint('[AUD] _resolveAudioUrl | field=$audioField | raw=$raw');
    if (raw == null || raw.isEmpty) return null;
    try {
      final sw = Stopwatch()..start();
      if (raw.startsWith('gs://')) {
        final url = await FirebaseStorage.instance
            .refFromURL(raw)
            .getDownloadURL();
        debugPrint(
          '[AUD] resolved in ${sw.elapsedMilliseconds}ms → ${url.substring(0, url.length.clamp(0, 60))}...',
        );
        return url;
      }
      return raw;
    } catch (e) {
      debugPrint('[AUD] _resolveAudioUrl ERROR: $e');
      return null;
    }
  }

  Future<void> _loadAudio() async {
    debugPrint('[AUD] _loadAudio called');
    final url = await _resolveAudioUrl();
    if (url == null) {
      debugPrint('[AUD] _loadAudio → url is null, bailing');
      return;
    }
    try {
      final sw = Stopwatch()..start();
      await _audioPlayer.setUrl(url);
      _loadedAudioUrl = url;
      debugPrint('[AUD] _loadAudio setUrl done in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[AUD] _loadAudio ERROR: $e');
    }
  }

  Future<void> _resolveImageUrl() async {
    final vm = context.read<TemSessionViewModel>();
    final raw = vm.currentStimulus?['imagen_url'] as String?;
    debugPrint(
      '[IMG] _resolveImageUrl | kIsWeb=$kIsWeb | raw=$raw | lastSource=$_lastImageSourceUrl',
    );

    // Saltar si ya resolvimos esta misma fuente
    final alreadyLoaded = kIsWeb
        ? (raw == _lastImageSourceUrl && _resolvedImageUrl != null)
        : (raw == _lastImageSourceUrl && _resolvedImageBytes != null);
    if (alreadyLoaded) {
      debugPrint('[IMG] same source, skip resolve');
      return;
    }
    _lastImageSourceUrl = raw;
    if (raw == null || raw.isEmpty) {
      debugPrint('[IMG] raw is null/empty');
      if (mounted)
        setState(() {
          _resolvedImageBytes = null;
          _resolvedImageUrl = null;
        });
      return;
    }
    try {
      final sw = Stopwatch()..start();
      final ref = raw.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(raw)
          : FirebaseStorage.instance.ref(raw);

      if (kIsWeb) {
        // Web: URL HTTPS → HtmlElementView renderiza con <img> nativo del browser.
        // Image.network / Image.memory fallan con AVIF en Chrome vía ImageDecoder API.
        final url = await ref.getDownloadURL();
        if (mounted) {
          setState(() => _resolvedImageUrl = url);
          debugPrint('[IMG] web URL ready in ${sw.elapsedMilliseconds}ms');
        }
      } else {
        // Móvil: bytes → Image.memory (decodificador nativo maneja AVIF sin problemas).
        final bytes = await ref.getData();
        if (mounted) {
          setState(() => _resolvedImageBytes = bytes);
          debugPrint(
            '[IMG] mobile bytes done in ${sw.elapsedMilliseconds}ms | size=${bytes?.length}',
          );
        }
      }
    } catch (e) {
      debugPrint('[IMG] _resolveImageUrl ERROR: $e');
      if (mounted)
        setState(() {
          _resolvedImageBytes = null;
          _resolvedImageUrl = null;
        });
    }
  }

  /// Reproduce el audio del estímulo y ESPERA a que termine.
  ///
  /// Siempre llama [stop()] + [setUrl()] para garantizar un estado limpio,
  /// eliminando la condición de carrera que bloqueaba la segunda reproducción.
  ///
  /// IMPORTANTE: NO dependemos del Future de [play()] para saber cuándo
  /// termina el audio.  En Android (ExoPlayer), [play()] resuelve cuando la
  /// reproducción INICIA, no cuando TERMINA.  En web sí espera hasta el
  /// final.  Para garantizar comportamiento consistente, lanzamos [play()]
  /// sin await y luego escuchamos [playerStateStream] hasta que
  /// [ProcessingState.completed] aparezca.
  ///
  /// [muteAfterFraction]: si se especifica, silencia el audio cuando la
  /// posición supera esa fracción de la duración total (0.5 = mitad).
  /// También pausa el video en ese mismo instante.
  ///
  /// [audioField]: campo del estímulo con la URL de audio a reproducir.
  /// Por defecto `'audio_url'`. Para N3 pasos 2/3/4 usar
  /// `'audio_url_sprechgesang'`.
  Future<void> _playAudioAndWait({
    double volume = 1.0,
    double? muteAfterFraction,
    int? fallbackDurationMs,
    String audioField = 'audio_url',
  }) async {
    debugPrint(
      '[AUD] _playAudioAndWait START | vol=$volume mute=$muteAfterFraction fallback=$fallbackDurationMs field=$audioField',
    );
    final url = await _resolveAudioUrl(audioField: audioField);
    if (url == null) {
      debugPrint('[AUD] _playAudioAndWait → url null, bailing');
      return;
    }

    // Resetear a estado idle ANTES de cargar → evita bloqueos en reproduct.
    // consecutivas del mismo URL.
    debugPrint('[AUD] calling stop() before setUrl');
    await _audioPlayer.stop();
    debugPrint('[AUD] stop() done | playerState=${_audioPlayer.playerState}');
    final sw = Stopwatch()..start();
    final loadedDuration = await _audioPlayer.setUrl(url);
    debugPrint(
      '[AUD] setUrl done in ${sw.elapsedMilliseconds}ms | loadedDuration=$loadedDuration',
    );
    _loadedAudioUrl = url;
    await _audioPlayer.setVolume(volume);
    debugPrint('[AUD] volume set to $volume');

    if (!mounted) return;
    final vm = context.read<TemSessionViewModel>();
    _startMetronomeOnPosition(vm.currentStimulus);

    // Iniciar video con adelanto para compensar latencia de pipeline media_kit.
    _videoPlayerKey.currentState?.play();
    await Future.delayed(const Duration(milliseconds: 150));

    // Configurar mute parcial (paso 3 — Completion).
    StreamSubscription<Duration>? posSub;
    if (muteAfterFraction != null) {
      // Intentar obtener duración: player → fallback del estímulo.
      final durMs =
          (loadedDuration ?? _audioPlayer.duration)?.inMilliseconds ??
          fallbackDurationMs;
      if (durMs != null && durMs > 0) {
        final muteAtMs = (durMs * muteAfterFraction).round();
        debugPrint(
          '[AUD] mute scheduled at ${muteAtMs}ms '
          '(total=${durMs}ms, fraction=$muteAfterFraction)',
        );
        posSub = _audioPlayer.positionStream.listen((pos) {
          if (pos.inMilliseconds >= muteAtMs) {
            _audioPlayer.setVolume(0);
            // Video sigue corriendo para que el paciente mantenga la guía visual.
            posSub?.cancel();
          }
        });
      } else {
        debugPrint(
          '[AUD] WARNING: could not determine audio duration '
          '\u2192 muteAfterFraction ignored',
        );
      }
    }

    final swPlay = Stopwatch()..start();
    debugPrint(
      '[AUD] play() fired — waiting for ProcessingState.completed... | playerState=${_audioPlayer.playerState}',
    );

    // Disparar reproducción SIN await — play() en Android retorna cuando el
    // audio ARRANCA, no cuando TERMINA.
    _audioPlayer.play();

    // Esperar explícitamente a que ExoPlayer reporte fin de reproducción.
    try {
      await _audioPlayer.playerStateStream.firstWhere((state) {
        debugPrint(
          '[AUD] playerState event: playing=${state.playing} processing=${state.processingState}',
        );
        return state.processingState == ProcessingState.completed;
      });
    } on StateError {
      debugPrint('[AUD] stream closed (player disposed)');
      // Stream cerrado (player disposed) — salir sin error.
    }

    swPlay.stop();
    debugPrint('[AUD] audio finished in ${swPlay.elapsedMilliseconds}ms');

    // Detener video al terminar audio
    debugPrint('[AUD] stopping video after audio done');
    _videoPlayerKey.currentState?.stop();

    posSub?.cancel();
    debugPrint('[AUD] _playAudioAndWait END');
  }

  // ══════════════════════════════════════════════════════════════════
  // Metrónomo
  // ══════════════════════════════════════════════════════════════════

  Uint8List _generateClickBytes() {
    const sr = 44100;
    const freq = 880.0;
    const durationMs = 80;
    const n = sr * durationMs ~/ 1000;
    final bd = ByteData(44 + n * 2);
    final b = bd.buffer.asUint8List();
    void ws(int o, String s) {
      for (var i = 0; i < s.length; i++) b[o + i] = s.codeUnitAt(i);
    }

    bd.setUint32(4, 36 + n * 2, Endian.little);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, sr, Endian.little);
    bd.setUint32(28, sr * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    bd.setUint32(40, n * 2, Endian.little);
    ws(0, 'RIFF');
    ws(8, 'WAVE');
    ws(12, 'fmt ');
    ws(36, 'data');
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final int sample =
          (math.exp(-t * 40) * 28000 * math.sin(2 * math.pi * freq * t))
              .round()
              .clamp(-32768, 32767);
      bd.setInt16(44 + i * 2, sample, Endian.little);
    }
    return b;
  }

  Future<void> _setupMetronomePlayer() async {
    final bytes = _clickBytes;
    if (bytes == null || _metronomePlayer == null) return;
    try {
      // StreamAudioSource sirve los bytes WAV directamente en memoria.
      // Es la única forma confiable en Android (ExoPlayer) e iOS (AVFoundation)
      // ya que ambos rechazan data: URIs silenciosamente.
      await _metronomePlayer!.setAudioSource(_ClickAudioSource(bytes));
      debugPrint('[Metro] player listo ✓');
    } catch (e) {
      debugPrint('[Metro] setup FALLÓ: $e');
    }
  }

  /// Reproduce el clic del metrónomo.
  ///
  /// IMPORTANTE: llama [setAudioSource] antes de cada [play] porque
  /// [StreamAudioSource] no soporta seeking fiable después de que el stream
  /// se consume. Llamar seek(0) sobre un stream agotado falla silenciosamente
  /// y deja el player en estado de error permanente — por eso anteriormente
  /// solo sonaba el primer clic y luego nada más.
  void _playClick() {
    final bytes = _clickBytes;
    final player = _metronomePlayer;
    if (bytes == null || player == null) return;
    debugPrint('[Metro] CLIC');
    // Cargar fuente fresca + play. _ClickAudioSource.request() crea un
    // Stream.value nuevo cada vez, así que no hay estado residual.
    player
        .setAudioSource(_ClickAudioSource(bytes))
        .then((_) => player.play())
        .catchError((e) => debugPrint('[Metro] error: $e'));
  }

  /// Programa un clic del metrónomo por cada onset del estímulo.
  ///
  /// Se llama justo antes de cada [_audioPlayer.play()].  Cuando
  /// [playingStream] emite `true` (audio realmente arrancando), se crean
  /// [Timer]s con el offset exacto de cada sílaba.  El flag local
  /// [scheduled] evita doble disparo si el stream emite varias veces.
  ///
  /// Como se llama antes de CADA reproducción (en [_playAudioAndWait]),
  /// el metrónomo suena en todas las repeticiones de todos los pasos.
  void _startMetronomeOnPosition(Map<String, dynamic>? stim) {
    _metronome?.cancel();
    _cancelClickTimers();

    // Habla normal no lleva metrónomo
    if (_currentVideoField == 'video_url_habla_normal') return;

    final onsets = _getCurrentOnsetsMs(stim);
    if (onsets.isEmpty) return;
    debugPrint('[Metro] ${onsets.length} onsets → $onsets');

    bool scheduled = false;
    _metronome = _audioPlayer.playingStream.listen((isPlaying) {
      if (!isPlaying || scheduled) return;
      scheduled = true; // dispara solo una vez por reproducción
      for (int i = 0; i < onsets.length; i++) {
        final ms = onsets[i];
        _clickTimers.add(
          Timer(Duration(milliseconds: ms), () {
            debugPrint('[Metro] clic sílaba $i @ ${ms}ms');
            if (mounted) _playClick();
          }),
        );
      }
    });
  }

  void _cancelClickTimers() {
    for (final t in _clickTimers) t.cancel();
    _clickTimers.clear();
  }

  Future<void> _startMetronomeStandalone(Map<String, dynamic>? stim) async {
    _metronome?.cancel();
    final onsets = _getCurrentOnsetsMs(stim);
    final Duration interval;
    final int clicks;
    if (onsets.length >= 2) {
      final avgMs = ((onsets.last - onsets.first) / (onsets.length - 1))
          .round()
          .clamp(200, 2000);
      interval = Duration(milliseconds: avgMs);
      clicks = onsets.length;
    } else {
      interval = const Duration(milliseconds: 500);
      clicks = 3;
    }
    var idx = 0;
    _metronome = Stream.periodic(interval).listen((_) {
      if (idx < clicks) {
        idx++;
        _playClick();
      } else {
        _metronome?.cancel();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════
  // Grabación (capa delgada sobre RecordingService)
  // ══════════════════════════════════════════════════════════════════

  Future<void> _startRec() async {
    final vm = context.read<TemSessionViewModel>();
    try {
      debugPrint('[REC-DBG] → _startRec()');
      await vm.recordingService.startRecording();
      debugPrint('[REC-DBG]   micrófono ABIERTO');
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('[REC-DBG]   _startRec ERROR: $e');
    }
  }

  Future<String?> _stopRec() async {
    final vm = context.read<TemSessionViewModel>();
    try {
      debugPrint('[REC-DBG] → _stopRec()');
      final path = await vm.recordingService.stopRecording();
      debugPrint('[REC-DBG]   micrófono CERRADO → $path');
      // Log tamaño del archivo grabado (solo en móvil).
      if (!kIsWeb) {
        try {
          final fileSize = await File(path).length();
          debugPrint(
            '[REC-DBG]   tamaño archivo: ${(fileSize / 1024).toStringAsFixed(1)} KB',
          );
        } catch (_) {}
      }
      if (mounted) setState(() => _isRecording = false);
      return path;
    } catch (e) {
      debugPrint('[REC-DBG]   _stopRec ERROR: $e');
      if (mounted) setState(() => _isRecording = false);
      return null;
    }
  }

  /// Sube una grabación y devuelve el [attemptId] generado.
  /// Devuelve `null` si ocurre un error (no crítico — el flujo continúa).
  Future<String?> _uploadAsync(
    TemSessionViewModel vm, {
    required String path,
    required int step,
    required int attempt,
  }) async {
    try {
      return await vm.recordingService.uploadAttempt(
        localPath: path,
        pacienteId: vm.pacienteId,
        sessionId: vm.sessionId ?? '',
        stimulusId: vm.currentStimulus?['id'] as String? ?? '',
        step: step,
        stepName: vm.currentStepName,
        attemptNumber: attempt,
      );
    } catch (e) {
      debugPrint('Upload (no crítico): $e');
      return null;
    }
  }

  /// Modo observabilidad: espera el resultado del backend Python en Firestore
  /// y lo registra en el log, pero siempre devuelve `true` para no bloquear
  /// al paciente. Sprint 3: reemplazar `return true` por `return isIntelligible`.
  Future<bool> _evaluateAttempt(String sessionId, String attemptId) async {
    if (attemptId.isEmpty) return true;
    final doc = FirebaseFirestore.instance
        .collection('sesiones_TEM')
        .doc(sessionId)
        .collection('attempts')
        .doc(attemptId);
    try {
      final snapshot = await doc
          .snapshots()
          .firstWhere((s) => s.data()?['status'] != 'pending_analysis')
          .timeout(const Duration(seconds: 90));
      final status = snapshot.data()?['status'] as String?;
      final clinicalScore = snapshot.data()?['clinical_score'] as int? ?? 0;
      final isIntelligible =
          snapshot.data()?['is_intelligible'] as bool? ?? false;
      debugPrint(
        '[TEM-EVAL] attemptId=$attemptId | '
        'status=$status | clinical_score=$clinicalScore | '
        'is_intelligible=$isIntelligible',
      );
      return clinicalScore >= 1;
    } on TimeoutException {
      debugPrint(
        '[TEM-EVAL] timeout esperando análisis de $attemptId — continuando',
      );
      return true; // timeout → no penalizar al paciente
    }
  }

  /// Evalúa TODOS los intentos de un paso en paralelo.
  /// Devuelve `true` si ALGÚN intento tiene clinical_score >= 1.
  Future<bool> _evaluateStepAttempts(
    String sessionId,
    List<String> attemptIds,
  ) async {
    final validIds = attemptIds.where((id) => id.isNotEmpty).toList();
    if (validIds.isEmpty) return true;

    final completer = Completer<bool>();
    int evaluated = 0;

    for (final id in validIds) {
      _evaluateAttempt(sessionId, id).then((passed) {
        if (completer.isCompleted) return;
        if (passed) {
          completer.complete(true);
        } else {
          evaluated++;
          if (evaluated >= validIds.length) {
            completer.complete(false);
          }
        }
      });
    }

    return completer.future;
  }

  /// Se invoca cuando el usuario pulsa el botón Continuar.
  void _onContinuePressed() {
    if (!mounted) return;
    final vm = context.read<TemSessionViewModel>();
    final passed = _lastStepPassed;
    setState(() => _waitingForContinue = false);

    // ── Retroceso via vm.stepBack() (N2 y N3 P4/P5) ───────────────
    // Se evalúa primero para tomar prioridad sobre los bloques específicos.
    if (vm.isRetroceso) {
      if (vm.retrocedFromStep != null &&
          vm.currentStep < vm.retrocedFromStep!) {
        // Estamos EN el paso de retroceso (ej. N2 P2 viniendo de P3)
        if (passed) {
          vm.advanceStep(); // volver al paso original, sin score
        } else {
          vm.abandonCurrentStimulus();
        }
      } else {
        // De vuelta en el paso original tras retroceso
        vm.recordAttemptResult(passed ? 1 : 0, forceAdvance: !passed);
        vm.clearRetroceso();
      }
      _continueOrFinish(vm);
      return;
    }

    // ── N3 P1: scoring con retroceso inline ──────────────────────
    if (vm.nivelActual == 3 && vm.currentStep == 1) {
      if (passed) {
        vm.recordAttemptResult(_n3P1NeedRetroceso ? 1 : 2);
      } else {
        vm.abandonCurrentStimulus();
      }
      _continueOrFinish(vm);
      return;
    }

    // ── N3 P2: introducción sprechgesang, sin score ───────────────
    if (vm.nivelActual == 3 && vm.currentStep == 2) {
      vm.advanceStep();
      _continueOrFinish(vm);
      return;
    }

    // ── N3 P3: scoring con retroceso inline ──────────────────────
    if (vm.nivelActual == 3 && vm.currentStep == 3) {
      if (passed) {
        vm.recordAttemptResult(_n3P3NeedRetroceso ? 1 : 2);
      } else {
        vm.abandonCurrentStimulus();
      }
      _continueOrFinish(vm);
      return;
    }

    // ── Lógica general: N1, N2, N3 P4/P5 ──────────────────────
    if (vm.currentStep == 1) {
      // N1 P1 y N2 P1: paso de escucha, sin score
      vm.advanceStep();
    } else if (vm.nivelActual >= 2 && !passed && vm.currentStep >= 3) {
      // N2 P3/P4 y N3 P4/P5: primer fallo → iniciar retroceso
      vm.stepBack();
    } else if (passed) {
      // Éxito normal
      final score = (vm.nivelActual >= 2 && vm.currentStep >= 3) ? 2 : 1;
      vm.recordAttemptResult(score);
    } else {
      // Fallo normal (N1 cualquier paso, N2 P2)
      vm.abandonCurrentStimulus();
    }
    _continueOrFinish(vm);
  }

  // ══════════════════════════════════════════════════════════════════
  // Transición de voz entre pasos
  // ══════════════════════════════════════════════════════════════════

  /// Selecciona la clave TTS, label e ícono según el nivel y paso actual,
  /// y muestra el [VoiceTransitionOverlay]. Si no hay servicio de narración,
  /// avanza directamente a [_autoBeginCurrentStep].
  void _startVoiceTransition() {
    if (!mounted) return;
    // Sin narración disponible: avanzar directamente, sin overlay.
    if (widget.narration == null) {
      _autoBeginCurrentStep();
      return;
    }
    final vm = context.read<TemSessionViewModel>();
    final config = _resolveTransitionConfig(vm.nivelActual, vm.currentStep);
    setState(() {
      _transitionKey = config.$1;
      _transitionLabel = config.$2;
      _transitionIcon = config.$3;
      _showVoiceTransition = true;
    });
  }

  /// Devuelve (audioKey, label, icon) para el nivel y paso dados.
  (String, String, IconData) _resolveTransitionConfig(int nivel, int step) {
    return switch ((nivel, step)) {
      (1, 1) => ('tem_n1p1_intro', 'Vamos a escuchar', Icons.hearing_rounded),
      (1, 2) => (
        'tem_n1p2_unison',
        'Canta junto con el audio',
        Icons.mic_rounded,
      ),
      (1, 3) => (
        'tem_n1p3_complete',
        'Completa la frase',
        Icons.record_voice_over_rounded,
      ),
      (1, 4) => ('tem_n1p4_repeat', 'Repite tú solo', Icons.volume_up_rounded),
      (1, 5) => (
        'tem_n1p5_question',
        'Responde la pregunta',
        Icons.question_answer_rounded,
      ),
      (2, 1) => ('tem_n2p1_intro', 'Vamos a escuchar', Icons.hearing_rounded),
      (2, 2) => (
        'tem_n2p2_fade',
        'Canta y completa la frase',
        Icons.mic_rounded,
      ),
      (2, 3) => (
        'tem_n2p3_pause',
        'Escucha y repite solo',
        Icons.volume_up_rounded,
      ),
      (2, 4) => (
        'tem_n2p4_question',
        'Responde la pregunta',
        Icons.question_answer_rounded,
      ),
      (3, 1) => (
        'tem_n3p1_delayed',
        'Repite después de la pausa',
        Icons.hourglass_empty_rounded,
      ),
      (3, 2) => (
        'tem_n3p2_sprechgesang_intro',
        'Tono más natural',
        Icons.music_note_rounded,
      ),
      (3, 3) => (
        'tem_n3p3_sprechgesang_fade',
        'Completa en tono natural',
        Icons.record_voice_over_rounded,
      ),
      (3, 4) => (
        'tem_n3p4_spoken',
        'Repite con voz normal',
        Icons.chat_bubble_outline_rounded,
      ),
      (3, 5) => (
        'tem_n3p5_question',
        'Responde la pregunta',
        Icons.question_answer_rounded,
      ),
      _ => ('tem_n1p1_intro', 'Prepárate', Icons.music_note_rounded),
    };
  }

  // ══════════════════════════════════════════════════════════════════
  // Flujo automático por paso
  // ══════════════════════════════════════════════════════════════════

  Future<void> _autoBeginCurrentStep() async {
    if (!mounted) return;
    final vm = context.read<TemSessionViewModel>();
    debugPrint(
      '[FLOW] _autoBeginCurrentStep | step=${vm.currentStep} | stimId=${vm.currentStimulus?['id']} | stimTexto=${vm.currentStimulus?['texto']}',
    );
    // Resolver imagen aquí — después del countdown, el estímulo ya cargó
    await _resolveImageUrl();
    _metronome?.cancel();
    _cancelClickTimers();
    // Paso 1: esperar hasta 2 s a que el video termine de abrir (evita stutter)
    if (vm.currentStep == 1) {
      int ms = 0;
      while (mounted &&
          _videoPlayerKey.currentState?.isReady == false &&
          ms < 2000) {
        await Future.delayed(const Duration(milliseconds: 50));
        ms += 50;
      }
      debugPrint(
        '[FLOW] video isReady=${_videoPlayerKey.currentState?.isReady} after ${ms}ms wait',
      );
    }
    if (vm.nivelActual == 1) {
      switch (vm.currentStep) {
        case 1:
          await _runStep1(vm);
        case 2:
          await _runStep2(vm);
        case 3:
          await _runStep3(vm);
        case 4:
          await _runStep4(vm);
        case 5:
          await _runStep5(vm);
      }
    } else if (vm.nivelActual == 3) {
      switch (vm.currentStep) {
        case 1:
          await _runN3Step1(vm);
        case 2:
          await _runN3Step2(vm);
        case 3:
          await _runN3Step3(vm);
        case 4:
          await _runN3Step4(vm);
        case 5:
          await _runN3Step5(vm);
      }
    } else {
      switch (vm.currentStep) {
        case 1:
          await _runN2Step1(vm);
        case 2:
          await _runN2Step2(vm);
        case 3:
          await _runN2Step3(vm);
        case 4:
          await _runN2Step4(vm);
      }
    }
  }

  // ─── Paso 1 — ESCUCHA: reproduce 2× ─────────────────────────────

  Future<void> _runStep1(TemSessionViewModel vm) async {
    debugPrint('[STEP1] START');
    setState(() {
      _paso1Plays = 0;
      _instructionOverride = null;
    });

    // Primera reproducción
    debugPrint('[STEP1] play #1 starting');
    await _playAudioAndWait();
    if (!mounted) return;
    debugPrint('[STEP1] play #1 done');

    // Segunda reproducción
    setState(() => _paso1Plays = 1);
    debugPrint('[STEP1] play #2 starting');
    await _playAudioAndWait();
    if (!mounted) return;
    debugPrint('[STEP1] play #2 done');

    setState(() {
      _paso1Plays = 2;
      _waitingForContinue = true;
      _instructionOverride = '¡Listo! Escuchaste el audio';
    });
    debugPrint('[STEP1] END → waiting for continue');
  }

  // ─── Paso 2 — UNÍSONO: 4 repeticiones mic + audio ───────────────

  Future<void> _runStep2(TemSessionViewModel vm) async {
    debugPrint('[STEP2] START');
    final attemptIds = <String>[];

    for (int rep = 1; rep <= 4; rep++) {
      if (!mounted) return;
      debugPrint('[STEP2] rep $rep/4 starting');
      setState(() {
        _currentRepetition = rep;
        _instructionOverride = 'Canta junto al audio ($rep/4)';
      });

      if (rep > 1) await Future.delayed(const Duration(milliseconds: 700));

      await _startRec();
      await _playAudioAndWait(volume: 1.0);
      final path = await _stopRec();

      if (path != null) {
        final id = await _uploadAsync(vm, path: path, step: 2, attempt: rep);
        if (id != null) attemptIds.add(id);
      }
    }

    if (!mounted) return;

    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateStepAttempts(vm.sessionId ?? '', attemptIds);
    if (!mounted) return;

    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      _instructionOverride = pass ? '¡Bien hecho!' : 'Sigue practicando';
    });
  }

  // ─── Paso 3 — COMPLETION: 4 rep, audio silenciado a la mitad ────

  Future<void> _runStep3(TemSessionViewModel vm) async {
    final attemptIds = <String>[];
    final fbDurMs = (vm.currentStimulus?['audio_duration_ms'] as num?)?.toInt();

    for (int rep = 1; rep <= 4; rep++) {
      if (!mounted) return;
      setState(() {
        _currentRepetition = rep;
        _instructionOverride = 'Completa la palabra ($rep/4)';
      });

      if (rep > 1) await Future.delayed(const Duration(milliseconds: 700));

      await _startRec();
      await _playAudioAndWait(
        volume: 1.0,
        muteAfterFraction: 0.5,
        fallbackDurationMs: fbDurMs,
      );
      final path = await _stopRec();

      if (path != null) {
        final id = await _uploadAsync(vm, path: path, step: 3, attempt: rep);
        if (id != null) attemptIds.add(id);
      }
    }

    if (!mounted) return;

    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateStepAttempts(vm.sessionId ?? '', attemptIds);
    if (!mounted) return;

    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      _instructionOverride = pass ? '¡Bien hecho!' : 'Sigue practicando';
    });
  }

  // ─── Paso 4 — REPETICIÓN: primero escucha, luego repite ─────────

  Future<void> _runStep4(TemSessionViewModel vm) async {
    // Fase A: escuchar el audio completo
    setState(() {
      _step4ListenDone = false;
      _instructionOverride = 'Escucha el audio completo';
    });

    await _playAudioAndWait(volume: 1.0);
    if (!mounted) return;

    // Fase B: el paciente repite (con guía de metrónomo)
    setState(() {
      _step4ListenDone = true;
      _instructionOverride = '¡Ahora repite tú!';
    });

    await Future.delayed(const Duration(milliseconds: 500));
    _startMetronomeStandalone(vm.currentStimulus); // fire-and-forget
    await _startRec();

    // Grabamos durante la duración del audio + buffer
    final audioDurMs =
        (vm.currentStimulus?['audio_duration_ms'] as num?)?.toInt() ?? 3000;
    await Future.delayed(Duration(milliseconds: audioDurMs + 1500));

    final path = await _stopRec();
    _metronome?.cancel();

    if (!mounted) return;

    final attemptId4 = path != null
        ? await _uploadAsync(vm, path: path, step: 4, attempt: 1)
        : null;

    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId4 ?? '');
    if (!mounted) return;

    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      _instructionOverride = pass ? '¡Excelente!' : 'Sigue practicando';
    });
  }

  // ─── Paso 5 — PREGUNTA: solo question card, graba respuesta ─────

  Future<void> _runStep5(TemSessionViewModel vm) async {
    setState(() => _instructionOverride = null);

    // Breve pausa para que el paciente lea la pregunta
    await Future.delayed(const Duration(seconds: 1));

    // Narrar la pregunta por voz antes de grabar la respuesta
    final ttsKey = vm.currentStimulus?['pregunta_tts_key'] as String?;
    await widget.narration?.speakAndWait(
      ttsKey ?? 'exercise_responde_pregunta',
    );
    if (!mounted) return;

    await _startRec();

    final audioDurMs =
        (vm.currentStimulus?['audio_duration_ms'] as num?)?.toInt() ?? 3000;
    await Future.delayed(Duration(milliseconds: audioDurMs + 2000));

    final path = await _stopRec();
    if (!mounted) return;

    final attemptId5 = path != null
        ? await _uploadAsync(vm, path: path, step: 5, attempt: 1)
        : null;

    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId5 ?? '');
    if (!mounted) return;

    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      _instructionOverride = pass ? '¡Muy bien!' : 'Sigue practicando';
    });
  }

  // ─── Pausa temporizada (N2 pasos 3-4) ───────────────────────────

  /// Muestra barra de pausa durante [seconds] segundos y espera.
  Future<void> _runPauseTimer(int seconds) async {
    setState(() {
      _pauseTimerActive = true;
      _pauseTimerTotal = seconds;
      _pauseTimerRemaining = seconds;
    });
    for (int i = seconds; i > 0; i--) {
      if (!mounted) return;
      setState(() => _pauseTimerRemaining = i);
      await Future.delayed(const Duration(seconds: 1));
    }
    if (mounted) setState(() => _pauseTimerActive = false);
  }

  // ─── N2 Paso 1 — INTRODUCCIÓN: reproduce 2× ─────────────────────

  Future<void> _runN2Step1(TemSessionViewModel vm) async {
    // Idéntico a N1 Paso 1: escuchar 2× con metrónomo.
    await _runStep1(vm);
  }

  // ─── N2 Paso 2 — UNÍSONO CON DESVANECIMIENTO ────────────────────

  Future<void> _runN2Step2(TemSessionViewModel vm) async {
    debugPrint('[N2-STEP2] START');
    final attemptIds = <String>[];
    final fbDurMs = (vm.currentStimulus?['audio_duration_ms'] as num?)?.toInt();

    // Fase A: 2 repeticiones obligatorias con desvanecimiento a mitad
    for (int rep = 1; rep <= 2; rep++) {
      if (!mounted) return;
      setState(() {
        _currentRepetition = rep;
        _instructionOverride = 'Canta y completa ($rep/2)';
      });
      if (rep > 1) await Future.delayed(const Duration(milliseconds: 700));

      await _startRec();
      await _playAudioAndWait(
        volume: 1.0,
        muteAfterFraction: 0.5,
        fallbackDurationMs: fbDurMs,
      );
      final path = await _stopRec();
      if (path != null) {
        final id = await _uploadAsync(vm, path: path, step: 2, attempt: rep);
        if (id != null) attemptIds.add(id);
      }
    }

    if (!mounted) return;
    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    var pass = await _evaluateStepAttempts(vm.sessionId ?? '', attemptIds);
    if (!mounted) return;

    // Fase B: hasta 2 intentos adicionales si fallan los obligatorios
    if (!pass) {
      for (int rep = 3; rep <= 4 && !pass; rep++) {
        if (!mounted) return;
        setState(() {
          _isEvaluating = false;
          _currentRepetition = rep;
          _instructionOverride = 'Inténtalo de nuevo ($rep/4)';
        });
        await Future.delayed(const Duration(milliseconds: 700));

        await _startRec();
        await _playAudioAndWait(
          volume: 1.0,
          muteAfterFraction: 0.5,
          fallbackDurationMs: fbDurMs,
        );
        final path = await _stopRec();
        if (path != null) {
          final id = await _uploadAsync(vm, path: path, step: 2, attempt: rep);
          if (id != null) {
            setState(() {
              _isEvaluating = true;
              _instructionOverride = 'Evaluando…';
            });
            pass = await _evaluateAttempt(vm.sessionId ?? '', id);
          }
        }
        if (!mounted) return;
      }
    }

    setState(() => _isEvaluating = false);
    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      _instructionOverride = pass ? '¡Bien hecho!' : 'Sigue practicando';
    });
    debugPrint('[N2-STEP2] END | pass=$pass');
  }

  // ─── N2 Paso 3 — REPETICIÓN CON PAUSA 6 s ──────────────────────

  Future<void> _runN2Step3(TemSessionViewModel vm) async {
    debugPrint('[N2-STEP3] START | isRetroceso=${vm.isRetroceso}');

    // Fase A: reproducir audio completo
    setState(() {
      _step4ListenDone = false;
      _instructionOverride = 'Escucha atentamente';
    });
    await _playAudioAndWait(volume: 1.0);
    if (!mounted) return;

    // Fase B: pausa de 6 segundos con barra de progreso
    setState(() {
      _step4ListenDone = true;
      _instructionOverride = 'Espera…';
    });
    await _runPauseTimer(6);
    if (!mounted) return;

    // Fase C: paciente repite con metrónomo como guía rítmica
    setState(() => _instructionOverride = '¡Ahora repite tú!');
    _startMetronomeStandalone(vm.currentStimulus); // guía rítmica
    await _startRec();
    final audioDurMs =
        (vm.currentStimulus?['audio_duration_ms'] as num?)?.toInt() ?? 3000;
    await Future.delayed(Duration(milliseconds: audioDurMs + 1500));
    final path = await _stopRec();
    _metronome?.cancel();
    if (!mounted) return;

    final attemptId = path != null
        ? await _uploadAsync(vm, path: path, step: 3, attempt: 1)
        : null;

    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId ?? '');
    if (!mounted) return;
    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      if (pass) {
        _instructionOverride = '¡Excelente!';
      } else if (vm.isRetroceso) {
        _instructionOverride = 'No logró repetir';
      } else {
        _instructionOverride = 'Volvamos al paso anterior';
      }
    });
    debugPrint('[N2-STEP3] END | pass=$pass');
  }

  // ─── N2 Paso 4 — RESPUESTA A PREGUNTA CON PAUSA 6 s ────────────

  Future<void> _runN2Step4(TemSessionViewModel vm) async {
    debugPrint('[N2-STEP4] START | isRetroceso=${vm.isRetroceso}');
    setState(
      () => _instructionOverride = null,
    ); // muestra pregunta vía showTextQuestion

    // Pausa de 6 segundos
    await _runPauseTimer(6);
    if (!mounted) return;

    // Narrar la pregunta por voz antes de grabar la respuesta
    final ttsKeyN2 = vm.currentStimulus?['pregunta_tts_key'] as String?;
    await widget.narration?.speakAndWait(
      ttsKeyN2 ?? 'exercise_responde_pregunta',
    );
    if (!mounted) return;

    // Paciente responde la pregunta
    setState(() => _instructionOverride = 'Responde la pregunta');
    await _startRec();
    final audioDurMs =
        (vm.currentStimulus?['audio_duration_ms'] as num?)?.toInt() ?? 3000;
    await Future.delayed(Duration(milliseconds: audioDurMs + 2000));
    final path = await _stopRec();
    if (!mounted) return;

    final attemptId = path != null
        ? await _uploadAsync(vm, path: path, step: 4, attempt: 1)
        : null;

    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId ?? '');
    if (!mounted) return;
    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      if (pass) {
        _instructionOverride = '¡Muy bien!';
      } else if (vm.isRetroceso) {
        _instructionOverride = 'No logró responder';
      } else {
        _instructionOverride = 'Volvamos al paso anterior';
      }
    });
    debugPrint('[N2-STEP4] END | pass=$pass');
  }

  // ══════════════════════════════════════════════════════════════════
  // NIVEL 3 — 5 pasos (Sprechgesang + Habla Normal)
  // ══════════════════════════════════════════════════════════════════

  // ─── N3 Paso 1 — Repetición diferida ────────────────────────────
  //
  // Protocolo: escucha entonado → pausa 6 s → repite solo con metrónomo.
  // Retroceso inline: si falla, apoyo con desvanecimiento 50% seguido de
  // un segundo intento. El flag _n3P1NeedRetroceso informa a
  // _onContinuePressed si el éxito fue con o sin retroceso.
  Future<void> _runN3Step1(TemSessionViewModel vm) async {
    debugPrint('[N3-STEP1] START');
    await _switchVideoField('video_url');
    _n3P1NeedRetroceso = false;
    final audioDurMs =
        (vm.currentStimulus?['audio_duration_ms'] as num?)?.toInt() ?? 3000;

    // Fase A: escucha entonado 1×
    setState(() {
      _step4ListenDone = false;
      _instructionOverride = 'Escucha la melodía';
    });
    await _playAudioAndWait(volume: 1.0);
    if (!mounted) return;

    // Fase B: pausa 6 s
    setState(() {
      _step4ListenDone = true;
      _instructionOverride = 'Prepárate…';
    });
    await _runPauseTimer(6);
    if (!mounted) return;

    // Fase C: repite solo con metrónomo
    setState(() => _instructionOverride = '¡Repite tú solo!');
    await _startMetronomeStandalone(vm.currentStimulus);
    await _startRec();
    await Future.delayed(Duration(milliseconds: audioDurMs + 1500));
    final path = await _stopRec();
    _metronome?.cancel();
    if (!mounted) return;

    final attemptId = path != null
        ? await _uploadAsync(vm, path: path, step: 1, attempt: 1)
        : null;
    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    var pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId ?? '');
    if (!mounted) return;
    setState(() => _isEvaluating = false);

    if (!pass) {
      // Retroceso INLINE: apoyo con desvanecimiento entonado (fade 50%)
      _n3P1NeedRetroceso = true;
      setState(() => _instructionOverride = 'Vamos a intentarlo juntos');
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      await _startRec();
      await _playAudioAndWait(
        volume: 1.0,
        muteAfterFraction: 0.5,
        fallbackDurationMs: audioDurMs,
      );
      await _stopRec(); // intento de apoyo — no se evalúa
      if (!mounted) return;

      // Pausa y segundo intento individual
      setState(() => _instructionOverride = 'Prepárate…');
      await _runPauseTimer(6);
      if (!mounted) return;

      setState(() => _instructionOverride = '¡Ahora repite tú solo!');
      await _startMetronomeStandalone(vm.currentStimulus);
      await _startRec();
      await Future.delayed(Duration(milliseconds: audioDurMs + 1500));
      final path2 = await _stopRec();
      _metronome?.cancel();
      if (!mounted) return;

      final attemptId2 = path2 != null
          ? await _uploadAsync(vm, path: path2, step: 1, attempt: 2)
          : null;
      setState(() {
        _isEvaluating = true;
        _instructionOverride = 'Evaluando…';
      });
      pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId2 ?? '');
      if (!mounted) return;
      setState(() => _isEvaluating = false);
    }

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      _instructionOverride = pass ? '¡Muy bien!' : 'Continuemos';
    });
    debugPrint('[N3-STEP1] END | pass=$pass | retroceso=$_n3P1NeedRetroceso');
  }

  // ─── N3 Paso 2 — Introducción sprechgesang ──────────────────────
  //
  // Protocolo: presenta 2× en sprechgesang, paciente solo escucha.
  // Sin grabación. Sin puntuación.
  Future<void> _runN3Step2(TemSessionViewModel vm) async {
    debugPrint('[N3-STEP2] START');
    await _switchVideoField('video_url_sprechgesang');
    setState(() {
      _paso1Plays = 0;
      _instructionOverride = null;
    });

    // Primera reproducción (sprechgesang)
    await _playAudioAndWait(audioField: 'audio_url_sprechgesang');
    if (!mounted) return;
    setState(() => _paso1Plays = 1);

    // Segunda reproducción
    await _playAudioAndWait(audioField: 'audio_url_sprechgesang');
    if (!mounted) return;
    setState(() {
      _paso1Plays = 2;
      _waitingForContinue = true;
      _instructionOverride = '¡Escuchaste el tono natural!';
    });
    debugPrint('[N3-STEP2] END');
  }

  // ─── N3 Paso 3 — Sprechgesang con apagado ───────────────────────
  //
  // Protocolo: paciente canta sprechgesang con fade a mitad.
  // Retroceso inline: si falla, apoyo con sprechgesang completo + retry fade.
  Future<void> _runN3Step3(TemSessionViewModel vm) async {
    debugPrint('[N3-STEP3] START');
    await _switchVideoField('video_url_sprechgesang');
    _n3P3NeedRetroceso = false;
    final audioDurMs = _getCurrentAudioDurationMs(vm.currentStimulus);

    setState(() {
      _step4ListenDone = true;
      _instructionOverride = 'Completa la frase';
    });
    await _startRec();
    await _playAudioAndWait(
      volume: 1.0,
      muteAfterFraction: 0.5,
      fallbackDurationMs: audioDurMs,
      audioField: 'audio_url_sprechgesang',
    );
    final path = await _stopRec();
    if (!mounted) return;

    final attemptId = path != null
        ? await _uploadAsync(vm, path: path, step: 3, attempt: 1)
        : null;
    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    var pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId ?? '');
    if (!mounted) return;
    setState(() => _isEvaluating = false);

    if (!pass) {
      // Retroceso INLINE: sprechgesang completo como apoyo
      _n3P3NeedRetroceso = true;
      setState(() => _instructionOverride = 'Vamos juntos');
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      await _startRec();
      await _playAudioAndWait(
        volume: 1.0,
        fallbackDurationMs: audioDurMs,
        audioField: 'audio_url_sprechgesang',
      ); // completo sin fade (apoyo)
      await _stopRec(); // no se evalúa
      if (!mounted) return;

      // Retry con fade
      setState(() => _instructionOverride = 'Completa tú solo');
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      await _startRec();
      await _playAudioAndWait(
        volume: 1.0,
        muteAfterFraction: 0.5,
        fallbackDurationMs: audioDurMs,
        audioField: 'audio_url_sprechgesang',
      );
      final path2 = await _stopRec();
      if (!mounted) return;

      final attemptId2 = path2 != null
          ? await _uploadAsync(vm, path: path2, step: 3, attempt: 2)
          : null;
      setState(() {
        _isEvaluating = true;
        _instructionOverride = 'Evaluando…';
      });
      pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId2 ?? '');
      if (!mounted) return;
      setState(() => _isEvaluating = false);
    }

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      _instructionOverride = pass ? '¡Muy bien!' : 'Continuemos';
    });
    debugPrint('[N3-STEP3] END | pass=$pass | retroceso=$_n3P3NeedRetroceso');
  }

  // ─── N3 Paso 4 — Repetición hablada diferida ────────────────────
  //
  // Protocolo: escucha sprechgesang (referencia) → pausa 6 s →
  // paciente repite con VOZ NORMAL (sin metrónomo).
  // Retroceso via vm.stepBack() igual que N2 P3.
  Future<void> _runN3Step4(TemSessionViewModel vm) async {
    debugPrint('[N3-STEP4] START | isRetroceso=${vm.isRetroceso}');
    await _switchVideoField('video_url_habla_normal');
    final audioDurMs = _getCurrentAudioDurationMs(vm.currentStimulus);

    // Fase A: escucha habla normal 1× como referencia
    setState(() {
      _step4ListenDone = false;
      _instructionOverride = 'Escucha, luego repite normalmente';
    });
    await _playAudioAndWait(volume: 1.0, audioField: 'audio_url_habla_normal');
    if (!mounted) return;

    // Fase B: pausa 6 s
    setState(() {
      _step4ListenDone = true;
      _instructionOverride = 'Prepárate…';
    });
    await _runPauseTimer(6);
    if (!mounted) return;

    // Fase C: repite con voz normal (sin metrónomo)
    setState(() => _instructionOverride = '¡Habla normalmente!');
    await _startRec();
    await Future.delayed(Duration(milliseconds: audioDurMs + 2000));
    final path = await _stopRec();
    if (!mounted) return;

    final attemptId = path != null
        ? await _uploadAsync(vm, path: path, step: 4, attempt: 1)
        : null;
    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId ?? '');
    if (!mounted) return;
    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      if (pass) {
        _instructionOverride = '¡Excelente!';
      } else if (vm.isRetroceso) {
        _instructionOverride = 'No logró repetir';
      } else {
        _instructionOverride = 'Volvamos al paso anterior';
      }
    });
    debugPrint('[N3-STEP4] END | pass=$pass');
  }

  // ─── N3 Paso 5 — Pregunta (habla normal) ────────────────────────
  //
  // Protocolo idéntico a N2 Paso 4: pausa 6 s → TTS pregunta →
  // paciente responde con voz natural.
  // Retroceso via vm.stepBack() igual que N2 P4.
  Future<void> _runN3Step5(TemSessionViewModel vm) async {
    debugPrint('[N3-STEP5] START | isRetroceso=${vm.isRetroceso}');
    await _switchVideoField('video_url');
    setState(() => _instructionOverride = null);

    // Pausa de 6 segundos
    await _runPauseTimer(6);
    if (!mounted) return;

    // Breve espera para que el stop() del VoiceTransitionOverlay se complete
    // antes de iniciar la siguiente reproducción del NarrationService.
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Narrar la pregunta por TTS (igual que N1/N2: lee la pregunta del estímulo)
    final ttsKey = vm.currentStimulus?['pregunta_tts_key'] as String?;
    await widget.narration?.speakAndWait(
      ttsKey ?? 'exercise_responde_pregunta',
    );
    if (!mounted) return;

    // Paciente responde con voz normal
    setState(() => _instructionOverride = 'Responde con tu voz normal');
    await _startRec();
    final audioDurMs = _getCurrentAudioDurationMs(vm.currentStimulus);
    await Future.delayed(Duration(milliseconds: audioDurMs + 2000));
    final path = await _stopRec();
    if (!mounted) return;

    final attemptId = path != null
        ? await _uploadAsync(vm, path: path, step: 5, attempt: 1)
        : null;
    setState(() {
      _isEvaluating = true;
      _instructionOverride = 'Evaluando…';
    });
    final pass = await _evaluateAttempt(vm.sessionId ?? '', attemptId ?? '');
    if (!mounted) return;
    setState(() => _isEvaluating = false);

    setState(() {
      _lastStepPassed = pass;
      _waitingForContinue = true;
      if (pass) {
        _instructionOverride = '¡Muy bien!';
      } else if (vm.isRetroceso) {
        _instructionOverride = 'No logró responder';
      } else {
        _instructionOverride = 'Volvamos al paso anterior';
      }
    });
    debugPrint('[N3-STEP5] END | pass=$pass');
  }

  // ──────────────────────────────────────────────────────────────────
  // Transición entre estados (paso siguiente o nuevo estímulo)
  // ──────────────────────────────────────────────────────────────────

  void _continueOrFinish(TemSessionViewModel vm) {
    if (!mounted) return;
    _metronome?.cancel();
    debugPrint(
      '[FLOW] _continueOrFinish | step=${vm.currentStep} | finished=${vm.sessionFinished} | stimId=${vm.currentStimulus?['id']}',
    );

    // Sesión terminada → navegar a resumen
    if (vm.sessionFinished) {
      debugPrint('[FLOW] session finished → navigating to summary');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: vm,
              child: const TemSessionSummaryScreen(),
            ),
          ),
        );
      });
      return;
    }

    // Continuar: resetear estado visual y mostrar cuenta regresiva
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      debugPrint('[FLOW] postFrame → resetting visual state');
      setState(() {
        _isRecording = false;
        _isEvaluating = false;
        _waitingForContinue = false;
        _lastStepPassed = true;
        _paso1Plays = 0;
        _currentRepetition = 0;
        _step4ListenDone = false;
        _pauseTimerActive = false;
        _instructionOverride = null;
      });
      // Nuevo estímulo (paso 1): detener audio/video anterior y cargar el nuevo
      if (vm.currentStep == 1) {
        debugPrint('[FLOW] step==1 → clearing old media, loading new audio');
        debugPrint(
          '[FLOW] currentStimulus at _loadAudio time: id=${vm.currentStimulus?['id']} texto=${vm.currentStimulus?['texto']}',
        );
        // Limpiar imagen vieja — se resolverá después del countdown
        // cuando _loadCurrentStimulus() ya haya cargado el nuevo estímulo.
        _resolvedImageBytes = null;
        _resolvedImageUrl = null;
        _lastImageSourceUrl = null;
        _videoPlayerKey.currentState?.stop();
        await _audioPlayer.stop();
        await _loadAudio();
      }
      debugPrint('[FLOW] starting voice transition');
      _startVoiceTransition();
    });
  }

  // ══════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Consumer<TemSessionViewModel>(
      builder: (context, vm, _) {
        final stimulus = vm.currentStimulus;
        final showLips = !vm.showTextQuestion; // paso 5: sin animación labial
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final instructionText = _instructionOverride ?? vm.stepInstruction;

        // Sílabas y tiempos para el SyllableHighlightWidget
        final syllables = List<String>.from(
          (stimulus?['syllables'] as List?) ?? [],
        );
        final onsetsMs = _getCurrentOnsetsMs(stimulus);
        final durationsMs = _getCurrentDurationsMs(stimulus);

        return Scaffold(
          backgroundColor: _bgColor,
          body: Stack(
            children: [
              Column(
                children: [
                  // Header personalizado
                  TemPageHeader(
                    title: instructionText,
                    backgroundColor: _accentColor,
                    trailing: widget.narration != null
                        ? MuteButton(narration: widget.narration!)
                        : null,
                  ),
                  // Barra de progreso + nivel/paso
                  _StepProgressBar(
                    currentStep: vm.currentStep,
                    totalSteps: vm.totalSteps,
                  ),
                  // Contenido principal
                  Expanded(
                    child: showLips
                        ? (isLandscape
                              ? _buildLandscapeBody(
                                  vm,
                                  stimulus,
                                  syllables,
                                  onsetsMs,
                                  durationsMs,
                                )
                              : _buildPortraitBody(
                                  vm,
                                  stimulus,
                                  syllables,
                                  onsetsMs,
                                  durationsMs,
                                ))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            child: Column(
                              children: [
                                _InstructionBanner(text: instructionText),
                                const SizedBox(height: 20),
                                _QuestionCard(stimulus: stimulus),
                                const SizedBox(height: 16),
                                // Imagen del estímulo en paso 5
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildStimImage(
                                    width: 160,
                                    height: 160,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildActionArea(vm),
                              ],
                            ),
                          ),
                  ),
                ],
              ),

              // Overlay de transición de voz entre pasos
              if (_showVoiceTransition && widget.narration != null)
                VoiceTransitionOverlay(
                  narration: widget.narration!,
                  audioKey: _transitionKey,
                  label: _transitionLabel,
                  icon: _transitionIcon,
                  onDone: () {
                    if (!mounted) return;
                    setState(() => _showVoiceTransition = false);
                    _autoBeginCurrentStep();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Layout vertical (portrait) ──────────────────────────────────────────
  Widget _buildPortraitBody(
    TemSessionViewModel vm,
    Map<String, dynamic>? stimulus,
    List<String> syllables,
    List<int> onsetsMs,
    List<int> durationsMs,
  ) {
    final texto = stimulus?['texto'] as String? ?? '—';
    final instructionText = _instructionOverride ?? vm.stepInstruction;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          // Instrucción del paso
          _InstructionBanner(text: instructionText),
          const SizedBox(height: 16),

          // Video del estímulo
          TemVideoPlayerWidget(
            key: _videoPlayerKey,
            videoUrl: stimulus?[_currentVideoField] as String?,
          ),
          const SizedBox(height: 12),

          // Sílabas resaltadas (o texto plano si no hay datos)
          // Habla normal no muestra resaltado de sílabas
          if (syllables.isNotEmpty &&
              syllables.length == onsetsMs.length &&
              syllables.length == durationsMs.length &&
              _currentVideoField != 'video_url_habla_normal')
            SyllableHighlightWidget(
              syllables: syllables,
              onsetsMs: onsetsMs,
              durationsMs: durationsMs,
              audioPosition: _audioPlayer.positionStream,
              texto: texto,
            )
          else
            _StimulusText(texto: texto),

          const SizedBox(height: 16),

          // Imagen del estímulo
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _buildStimImage(width: 180, height: 180),
          ),

          const SizedBox(height: 20),
          _buildActionArea(vm),
        ],
      ),
    );
  }

  // ── Layout horizontal (landscape) ─────────────────────────────────────────
  Widget _buildLandscapeBody(
    TemSessionViewModel vm,
    Map<String, dynamic>? stimulus,
    List<String> syllables,
    List<int> onsetsMs,
    List<int> durationsMs,
  ) {
    final texto = stimulus?['texto'] as String? ?? '—';
    final instructionText = _instructionOverride ?? vm.stepInstruction;
    return Column(
      children: [
        // Instrucción del paso
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _InstructionBanner(text: instructionText),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ─── Izquierda: video ───
                Expanded(
                  flex: 3,
                  child: TemVideoPlayerWidget(
                    key: _videoPlayerKey,
                    videoUrl: stimulus?[_currentVideoField] as String?,
                  ),
                ),
                const SizedBox(width: 12),

                // ─── Centro: sílabas + controles ───
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Habla normal no muestra resaltado de sílabas
                        if (syllables.isNotEmpty &&
                            syllables.length == onsetsMs.length &&
                            syllables.length == durationsMs.length &&
                            _currentVideoField != 'video_url_habla_normal')
                          SyllableHighlightWidget(
                            syllables: syllables,
                            onsetsMs: onsetsMs,
                            durationsMs: durationsMs,
                            audioPosition: _audioPlayer.positionStream,
                            texto: texto,
                          )
                        else
                          _StimulusText(texto: texto),
                        const SizedBox(height: 16),
                        _buildActionArea(vm),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // ─── Derecha: imagen del estímulo ───
                if (kIsWeb
                    ? _resolvedImageUrl != null
                    : _resolvedImageBytes != null)
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildStimImage(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Renderiza la imagen del est\u00edmulo de forma compatible con la plataforma.
  ///
  /// - Web: [HtmlElementView] con un `<img>` nativo del browser, que decodifica
  ///   AVIF correctamente sin pasar por el [ImageDecoder] API de Flutter Web.
  /// - M\u00f3vil: [Image.memory] con los bytes descargados prev\u00edamente.
  Widget _buildStimImage({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    if (kIsWeb) {
      if (_resolvedImageUrl == null) return const SizedBox.shrink();
      final url = _resolvedImageUrl!;
      return SizedBox(
        width: width,
        height: height,
        child: HtmlElementView.fromTagName(
          key: ValueKey(url),
          tagName: 'img',
          onElementCreated: (el) {
            final img = el as dynamic;
            img.src = url;
            img.style.width = '100%';
            img.style.height = '100%';
            img.style.objectFit = fit == BoxFit.cover ? 'cover' : 'contain';
          },
        ),
      );
    } else {
      if (_resolvedImageBytes == null) return const SizedBox.shrink();
      return Image.memory(
        _resolvedImageBytes!,
        width: width,
        height: height,
        fit: fit,
      );
    }
  }

  Widget _buildActionArea(TemSessionViewModel vm) {
    if (_waitingForContinue) {
      return _ContinueButton(onPressed: _onContinuePressed);
    }
    if (_isEvaluating) {
      return const _LoadingContinueButton();
    }
    if (_pauseTimerActive) {
      return _PauseProgressBar(
        remaining: _pauseTimerRemaining,
        total: _pauseTimerTotal,
      );
    }

    // ── N3: indicadores específicos ────────────────────────────────────
    if (vm.nivelActual == 3) {
      if (vm.currentStep == 2) {
        return _Paso1AutoIndicator(plays: _paso1Plays);
      }
      if (vm.currentStep == 5) {
        return _Step5Indicator(
          isRecording: _isRecording,
          isEvaluating: _isEvaluating,
        );
      }
      // P1, P3, P4: escucha → graba
      return _Step4Indicator(
        listenDone: _step4ListenDone,
        isRecording: _isRecording,
        isEvaluating: _isEvaluating,
      );
    }

    // Paso 1 es escucha en ambos niveles
    if (vm.currentStep == 1) {
      return _Paso1AutoIndicator(plays: _paso1Plays);
    }

    // Pasos de repetición con conteo (N1 P2-P3, N2 P2)
    if ((vm.nivelActual == 1 && (vm.currentStep == 2 || vm.currentStep == 3)) ||
        (vm.nivelActual >= 2 && vm.currentStep == 2)) {
      return _RepetitionIndicator(
        current: _currentRepetition,
        total: vm.nivelActual >= 2 ? 2 : 4,
        isRecording: _isRecording,
        isEvaluating: _isEvaluating,
      );
    }

    // Pasos de escucha+repetición (N1 P4, N2 P3)
    if ((vm.nivelActual == 1 && vm.currentStep == 4) ||
        (vm.nivelActual >= 2 && vm.currentStep == 3)) {
      return _Step4Indicator(
        listenDone: _step4ListenDone,
        isRecording: _isRecording,
        isEvaluating: _isEvaluating,
      );
    }

    // Pasos de pregunta (N1 P5, N2 P4)
    if ((vm.nivelActual == 1 && vm.currentStep == 5) ||
        (vm.nivelActual >= 2 && vm.currentStep == 4)) {
      return _Step5Indicator(
        isRecording: _isRecording,
        isEvaluating: _isEvaluating,
      );
    }

    return const SizedBox.shrink();
  }
}

// ============================================================================
// Sub-widgets de UI
// ============================================================================

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepProgressBar({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFF7043),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paso $currentStep de $totalSteps',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(totalSteps, (i) {
              final done = i < currentStep;
              final active = i == currentStep - 1;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: done
                        ? Colors.white
                        : active
                        ? Colors.white70
                        : Colors.white30,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _InstructionBanner extends StatelessWidget {
  final String text;
  const _InstructionBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE9E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF48A63)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFFBF360C),
        ),
      ),
    );
  }
}

class _StimulusText extends StatelessWidget {
  final String texto;
  const _StimulusText({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2D2D2D),
        letterSpacing: 1.2,
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final Map<String, dynamic>? stimulus;
  const _QuestionCard({required this.stimulus});

  @override
  Widget build(BuildContext context) {
    final pregunta =
        stimulus?['pregunta'] as String? ?? '¿Qué quieres decirme ahora?';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.record_voice_over_rounded,
            size: 48,
            color: Color(0xFFF57C00),
          ),
          const SizedBox(height: 12),
          const Text(
            'Responde:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Color(0xFFE65100)),
          ),
          const SizedBox(height: 12),
          Text(
            pregunta,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4E342E),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Indicrador paso 1 ────────────────────────────────────────────────────────

class _Paso1AutoIndicator extends StatelessWidget {
  final int plays;
  const _Paso1AutoIndicator({required this.plays});

  @override
  Widget build(BuildContext context) {
    final bool allDone = plays >= 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          allDone ? Icons.check_circle_rounded : Icons.hearing_rounded,
          size: 56,
          color: const Color(0xFFF48A63),
        ),
        const SizedBox(height: 10),
        Text(
          allDone ? 'Audio reproducido' : 'Escucha atentamente',
          style: const TextStyle(color: Colors.black54, fontSize: 18),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(2, (i) {
            final done = i < plays;
            final active = i == plays;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 48 : 40,
              height: active ? 48 : 40,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? const Color(0xFFF48A63)
                    : active
                    ? const Color(0xFFF48A63).withOpacity(0.35)
                    : Colors.black12,
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 24,
                    )
                  : active
                  ? const Icon(
                      Icons.volume_up_rounded,
                      color: Color(0xFFF48A63),
                      size: 28,
                    )
                  : null,
            );
          }),
        ),
      ],
    );
  }
}

// ── Indicador pasos 2 y 3 ───────────────────────────────────────────────────

class _RepetitionIndicator extends StatelessWidget {
  final int current;
  final int total;
  final bool isRecording;
  final bool isEvaluating;

  const _RepetitionIndicator({
    required this.current,
    required this.total,
    required this.isRecording,
    required this.isEvaluating,
  });

  @override
  Widget build(BuildContext context) {
    if (isEvaluating) return const _EvaluatingWidget();
    return Column(
      children: [
        // Puntos de progreso (uno por repetición)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total, (i) {
            final done = i < current - 1;
            final active = i == current - 1;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 28 : 22,
              height: active ? 28 : 22,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? const Color(0xFFF48A63)
                    : active
                    ? const Color(0xFFF48A63).withOpacity(0.7)
                    : Colors.black12,
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
                    )
                  : null,
            );
          }),
        ),
        const SizedBox(height: 16),
        if (isRecording)
          const _RecordingPulse()
        else
          const SizedBox(height: 50),
      ],
    );
  }
}

// ── Indicador paso 4 ─────────────────────────────────────────────────────────

class _Step4Indicator extends StatelessWidget {
  final bool listenDone;
  final bool isRecording;
  final bool isEvaluating;

  const _Step4Indicator({
    required this.listenDone,
    required this.isRecording,
    required this.isEvaluating,
  });

  @override
  Widget build(BuildContext context) {
    if (isEvaluating) return const _EvaluatingWidget();

    if (!listenDone) {
      return const Column(
        children: [
          Icon(Icons.hearing_rounded, size: 56, color: Color(0xFFF48A63)),
          SizedBox(height: 8),
          Text(
            'Escuchando…',
            style: TextStyle(color: Colors.black54, fontSize: 18),
          ),
        ],
      );
    }
    return Column(
      children: [
        const Icon(Icons.mic_rounded, size: 56, color: Color(0xFFF48A63)),
        const SizedBox(height: 8),
        const Text(
          '¡Tu turno!',
          style: TextStyle(
            color: Color(0xFFF48A63),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (isRecording) const _RecordingPulse(),
      ],
    );
  }
}

// ── Indicador paso 5 ─────────────────────────────────────────────────────────

class _Step5Indicator extends StatelessWidget {
  final bool isRecording;
  final bool isEvaluating;
  const _Step5Indicator({
    required this.isRecording,
    required this.isEvaluating,
  });

  @override
  Widget build(BuildContext context) {
    if (isEvaluating) return const _EvaluatingWidget();
    return Column(
      children: [
        if (isRecording)
          const _RecordingPulse()
        else
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFFF48A63),
            ),
          ),
      ],
    );
  }
}

// ── Componentes compartidos ──────────────────────────────────────────────────

class _RecordingPulse extends StatelessWidget {
  const _RecordingPulse();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4CAF50).withOpacity(0.15),
          ),
          child: const Icon(
            Icons.mic_rounded,
            size: 48,
            color: Color(0xFF4CAF50),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Grabando…',
          style: TextStyle(
            color: Color(0xFF4CAF50),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EvaluatingWidget extends StatelessWidget {
  const _EvaluatingWidget();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFFF48A63),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Evaluando…',
          style: TextStyle(color: Colors.black54, fontSize: 16),
        ),
      ],
    );
  }
}

// ── Botón CONTINUAR (estilo Duolingo) ────────────────────────────────────────

class _ContinueButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ContinueButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 72,
        child: ElevatedButton.icon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            onPressed();
          },
          icon: const Icon(Icons.arrow_forward_rounded, size: 28),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF48A63),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
            shadowColor: const Color(0xFFF48A63).withOpacity(0.4),
          ),
          label: const Text(
            'CONTINUAR',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingContinueButton extends StatelessWidget {
  const _LoadingContinueButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Evaluando…',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra horizontal de pausa temporizada (N2 pasos 3-4).
class _PauseProgressBar extends StatelessWidget {
  final int remaining;
  final int total;
  const _PauseProgressBar({required this.remaining, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = remaining / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$remaining s',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF48A63),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 12,
              backgroundColor: const Color(0xFFFBE9E7),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFF48A63),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
