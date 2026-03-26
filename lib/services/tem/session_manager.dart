import 'package:cloud_firestore/cloud_firestore.dart';
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
/// Documentos Firestore creados por [buildSession]:
/// ┌──────────────────────────────────────────────────────────────┘
/// ejercicios/{ejercicioId}
///   creado_por, descripcion_adaptado, fecha_creacion, id, id_paciente,
///   personalizado, referencia_base, revisado, terapia, tipo
/// ┌──────────────────────────────────────────────────────────────┘
/// ejercicios_TEM/{ejercicioId}     ←← mismo patrón que ejercicios_SR
///   id_ejercicio_general: ejercicioId   (enlace a colección ejercicios)
///   nivel, estimulosSecuencia, sesion_tem_id, status, startedAt
/// ┌──────────────────────────────────────────────────────────────┘
/// sesiones_TEM/{sessionId}         ←← detalle clínico completo
///   ejercicio_tem_id: ejercicioId,  nivel, estimulosSecuencia, ...
///
/// Sprint 1 — implementación completa.
class SessionManager {
  final StimulusRepository repository;
  final _firestore = FirebaseFirestore.instance;

  /// ID del ejercicio general (último creado). Expuesto para [closeSession].
  String? lastEjercicioId;

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

    // ---- Regla 1: todos los estímulos del nivel ----
    final allStimuli = await repository.getStimuliForNivel(nivel);

    if (allStimuli.isEmpty) {
      throw StateError(
        'No hay estímulos disponibles para nivel_clinico=$nivel.',
      );
    }

    // ---- Regla 2: excluir intentados en las últimas 24 h ----
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
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
    final sequence = _applyTonalAntiPerseveration(candidates, size);

    final stimulusIds = sequence.map((s) => s['id'] as String).toList();

    // ---- Crear documentos en Firestore (batch atómico) ----
    //
    // Esquema idéntico al de SR/VNEST:
    //   ejercicios/{ejercicioId}      ← registro general común a todas las terapias
    //   ejercicios_TEM/{ejercicioId}  ← dato específico TEM con id_ejercicio_general
    //   sesiones_TEM/{sessionId}      ← detalle clínico de la sesión

    // ID estilo E0A1B2 (6 dígitos hex en mayúscula) igual que SR/VNEST
    final ms = DateTime.now().millisecondsSinceEpoch;
    final ejercicioId =
        'E${(ms % 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
    final sessionId = 'SES_$ms';

    final batch = _firestore.batch();

    // 1. ejercicios/{ejercicioId} — registro general (igual que SR/VNEST)
    final ejercicioRef = _firestore.collection('ejercicios').doc(ejercicioId);
    batch.set(ejercicioRef, {
      'id': ejercicioId,
      'creado_por': 'IA',
      'descripcion_adaptado': '',
      'fecha_creacion': FieldValue.serverTimestamp(),
      'id_paciente': pacienteId,
      'personalizado': true,
      'referencia_base': null,
      'revisado': false,
      'terapia': 'TEM',
      'tipo': 'privado',
    });

    // 2. ejercicios_TEM/{ejercicioId} — dato específico (igual que ejercicios_SR)
    //    id_ejercicio_general apunta al doc de la colección general 'ejercicios'
    final ejercicioTemRef = _firestore
        .collection('ejercicios_TEM')
        .doc(ejercicioId);
    batch.set(ejercicioTemRef, {
      'id_ejercicio_general': ejercicioId, // enlace a ejercicios/{ejercicioId}
      'sesion_tem_id': sessionId, // enlace a sesiones_TEM/{sessionId}
      'nivel': nivel,
      'estimulosSecuencia': stimulusIds,
      'status': 'in_progress',
      'startedAt': FieldValue.serverTimestamp(),
      'scoreSesion': null,
    });

    // 3. sesiones_TEM/{sessionId} — detalle clínico completo
    final sesionRef = _firestore.collection('sesiones_TEM').doc(sessionId);
    batch.set(sesionRef, {
      'sessionId': sessionId,
      'ejercicio_tem_id': ejercicioId, // enlace a ejercicios_TEM/{ejercicioId}
      'pacienteId': pacienteId,
      'nivel': nivel,
      'estimulosSecuencia': stimulusIds,
      'estimuloActualIndex': 0,
      'startedAt': FieldValue.serverTimestamp(),
      'completedAt': null,
      'scoreSesion': null,
      'status': 'in_progress',
    });

    await batch.commit();

    lastEjercicioId = ejercicioId;
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
  }

  // ------------------------------------------------------------------
  // Cierre de sesión
  // ------------------------------------------------------------------

  /// Cierra la sesión con el score final. Actualiza en batch:
  ///   sesiones_TEM/{sessionId}     → status, completedAt, scoreSesion
  ///   ejercicios_TEM/{ejercicioId} → scoreSesion, status, completedAt
  ///   ejercicios/{ejercicioId}     → revisado: false (pendiente terapeuta)
  Future<void> closeSession({
    required String sessionId,
    required int scoreSesion,
  }) async {
    // Recuperar ejercicioId desde memoria o desde el doc de sesión
    final String? ejercicioId =
        lastEjercicioId ??
        (await _firestore.collection('sesiones_TEM').doc(sessionId).get())
                .data()?['ejercicio_tem_id']
            as String?;

    final batch = _firestore.batch();

    // sesiones_TEM
    batch.update(_firestore.collection('sesiones_TEM').doc(sessionId), {
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'scoreSesion': scoreSesion,
    });

    if (ejercicioId != null) {
      // ejercicios_TEM
      batch.update(_firestore.collection('ejercicios_TEM').doc(ejercicioId), {
        'status': 'completed',
        'scoreSesion': scoreSesion,
        'completedAt': FieldValue.serverTimestamp(),
      });
      // ejercicios (registro general — marca pendiente de revisión)
      batch.update(_firestore.collection('ejercicios').doc(ejercicioId), {
        'revisado': false,
      });
    }

    await batch.commit();
  }
}
