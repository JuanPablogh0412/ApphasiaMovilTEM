import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/tem/tem_session_viewmodel.dart';
import 'lip_animation/lip_animation_widget.dart';
import 'lip_animation/lip_timeline.dart';
import 'syllable_highlight_widget.dart';
import 'tem_session_summary_screen.dart';

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

/// Pantalla de ejercicio activo TEM — protocolo de 5 pasos Nivel 1.
///
/// Paso 1 — ESCUCHA:     App reproduce audio 2×.  Sin grabación.
/// Paso 2 — UNÍSONO:     Paciente canta junto al audio 4×.  Graba 4 audios.
/// Paso 3 — COMPLETION:  Audio se silencia a la mitad; paciente completa 4×.
/// Paso 4 — REPETICIÓN:  Paciente escucha 1× y luego repite solo.
/// Paso 5 — PREGUNTA:    Muestra la pregunta; paciente responde.  Sin labios.
///
/// Todo el flujo es automático (guiado por la app).
/// El backend Python evaluará los audios; por ahora el stub devuelve éxito.
class TemExerciseScreen extends StatefulWidget {
  const TemExerciseScreen({super.key}) : args = const {};
  const TemExerciseScreen.withArgs({super.key, required this.args});

  final Map<String, dynamic> args;

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

  // ── Countdown overlay ──────────────────────────────────────────────
  bool _showCountdown = false;
  int _countdownSec = 3;
  Timer? _countdownTimer;

  // ── Estado visual del paso en curso ───────────────────────────────
  /// Paso 1: cuántas reproducciones van (0, 1, 2).
  int _paso1Plays = 0;

  /// Pasos 2/3: repetición actual 1-4.
  int _currentRepetition = 0;

  /// Paso 4: ¿ya terminó la fase de escucha?
  bool _step4ListenDone = false;

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

  /// URL HTTPS de la imagen del estímulo actual.
  String? _resolvedImageUrl;

  /// gs:// URL que produjo [_resolvedImageUrl] — para detectar cambios.
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
      await _loadAudio();
      _startCountdown();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _metronome?.cancel();
    _cancelClickTimers();
    _metronomePlayer?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════
  // Audio helpers
  // ══════════════════════════════════════════════════════════════════

  Future<String?> _resolveAudioUrl() async {
    final vm = context.read<TemSessionViewModel>();
    final raw = vm.currentStimulus?['audio_url'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      if (raw.startsWith('gs://')) {
        return await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      }
      return raw;
    } catch (e) {
      debugPrint('_resolveAudioUrl error: $e');
      return null;
    }
  }

  Future<void> _loadAudio() async {
    final url = await _resolveAudioUrl();
    if (url == null) return;
    try {
      await _audioPlayer.setUrl(url);
      _loadedAudioUrl = url;
    } catch (e) {
      debugPrint('_loadAudio error: $e');
    }
  }

  Future<void> _resolveImageUrl() async {
    final vm = context.read<TemSessionViewModel>();
    final raw = vm.currentStimulus?['imagen_url'] as String?;
    // Si ya resolvimos esta misma URL fuente, no repetir
    if (raw == _lastImageSourceUrl && _resolvedImageUrl != null) return;
    _lastImageSourceUrl = raw;
    if (raw == null || raw.isEmpty) {
      if (mounted) setState(() => _resolvedImageUrl = null);
      return;
    }
    try {
      // Usamos getDownloadURL() (igual que audio) para obtener una URL HTTPS
      // válida. getData() falla silenciosamente en Flutter Web por CORS.
      final ref = raw.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(raw)
          : FirebaseStorage.instance.ref(raw);
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() => _resolvedImageUrl = url);
        debugPrint('_resolveImageUrl OK: $url');
      }
    } catch (e) {
      debugPrint('_resolveImageUrl error: $e');
      if (mounted) setState(() => _resolvedImageUrl = null);
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
  Future<void> _playAudioAndWait({
    double volume = 1.0,
    double? muteAfterFraction,
  }) async {
    final url = await _resolveAudioUrl();
    if (url == null) return;

    // Resetear a estado idle ANTES de cargar → evita bloqueos en reproduct.
    // consecutivas del mismo URL.
    await _audioPlayer.stop();
    final loadedDuration = await _audioPlayer.setUrl(url);
    _loadedAudioUrl = url;
    await _audioPlayer.setVolume(volume);

    if (!mounted) return;
    final vm = context.read<TemSessionViewModel>();
    _startMetronomeOnPosition(vm.currentStimulus);

    // Configurar mute parcial (paso 3 — Completion).
    StreamSubscription<Duration>? posSub;
    if (muteAfterFraction != null) {
      final durMs = (loadedDuration ?? _audioPlayer.duration)?.inMilliseconds;
      if (durMs != null && durMs > 0) {
        final muteAtMs = (durMs * muteAfterFraction).round();
        posSub = _audioPlayer.positionStream.listen((pos) {
          if (pos.inMilliseconds >= muteAtMs) {
            _audioPlayer.setVolume(0);
            posSub?.cancel();
          }
        });
      }
    }

    final sw = Stopwatch()..start();
    debugPrint(
      '[REC-DBG] play() disparado — esperando ProcessingState.completed...',
    );

    // Disparar reproducción SIN await — play() en Android retorna cuando el
    // audio ARRANCA, no cuando TERMINA.
    _audioPlayer.play();

    // Esperar explícitamente a que ExoPlayer reporte fin de reproducción.
    try {
      await _audioPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
    } on StateError {
      // Stream cerrado (player disposed) — salir sin error.
    }

    sw.stop();
    debugPrint('[REC-DBG] audio terminó en ${sw.elapsedMilliseconds}ms');

    posSub?.cancel();
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

    final raw = stim?['onsets_ms'] as List?;
    if (raw == null || raw.isEmpty) return;
    final onsets = raw.map<int>((e) => (e as num).toInt()).toList();
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
    final raw = stim?['onsets_ms'] as List?;
    final Duration interval;
    final int clicks;
    if (raw != null && raw.length >= 2) {
      final onsets = raw.map<int>((e) => (e as num).toInt()).toList();
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
          .timeout(const Duration(seconds: 45));
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

    if (vm.currentStep == 1) {
      vm.advanceStep(); // paso 1 → 2 (solo escucha)
    } else if (passed) {
      vm.recordAttemptResult(1); // éxito → avanza paso
    } else {
      vm.abandonCurrentStimulus(); // fallo → nuevo estímulo
    }
    _continueOrFinish(vm);
  }

  // ══════════════════════════════════════════════════════════════════
  // Cuenta regresiva
  // ══════════════════════════════════════════════════════════════════

  void _startCountdown() {
    if (!mounted) return;
    _countdownTimer?.cancel();
    setState(() {
      _showCountdown = true;
      _countdownSec = 3;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdownSec > 1) {
        setState(() => _countdownSec--);
      } else {
        t.cancel();
        setState(() => _showCountdown = false);
        _autoBeginCurrentStep();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════
  // Flujo automático por paso
  // ══════════════════════════════════════════════════════════════════

  Future<void> _autoBeginCurrentStep() async {
    if (!mounted) return;
    final vm = context.read<TemSessionViewModel>();
    // Resolver imagen aquí — después del countdown, el estímulo ya cargó
    await _resolveImageUrl();
    _metronome?.cancel();
    _cancelClickTimers();
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
  }

  // ─── Paso 1 — ESCUCHA: reproduce 2× ─────────────────────────────

  Future<void> _runStep1(TemSessionViewModel vm) async {
    setState(() {
      _paso1Plays = 0;
      _instructionOverride = null;
    });

    // Primera reproducción
    await _playAudioAndWait();
    if (!mounted) return;

    // Segunda reproducción
    setState(() => _paso1Plays = 1);
    await _playAudioAndWait();
    if (!mounted) return;

    setState(() {
      _paso1Plays = 2;
      _waitingForContinue = true;
      _instructionOverride = '¡Listo! Escuchaste el audio';
    });
  }

  // ─── Paso 2 — UNÍSONO: 4 repeticiones mic + audio ───────────────

  Future<void> _runStep2(TemSessionViewModel vm) async {
    final attemptIds = <String>[];

    for (int rep = 1; rep <= 4; rep++) {
      if (!mounted) return;
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

    for (int rep = 1; rep <= 4; rep++) {
      if (!mounted) return;
      setState(() {
        _currentRepetition = rep;
        _instructionOverride = 'Completa la palabra ($rep/4)';
      });

      if (rep > 1) await Future.delayed(const Duration(milliseconds: 700));

      await _startRec();
      await _playAudioAndWait(volume: 1.0, muteAfterFraction: 0.5);
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

  // ──────────────────────────────────────────────────────────────────
  // Transición entre estados (paso siguiente o nuevo estímulo)
  // ──────────────────────────────────────────────────────────────────

  void _continueOrFinish(TemSessionViewModel vm) {
    if (!mounted) return;
    _metronome?.cancel();

    // Sesión terminada → navegar a resumen
    if (vm.sessionFinished) {
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
      setState(() {
        _isRecording = false;
        _isEvaluating = false;
        _waitingForContinue = false;
        _lastStepPassed = true;
        _paso1Plays = 0;
        _currentRepetition = 0;
        _step4ListenDone = false;
        _instructionOverride = null;
      });
      // Nuevo estímulo (paso 1): detener audio anterior y cargar el nuevo
      if (vm.currentStep == 1) {
        // Limpiar imagen vieja — se resolverá después del countdown
        // cuando _loadCurrentStimulus() ya haya cargado el nuevo estímulo.
        _resolvedImageUrl = null;
        _lastImageSourceUrl = null;
        await _audioPlayer.stop();
        await _loadAudio();
      }
      _startCountdown();
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
        final onsetsMs = List<int>.from(
          (stimulus?['onsets_ms'] as List?) ?? [],
        );
        final durationsMs = List<int>.from(
          (stimulus?['durations_ms'] as List?) ?? [],
        );

        return Scaffold(
          backgroundColor: _bgColor,
          appBar: AppBar(
            title: Text(instructionText),
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Barra de progreso + nivel/paso
                  _StepProgressBar(
                    currentStep: vm.currentStep,
                    totalSteps: TemSessionViewModel.totalSteps,
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
                                if (_resolvedImageUrl != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(
                                      _resolvedImageUrl!,
                                      width: 160,
                                      height: 160,
                                      fit: BoxFit.contain,
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

              // Overlay de cuenta regresiva — muestra instrucción
              if (_showCountdown)
                _CountdownOverlay(
                  seconds: _countdownSec,
                  instruction: instructionText,
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

          // Animación labial
          _LipAnimationPanel(
            stimulus: stimulus,
            audioPosition: _audioPlayer.positionStream,
          ),
          const SizedBox(height: 12),

          // Sílabas resaltadas (o texto plano si no hay datos)
          if (syllables.isNotEmpty &&
              syllables.length == onsetsMs.length &&
              syllables.length == durationsMs.length)
            SyllableHighlightWidget(
              syllables: syllables,
              onsetsMs: onsetsMs,
              durationsMs: durationsMs,
              audioPosition: _audioPlayer.positionStream,
            )
          else
            _StimulusText(texto: texto),

          const SizedBox(height: 16),

          // Imagen del estímulo
          if (_resolvedImageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                _resolvedImageUrl!,
                width: 180,
                height: 180,
                fit: BoxFit.contain,
              ),
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
                // ─── Izquierda: labios ───
                Expanded(
                  flex: 3,
                  child: _LipAnimationPanel(
                    stimulus: stimulus,
                    audioPosition: _audioPlayer.positionStream,
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
                        if (syllables.isNotEmpty &&
                            syllables.length == onsetsMs.length &&
                            syllables.length == durationsMs.length)
                          SyllableHighlightWidget(
                            syllables: syllables,
                            onsetsMs: onsetsMs,
                            durationsMs: durationsMs,
                            audioPosition: _audioPlayer.positionStream,
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
                if (_resolvedImageUrl != null)
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        _resolvedImageUrl!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionArea(TemSessionViewModel vm) {
    if (_waitingForContinue) {
      return _ContinueButton(onPressed: _onContinuePressed);
    }
    if (_isEvaluating) {
      return const _LoadingContinueButton();
    }
    switch (vm.currentStep) {
      case 1:
        return _Paso1AutoIndicator(plays: _paso1Plays);

      case 2:
      case 3:
        return _RepetitionIndicator(
          current: _currentRepetition,
          total: 4,
          isRecording: _isRecording,
          isEvaluating: _isEvaluating,
        );

      case 4:
        return _Step4Indicator(
          listenDone: _step4ListenDone,
          isRecording: _isRecording,
          isEvaluating: _isEvaluating,
        );

      case 5:
        return _Step5Indicator(
          isRecording: _isRecording,
          isEvaluating: _isEvaluating,
        );

      default:
        return const SizedBox.shrink();
    }
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

class _LipAnimationPanel extends StatefulWidget {
  final Map<String, dynamic>? stimulus;
  final Stream<Duration> audioPosition;

  const _LipAnimationPanel({
    required this.stimulus,
    required this.audioPosition,
  });

  @override
  State<_LipAnimationPanel> createState() => _LipAnimationPanelState();
}

class _LipAnimationPanelState extends State<_LipAnimationPanel> {
  LipTimeline? _timeline;

  @override
  void initState() {
    super.initState();
    _timeline = _buildTimeline(widget.stimulus);
  }

  @override
  void didUpdateWidget(_LipAnimationPanel old) {
    super.didUpdateWidget(old);
    if (old.stimulus?['id'] != widget.stimulus?['id']) {
      setState(() => _timeline = _buildTimeline(widget.stimulus));
    }
  }

  LipTimeline? _buildTimeline(Map<String, dynamic>? stim) {
    if (stim == null) return null;
    try {
      final syllables = List<String>.from((stim['syllables'] as List?) ?? []);
      final onsets = List<int>.from((stim['onsets_ms'] as List?) ?? []);
      final durations = List<int>.from((stim['durations_ms'] as List?) ?? []);
      if (syllables.isEmpty ||
          syllables.length != onsets.length ||
          syllables.length != durations.length)
        return null;
      return LipTimeline.fromStimulusJson({
        'syllables': syllables,
        'onsets_ms': onsets,
        'durations_ms': durations,
        if (stim['audio_duration_ms'] != null)
          'audio_duration_ms': stim['audio_duration_ms'],
      });
    } catch (e) {
      debugPrint('_buildTimeline error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = widget.stimulus?['texto'] as String? ?? 'mama';
    final tl = _timeline;
    return Center(
      child: SizedBox(
        width: 300,
        height: 220,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: tl != null
                ? LipAnimationWidget.fromTimeline(
                    timeline: tl,
                    audioPositionStream: widget.audioPosition,
                  )
                : LipAnimationWidget(
                    text: texto.isEmpty ? 'mama' : texto,
                    loop: true,
                    durationPerSyllable: const Duration(milliseconds: 600),
                  ),
          ),
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
            size: 36,
            color: Color(0xFFF57C00),
          ),
          const SizedBox(height: 10),
          const Text(
            'Responde con lo que aprendiste:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFFE65100)),
          ),
          const SizedBox(height: 10),
          Text(
            pregunta,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
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

class _CountdownOverlay extends StatelessWidget {
  final int seconds;
  final String? instruction;
  const _CountdownOverlay({required this.seconds, this.instruction});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (instruction != null && instruction!.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF48A63),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  instruction!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Prepárate…',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                '$seconds',
                key: ValueKey(seconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 96,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
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
          size: 48,
          color: const Color(0xFFF48A63),
        ),
        const SizedBox(height: 8),
        Text(
          allDone ? 'Audio reproducido' : 'Escucha atentamente',
          style: const TextStyle(color: Colors.black54, fontSize: 14),
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
              width: active ? 40 : 32,
              height: active ? 40 : 32,
              margin: const EdgeInsets.symmetric(horizontal: 6),
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
                      size: 18,
                    )
                  : active
                  ? const Icon(
                      Icons.volume_up_rounded,
                      color: Color(0xFFF48A63),
                      size: 20,
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
              width: active ? 18 : 13,
              height: active ? 18 : 13,
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
                      size: 10,
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
          Icon(Icons.hearing_rounded, size: 48, color: Color(0xFFF48A63)),
          SizedBox(height: 8),
          Text(
            'Escuchando el audio…',
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
      );
    }
    return Column(
      children: [
        const Icon(Icons.mic_rounded, size: 48, color: Color(0xFFF48A63)),
        const SizedBox(height: 8),
        const Text(
          '¡Tu turno!',
          style: TextStyle(
            color: Color(0xFFF48A63),
            fontSize: 16,
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
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4CAF50).withOpacity(0.15),
          ),
          child: const Icon(
            Icons.mic_rounded,
            size: 38,
            color: Color(0xFF4CAF50),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Grabando…',
          style: TextStyle(
            color: Color(0xFF4CAF50),
            fontSize: 14,
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
          style: TextStyle(color: Colors.black54, fontSize: 13),
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
        height: 56,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF48A63),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
            shadowColor: const Color(0xFFF48A63).withOpacity(0.4),
          ),
          child: const Text(
            'CONTINUAR',
            style: TextStyle(
              fontSize: 18,
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
