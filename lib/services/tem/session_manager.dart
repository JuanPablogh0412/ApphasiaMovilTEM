import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'stimulus_repository.dart';

/// Servicio que construye la secuencia de estímulos de cada sesión TEM
/// aplicando las reglas anti-perseveración del protocolo MIT.
///
/// REGLAS ANTI-PERSEVERACIÓN (Helm-Estabrooks et al., 1989):
///   1. Obtener todos los estímulos del nivel_actual del paciente.
///   2. Excluir estímulos intentados en las últimas 24 h.
///   3. Excluir estímulos con 4 intentos fallidos consecutivos en
///      sesiones recientes (demasiado difíciles por ahora).
///   4. Priorizar estímulos con menos completions exitosas
///      (balance de práctica uniforme).
///   5. REGLA TONAL: no colocar dos estímulos consecutivos con el mismo
///      [patron_tonal] Y el mismo [num_silabas]
///      (ej: dos bisílabas LH seguidas → perseveración tonal).
///   6. Devolver los primeros [size] de la lista resultante.
///
/// Documento Firestore creado por [buildSession]:
///   sesiones_TEM/{sessionId}  ← detalle clínico completo
///     ejercicio_tem_id, pacienteId, nivel, estimulosSecuencia, ...
///
/// Los documentos en `ejercicios/` y `ejercicios_TEM/` son creados
/// automáticamente por una Cloud Function (onSessionCreated) que
/// escucha `sesiones_TEM/{sessionId}` y usa el SDK de admin.
///
/// Sprint 1 — implementación completa.
/// Sprint 3 — writes a ejercicios/ y ejercicios_TEM/ movidos a Cloud Function.
class SessionManager {
  final StimulusRepository repository;
  final _firestore = FirebaseFirestore.instance;

  /// ID de la sesión TEM (última creada). Expuesto para el ViewModel.
  String? lastSessionId;

  SessionManager({required this.repository});

  // ------------------------------------------------------------------
  // buildSession — algoritmo anti-perseveración
  // ------------------------------------------------------------------

  /// Construye la secuencia anti-perseveración de la sesión para [pacienteId].
  ///
  /// Aplica las 5 reglas, crea el documento `sesiones_TEM/{sessionId}`
  /// y devuelve la lista ordenada de IDs de estímulo.
  /// El ID de sesión queda disponible en [lastSessionId].
  ///
  /// [size] — número de estímulos (mínimo 10, según protocolo MIT).
  Future<List<String>> buildSession(String pacienteId, {int size = 10}) async {
    // ---- Regla 1: nivel actual del paciente ----
    final nivel = await repository.getNivelActual(pacienteId);

    // ---- Asignación del terapeuta (si existe, tiene prioridad) ----
    final asignacion = await repository.getAsignacionActiva(pacienteId);

    // ---- Regla 1: candidatos base ----
    // Si hay asignación activa, usa solo los estímulos asignados cuyo
    // nivel_clinico coincida con el nivel actual del paciente.
    // Si no quedan estímulos (asignación de otro nivel o inexistente),
    // cae al pool general del nivel.
    List<Map<String, dynamic>> allStimuli;
    if (asignacion != null) {
      final assignedIds = List<String>.from(asignacion['estimulosIds'] as List);
      final raw = await repository.getStimuliByIds(assignedIds);
      allStimuli = raw
          .where((s) => (s['nivel_clinico'] as int?) == nivel)
          .toList();
    } else {
      allStimuli = [];
    }
    // Fallback: si la asignación no tiene estímulos del nivel actual,
    // usar el pool general para ese nivel.
    if (allStimuli.isEmpty) {
      allStimuli = await repository.getStimuliForNivel(nivel);
    }

    if (allStimuli.isEmpty) {
      throw StateError(
        'No hay estímulos disponibles para nivel_clinico=$nivel.',
      );
    }

    // ---- Regla 2: excluir intentados en los últimos 7 días ----
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final recentSessions = await repository.getSessionsSince(
      pacienteId,
      cutoff,
    );

    final recentlyAttempted = <String>{};
    for (final session in recentSessions) {
      final seq = session['estimulosSecuencia'] as List<dynamic>? ?? [];
      recentlyAttempted.addAll(seq.cast<String>());
    }

    var candidates = allStimuli
        .where((s) => !recentlyAttempted.contains(s['id'] as String))
        .toList();

    // Fall-back: si quedan muy pocos, ignora la regla 2
    if (candidates.length < size) {
      candidates = List<Map<String, dynamic>>.from(allStimuli);
    }

    // ---- Regla 3: excluir estímulos con 4 fallos consecutivos ----
    // (verificación simplificada: usa el campo opcional `fallos_consecutivos`
    //  que el backend puede actualizar; si no existe, se omite la exclusión)
    candidates = candidates.where((s) {
      final fallos = (s['fallos_consecutivos'] as int?) ?? 0;
      return fallos < 4;
    }).toList();

    if (candidates.isEmpty) {
      // Si todos tienen 4 fallos, reiniciar (protocolo: nueva oportunidad)
      candidates = List<Map<String, dynamic>>.from(allStimuli);
    }

    // ---- Regla 4: priorizar estímulos con menos completions exitosas ----
    candidates.sort((a, b) {
      final aComp = (a['num_completions'] as int?) ?? 0;
      final bComp = (b['num_completions'] as int?) ?? 0;
      return aComp.compareTo(bComp); // ascendente: menos completions primero
    });

    // ---- Regla 5: anti-perseveración tonal ----
    var sequence = _applyTonalAntiPerseveration(candidates, size);

    // ---- Relleno si la asignación tiene menos de [size] estímulos ----
    // Complementa con el algoritmo base para mantener el protocolo de 10.
    if (asignacion != null && sequence.length < size) {
      final usedIds = sequence.map((s) => s['id'] as String).toSet();
      final fillPool = await repository.getStimuliForNivel(nivel);
      final fillCandidates =
          fillPool.where((s) => !usedIds.contains(s['id'] as String)).toList()
            ..sort((a, b) {
              final aC = (a['num_completions'] as int?) ?? 0;
              final bC = (b['num_completions'] as int?) ?? 0;
              return aC.compareTo(bC);
            });
      sequence = [...sequence, ...fillCandidates.take(size - sequence.length)];
    }

    final stimulusIds = sequence.map((s) => s['id'] as String).toList();

    // ---- Crear documento en Firestore ----
    // Solo se crea sesiones_TEM/{sessionId}.
    // ejercicios/{ejercicioId} y ejercicios_TEM/{ejercicioId} los crea
    // la Cloud Function onSessionCreated (SDK admin, sin restricciones).

    // ID estilo E0A1B2 (6 dígitos hex en mayúscula) igual que SR/VNEST
    final ms = DateTime.now().millisecondsSinceEpoch;
    final ejercicioId =
        'E${(ms % 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
    final sessionId = 'SES_$ms';

    await _firestore.collection('sesiones_TEM').doc(sessionId).set({
      'sessionId': sessionId,
      'ejercicio_tem_id': ejercicioId,
      'pacienteId': pacienteId,
      'nivel': nivel,
      'estimulosSecuencia': stimulusIds,
      'estimuloActualIndex': 0,
      'startedAt': FieldValue.serverTimestamp(),
      'completedAt': null,
      'scoreSesion': null,
      'status': 'in_progress',
    });

    lastSessionId = sessionId;
    return stimulusIds;
  }

  // ------------------------------------------------------------------
  // Regla 5 — tonal anti-perseveration helper (puro, testeable)
  // ------------------------------------------------------------------

  /// Construye la secuencia aplicando la regla tonal:
  /// nunca dos estímulos consecutivos con mismo [patron_tonal] Y
  /// mismo [num_silabas].
  ///
  /// Si no hay candidato válido, se añade el siguiente disponible
  /// para no bloquear la sesión.
  static List<Map<String, dynamic>> applyTonalAntiPerseveration(
    List<Map<String, dynamic>> candidates,
    int size,
  ) => _applyTonalAntiPerseveration(candidates, size);

  static List<Map<String, dynamic>> _applyTonalAntiPerseveration(
    List<Map<String, dynamic>> candidates,
    int size,
  ) {
    final sequence = <Map<String, dynamic>>[];
    final remaining = List<Map<String, dynamic>>.from(candidates);

    while (sequence.length < size && remaining.isNotEmpty) {
      final last = sequence.isNotEmpty ? sequence.last : null;

      Map<String, dynamic>? next;

      for (final candidate in remaining) {
        if (last == null || !_violatesTonalRule(last, candidate)) {
          next = candidate;
          break;
        }
      }

      // Si no hay candidato no-violador, tomar el primero disponible
      next ??= remaining.first;

      sequence.add(next);
      remaining.remove(next);
    }

    return sequence;
  }

  /// Devuelve true si añadir [candidate] después de [previous] viola
  /// la regla tonal (mismo patron_tonal Y mismo num_silabas).
  static bool _violatesTonalRule(
    Map<String, dynamic> previous,
    Map<String, dynamic> candidate,
  ) {
    final prevTonal = previous['patron_tonal'] as String?;
    final prevSilabas = previous['num_silabas'] as int?;
    final candTonal = candidate['patron_tonal'] as String?;
    final candSilabas = candidate['num_silabas'] as int?;

    // Solo viola si AMBOS coinciden y no son null
    return prevTonal != null &&
        candTonal != null &&
        prevSilabas != null &&
        candSilabas != null &&
        prevTonal == candTonal &&
        prevSilabas == candSilabas;
  }

  // ------------------------------------------------------------------
  // Marcado de estímulos
  // ------------------------------------------------------------------

  /// Marca el estímulo como completado en el doc de sesión y avanza el índice.
  Future<void> markStimulusCompleted({
    required String sessionId,
    required String stimulusId,
  }) async {
    // Obtener índice actualizado
    final doc = await _firestore
        .collection('sesiones_TEM')
        .doc(sessionId)
        .get();
    final currentIndex = (doc.data()?['estimuloActualIndex'] as int?) ?? 0;

    await _firestore.collection('sesiones_TEM').doc(sessionId).update({
      'estimuloActualIndex': currentIndex + 1,
      'completedStimuli': FieldValue.arrayUnion([stimulusId]),
    });

    // Actualizar contadores del estímulo en stimuli_TEM
    _firestore
        .collection('stimuli_TEM')
        .doc(stimulusId)
        .update({
          'num_completions': FieldValue.increment(1),
          'fallos_consecutivos': 0,
        })
        .catchError((e) => debugPrint('stimuli counter error: $e'));
  }

  /// Marca el estímulo como abandonado (4 intentos fallidos) y avanza el índice.
  Future<void> markStimulusAbandoned({
    required String sessionId,
    required String stimulusId,
  }) async {
    final doc = await _firestore
        .collection('sesiones_TEM')
        .doc(sessionId)
        .get();
    final currentIndex = (doc.data()?['estimuloActualIndex'] as int?) ?? 0;

    await _firestore.collection('sesiones_TEM').doc(sessionId).update({
      'estimuloActualIndex': currentIndex + 1,
      'abandonedStimuli': FieldValue.arrayUnion([stimulusId]),
    });

    // Actualizar contador de fallos del estímulo en stimuli_TEM
    _firestore
        .collection('stimuli_TEM')
        .doc(stimulusId)
        .update({'fallos_consecutivos': FieldValue.increment(1)})
        .catchError((e) => debugPrint('stimuli counter error: $e'));
  }

  // ------------------------------------------------------------------
  // Cierre de sesión
  // ------------------------------------------------------------------

  /// Cierra la sesión con el score final.
  /// Solo actualiza sesiones_TEM/{sessionId}.
  /// La Cloud Function onSessionCompleted detecta el cambio de status
  /// y evalúa progresión (avance automático de nivel si ≥90% en 5 consecutivas).
  Future<void> closeSession({
    required String sessionId,
    required int scoreSesion,
    required int maxScoreSesion,
  }) async {
    final scorePct = maxScoreSesion > 0
        ? (scoreSesion / maxScoreSesion * 100).roundToDouble()
        : 0.0;
    await _firestore.collection('sesiones_TEM').doc(sessionId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'scoreSesion': scoreSesion,
      'maxScoreSesion': maxScoreSesion,
      'scorePct': scorePct,
    });
  }
}
