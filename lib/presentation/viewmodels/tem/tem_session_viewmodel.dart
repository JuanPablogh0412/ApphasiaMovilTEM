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
/// Sprint 1 — implementación completa de FSM Nivel 1.
/// Sprint 3 — FSM completa con retroceso (Niveles 2-3).
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

  /// Paso actual dentro del estímulo (1-5 para Nivel 1)
  int currentStep = 1;

  /// Total de pasos del nivel actual (5 para Nivel 1)
  static const int totalSteps = 5;

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
  String get currentStepName => switch (currentStep) {
    1 => 'escucha',
    2 => 'unisono',
    3 => 'completion',
    4 => 'repeticion',
    5 => 'pregunta',
    _ => 'desconocido',
  };

  /// true si el paso actual requiere grabación (pasos 2-5).
  bool get isRecordingStep => currentStep >= 2;

  /// true si el paso actual usa metrónomo audible (pasos 1-4).
  bool get hasMetronome => currentStep <= 4;

  /// true si el paso actual muestra la pregunta de texto (paso 5).
  bool get showTextQuestion => currentStep == 5;

  /// Texto de instrucción para cada paso.
  String get stepInstruction => switch (currentStep) {
    1 => 'Escucha atentamente',
    2 => 'Canta junto al audio',
    3 => 'Completa la frase solo',
    4 => 'Repite solo',
    5 => 'Responde la pregunta',
    _ => '',
  };

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
    notifyListeners();

    try {
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
  /// [score] → 0 = fallo, 1 = éxito.
  /// Si score > 0 → avanza al siguiente paso.
  /// Si score == 0 y estamos en el 4º intento → abandona el estímulo.
  void recordAttemptResult(int score) {
    sessionScore += score;

    if (score > 0) {
      // Éxito → avanzar al siguiente paso
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
  void stepBack() {
    // TODO(Sprint 3): implementar retroceso FSM para Niveles 2 y 3
    throw UnimplementedError('TemSessionViewModel.stepBack — Sprint 3');
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
