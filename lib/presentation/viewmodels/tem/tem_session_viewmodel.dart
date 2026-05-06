import 'package:flutter/foundation.dart';
import 'package:aphasia_mobile/services/tem/stimulus_repository.dart';
import 'package:aphasia_mobile/services/tem/rhythm_engine.dart';
import 'package:aphasia_mobile/services/tem/recording_service.dart';
import 'package:aphasia_mobile/services/tem/session_manager.dart';

/// ViewModel que orquesta toda la sesión TEM y la pantalla de inicio.
///
/// RESPONSABILIDADES:
///   - Carga datos del paciente para la pantalla de inicio (nivel, historial)
///   - Construye la secuencia de estímulos (vía SessionManager)
///   - Expone el estado de la sesión como propiedades observables
///   - Ejecuta la FSM clínica (pasos 1-5, intentos 1-4, abandon)
///   - Coordina StimulusRepository, RhythmEngine y RecordingService
///   - Las pantallas SOLO leen estado y llaman métodos
///
/// Sprint 1 — FSM Nivel 1 (5 pasos, score 0/1).
/// Sprint 2 — FSM Nivel 2 (4 pasos, score 0/1/2, retroceso).
class TemSessionViewModel extends ChangeNotifier {
  final StimulusRepository repository;
  final SessionManager sessionManager;
  final RhythmEngine? rhythmEngine;
  final RecordingService recordingService;

  TemSessionViewModel({
    required this.repository,
    required this.sessionManager,
    required this.recordingService,
    this.rhythmEngine,
  });

  // =====================================================================
  // ESTADO PANTALLA HOME
  // =====================================================================

  /// Nivel clínico actual del paciente (1, 2 ó 3).
  int nivelActual = 1;

  /// Número total de sesiones completadas.
  int completedSessionsCount = 0;

  /// Promedio de score de las últimas 3 sesiones (0.0 si no hay datos).
  double avgScoreLast3 = 0.0;

  /// Sesiones consecutivas con scorePct ≥ 90 % (para progresión de nivel).
  int consecutiveHighSessions = 0;

  // =====================================================================
  // ESTADO OBSERVABLE SESIÓN
  // =====================================================================

  /// ID del paciente activo
  String pacienteId = '';

  /// Estímulo activo (null = sesión no iniciada / terminada)
  Map<String, dynamic>? currentStimulus;

  /// Índice del estímulo actual dentro de la secuencia
  int currentStimulusIndex = 0;

  /// Total de estímulos en la sesión actual
  int totalStimuli = 0;

  /// Paso actual dentro del estímulo (1-5 para Nivel 1, 1-4 para Nivel 2, 1-5 para Nivel 3)
  int currentStep = 1;

  /// Total de pasos del nivel actual.
  int get totalSteps => nivelActual == 2 ? 4 : 5;

  /// Intento actual para el paso en curso (1 a maxAttempts)
  int currentAttempt = 1;

  /// Número máximo de intentos antes de abandon (protocolo MIT: 4)
  static const int maxAttempts = 4;

  /// Puntuación acumulada de la sesión
  int sessionScore = 0;

  /// Si true → la sesión está en progreso
  bool sessionActive = false;

  /// Si true → la sesión terminó — la UI debe navegar a SummaryScreen
  bool sessionFinished = false;

  /// Si true → estamos en una secuencia de retroceso (Niveles 2-3).
  bool isRetroceso = false;

  /// Paso desde el cual se inició el retroceso (null si no hay retroceso activo).
  int? retrocedFromStep;

  /// Mensaje de error para mostrar en la UI (null = sin error)
  String? errorMessage;

  /// Si true → se está cargando un recurso asíncronamente
  bool isLoading = false;

  // =====================================================================
  // ESTADO PRIVADO
  // =====================================================================

  String? _sessionId;
  List<String> _stimulusIds = [];
  final List<String> _abandonedStimuli = [];
  final List<String> _completedStimuli = [];

  // =====================================================================
  // GETTERS DE CONVENIENCIA (usados por la UI)
  // =====================================================================

  /// ID de la sesión activa.
  String? get sessionId => _sessionId;

  /// Lista de IDs de estímulos abandonados (solo lectura).
  List<String> get abandonedStimuli => List.unmodifiable(_abandonedStimuli);

  /// Lista de IDs de estímulos completados (solo lectura).
  List<String> get completedStimuli => List.unmodifiable(_completedStimuli);

  /// Nombre del paso actual para logs y UI.
  String get currentStepName {
    if (nivelActual == 1) {
      return switch (currentStep) {
        1 => 'escucha',
        2 => 'unisono',
        3 => 'completion',
        4 => 'repeticion',
        5 => 'pregunta',
        _ => 'desconocido',
      };
    }
    if (nivelActual == 3) {
      return switch (currentStep) {
        1 => 'repeticion_diferida',
        2 => 'sprechgesang_intro',
        3 => 'sprechgesang_fade',
        4 => 'repeticion_hablada',
        5 => 'pregunta_n3',
        _ => 'desconocido',
      };
    }
    // Nivel 2
    return switch (currentStep) {
      1 => 'introduccion',
      2 => 'unisono_desvanecimiento',
      3 => 'repeticion_pausa',
      4 => 'pregunta_n2',
      _ => 'desconocido',
    };
  }

  /// true si el paso actual requiere grabación.
  bool get isRecordingStep => currentStep >= 2;

  /// true si el paso actual usa metrónomo audible.
  bool get hasMetronome {
    if (nivelActual == 1) return currentStep <= 4;
    if (nivelActual == 3) return currentStep <= 3; // N3: solo P1, P2, P3
    return currentStep <= 2; // N2: solo introducción y unísono
  }

  /// true si el paso actual muestra la pregunta de texto.
  bool get showTextQuestion {
    if (nivelActual == 1) return currentStep == 5;
    if (nivelActual == 3) return currentStep == 5; // N3: paso 5 es pregunta
    return currentStep == 4; // N2: paso 4 es pregunta
  }

  /// true si el paso actual requiere pausa de 6 s antes (N2 P3-4, N3 P1/P4/P5).
  bool get hasPauseTimer {
    if (nivelActual == 3) return currentStep == 1 || currentStep >= 4;
    return nivelActual >= 2 && currentStep >= 3;
  }

  /// Puntuación máxima por estímulo según nivel.
  /// N1: 4 pts (P2-5, 1 pt c/u). N2: 5 pts (P2:1 + P3:2 + P4:2). N3: 8 pts (P1:2 + P3:2 + P4:2 + P5:2).
  int get maxScorePerStimulus {
    if (nivelActual == 1) return 4;
    if (nivelActual == 3) return 8;
    return 5; // N2
  }

  /// Texto de instrucción para cada paso.
  String get stepInstruction {
    if (nivelActual == 1) {
      return switch (currentStep) {
        1 => 'Escucha atentamente',
        2 => 'Canta junto al audio',
        3 => 'Completa la frase solo',
        4 => 'Repite solo',
        5 => 'Responde la pregunta',
        _ => '',
      };
    }
    if (nivelActual == 3) {
      return switch (currentStep) {
        1 => 'Repite después de la pausa',
        2 => 'Escucha el tono natural',
        3 => 'Completa en tono natural',
        4 => 'Repite con voz normal',
        5 => 'Responde la pregunta',
        _ => '',
      };
    }
    // Nivel 2
    return switch (currentStep) {
      1 => 'Escucha atentamente',
      2 => 'Canta y completa la frase',
      3 => 'Repite después de la pausa',
      4 => 'Responde la pregunta',
      _ => '',
    };
  }

  // =====================================================================
  // PANTALLA HOME — carga de datos
  // =====================================================================

  /// Carga los datos para la pantalla de inicio del paciente:
  /// nivel actual, número de sesiones completadas y promedio de score.
  Future<void> loadHomeData(String uid) async {
    isLoading = true;
    errorMessage = null;
    pacienteId = uid;
    notifyListeners();

    try {
      nivelActual = await repository.getNivelActual(uid);

      final completed = await repository.getCompletedSessions(uid, limit: 3);
      completedSessionsCount = completed.length;

      if (completed.isNotEmpty) {
        final scores = completed
            .map((s) => (s['scoreSesion'] as num?)?.toDouble() ?? 0.0)
            .toList();
        avgScoreLast3 = scores.reduce((a, b) => a + b) / scores.length;
      } else {
        avgScoreLast3 = 0.0;
      }

      // Verificar progresión de nivel: 5 sesiones consecutivas con ≥90%
      consecutiveHighSessions = await repository.countConsecutiveHighSessions(
        uid,
        nivel: nivelActual,
      );
      if (consecutiveHighSessions >= 5 && nivelActual < 3) {
        nivelActual++;
        consecutiveHighSessions = 0;
        await repository.setNivelActual(uid, nivelActual);
      }
    } catch (e) {
      errorMessage = 'Error al cargar datos: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // =====================================================================
  // SESIÓN — ciclo de vida
  // =====================================================================

  /// Inicia una sesión para [uid]: construye la secuencia y carga el primero.
  Future<void> startSession(String uid) async {
    isLoading = true;
    errorMessage = null;
    pacienteId = uid;
    _abandonedStimuli.clear();
    _completedStimuli.clear();
    sessionScore = 0;
    sessionFinished = false;
    isRetroceso = false;
    retrocedFromStep = null;
    notifyListeners();

    try {
      // Recargar nivel del paciente desde Firestore (pudo cambiar externamente).
      nivelActual = await repository.getNivelActual(uid);

      _stimulusIds = await sessionManager.buildSession(uid);
      _sessionId = sessionManager.lastSessionId;

      totalStimuli = _stimulusIds.length;
      currentStimulusIndex = 0;
      currentStep = 1;
      currentAttempt = 1;

      await _loadCurrentStimulus();

      sessionActive = true;
    } catch (e) {
      errorMessage = 'Error al iniciar sesión: $e';
      sessionActive = false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // =====================================================================
  // FSM DE PASOS
  // =====================================================================

  /// Avanza al siguiente paso del estímulo actual.
  /// Si ya estamos en el último paso (5), avanza al siguiente estímulo.
  void advanceStep() {
    if (currentStep < totalSteps) {
      currentStep++;
      currentAttempt = 1;
      notifyListeners();
    } else {
      // Último paso completado → estímulo completado
      _advanceStimulus(completed: true);
    }
  }

  /// Registra el resultado del intento en curso.
  ///
  /// [score] → 0 = fallo, 1 = éxito (o retroceso exitoso), 2 = éxito directo (N2).
  /// Si score > 0 → avanza al siguiente paso.
  /// Si score == 0 y estamos en el 4º intento → abandona el estímulo.
  /// [forceAdvance] → si true, avanza al siguiente paso incluso con score 0
  ///   (usado tras retroceso fallido en N2: score 0 pero se continúa).
  void recordAttemptResult(int score, {bool forceAdvance = false}) {
    sessionScore += score;

    if (score > 0 || forceAdvance) {
      // Éxito, o retroceso agotado → avanzar al siguiente paso
      advanceStep();
    } else {
      // Fallo
      if (currentAttempt >= maxAttempts) {
        abandonCurrentStimulus();
      } else {
        currentAttempt++;
        notifyListeners();
      }
    }
  }

  /// Retroceso de paso (solo Niveles 2 y 3).
  ///
  /// N2 P3 falla → retrocede a P2. N2 P4 falla → retrocede a P3.
  /// El paso de retroceso se ejecuta como reintento; si pasa,
  /// se reintenta el paso original con score máximo de 1.
  void stepBack() {
    assert(currentStep > 1, 'No se puede retroceder desde el paso 1');
    retrocedFromStep = currentStep;
    currentStep--;
    currentAttempt = 1;
    isRetroceso = true;
    notifyListeners();
  }

  /// Limpia el estado de retroceso (llamado por la pantalla tras resolver
  /// la secuencia de retroceso).
  void clearRetroceso() {
    isRetroceso = false;
    retrocedFromStep = null;
    notifyListeners();
  }

  /// Abandona el estímulo actual (4 fallos) y avanza al siguiente.
  void abandonCurrentStimulus() {
    _advanceStimulus(completed: false);
  }

  /// Finaliza la sesión: actualiza Firestore y señala a la UI.
  Future<void> finishSession() async {
    if (_sessionId == null) return;

    sessionActive = false;
    sessionFinished = true;
    notifyListeners();

    try {
      await sessionManager.closeSession(
        sessionId: _sessionId!,
        scoreSesion: sessionScore,
        maxScoreSesion: maxScorePerStimulus * totalStimuli,
      );
    } catch (e) {
      // No bloquear la UI si falla; el terapeuta puede corregirlo
      debugPrint('TemSessionViewModel.finishSession error: $e');
    }
  }

  // =====================================================================
  // HELPERS PRIVADOS
  // =====================================================================

  Future<void> _loadCurrentStimulus() async {
    if (currentStimulusIndex >= _stimulusIds.length) return;
    final stimId = _stimulusIds[currentStimulusIndex];
    currentStimulus = await repository.getStimulus(stimId);
    notifyListeners();
  }

  void _advanceStimulus({required bool completed}) {
    // Limpiar estado de retroceso al cambiar de estímulo
    isRetroceso = false;
    retrocedFromStep = null;

    final stimId = currentStimulus != null
        ? (currentStimulus!['id'] as String? ??
              currentStimulus!['stimulusId'] as String? ??
              '')
        : '';

    if (stimId.isNotEmpty) {
      if (completed) {
        _completedStimuli.add(stimId);
        sessionManager
            .markStimulusCompleted(sessionId: _sessionId!, stimulusId: stimId)
            .catchError((e) => debugPrint('markCompleted error: $e'));
      } else {
        _abandonedStimuli.add(stimId);
        sessionManager
            .markStimulusAbandoned(sessionId: _sessionId!, stimulusId: stimId)
            .catchError((e) => debugPrint('markAbandoned error: $e'));
      }
    }

    currentStimulusIndex++;

    if (currentStimulusIndex >= totalStimuli) {
      finishSession();
    } else {
      currentStep = 1;
      currentAttempt = 1;
      _loadCurrentStimulus();
    }
  }

  // =====================================================================
  // DISPOSE
  // =====================================================================

  @override
  void dispose() {
    rhythmEngine?.dispose();
    recordingService.dispose();
    super.dispose();
  }
}
