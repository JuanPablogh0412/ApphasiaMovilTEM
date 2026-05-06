import 'package:cloud_firestore/cloud_firestore.dart';

/// Repositorio de datos para estímulos TEM.
/// Accede a Firestore (stimuli_TEM, ejercicios_TEM) y Firebase Storage.
/// Sprint 1 — implementación completa.
/// Sprint 2 — adaptado a nuevo formato de estímulos (WebM, video_url, estado).
class StimulusRepository {
  final _firestore = FirebaseFirestore.instance;

  // ------------------------------------------------------------------
  // Ejercicios asignados
  // ------------------------------------------------------------------

  /// Devuelve los ejercicios TEM asignados al paciente desde
  /// la colección `ejercicios_TEM` filtrada por [pacienteId].
  Future<List<Map<String, dynamic>>> getAsignados(String pacienteId) async {
    final snap = await _firestore
        .collection('ejercicios_TEM')
        .where('pacienteId', isEqualTo: pacienteId)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ------------------------------------------------------------------
  // Datos del estímulo
  // ------------------------------------------------------------------

  /// Obtiene los metadatos del estímulo desde `stimuli_TEM/{stimulusId}`.
  /// Solo devuelve estímulos con `estado == "aprobado"`.
  Future<Map<String, dynamic>> getStimulus(String stimulusId) async {
    final doc = await _firestore
        .collection('stimuli_TEM')
        .doc(stimulusId)
        .get();
    if (!doc.exists) {
      throw StateError('Estímulo "$stimulusId" no encontrado en stimuli_TEM.');
    }
    final data = doc.data()!;
    if (data['estado'] != 'aprobado') {
      throw StateError('Estímulo "$stimulusId" no está aprobado.');
    }
    return {'id': doc.id, ...data};
  }

  // ------------------------------------------------------------------
  // Datos del paciente
  // ------------------------------------------------------------------

  /// Obtiene el nivel clínico actual del paciente desde `pacientes/{uid}`.
  /// Devuelve 1 si el campo no existe.
  Future<int> getNivelActual(String pacienteId) async {
    final doc = await _firestore.collection('pacientes').doc(pacienteId).get();
    return (doc.data()?['nivel_actual'] as int?) ?? 1;
  }

  /// Devuelve los estímulos aprobados para [nivelClinico] desde
  /// la colección `stimuli_TEM`.
  Future<List<Map<String, dynamic>>> getStimuliForNivel(
    int nivelClinico,
  ) async {
    final snap = await _firestore
        .collection('stimuli_TEM')
        .where('nivel_clinico', isEqualTo: nivelClinico)
        .where('estado', isEqualTo: 'aprobado')
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Devuelve las sesiones TEM del paciente iniciadas después de [since].
  Future<List<Map<String, dynamic>>> getSessionsSince(
    String pacienteId,
    DateTime since,
  ) async {
    final snap = await _firestore
        .collection('sesiones_TEM')
        .where('pacienteId', isEqualTo: pacienteId)
        .where('startedAt', isGreaterThan: Timestamp.fromDate(since))
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Devuelve las últimas [limit] sesiones completadas del paciente.
  Future<List<Map<String, dynamic>>> getCompletedSessions(
    String pacienteId, {
    int limit = 3,
  }) async {
    final snap = await _firestore
        .collection('sesiones_TEM')
        .where('pacienteId', isEqualTo: pacienteId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ------------------------------------------------------------------
  // Asignación del terapeuta
  // ------------------------------------------------------------------

  /// Devuelve la asignación activa del terapeuta para [pacienteId],
  /// o null si no existe ninguna.
  /// Consulta `asignaciones_TEM` donde `pacienteId == uid AND activa == true`.
  Future<Map<String, dynamic>?> getAsignacionActiva(String pacienteId) async {
    final snap = await _firestore
        .collection('asignaciones_TEM')
        .where('pacienteId', isEqualTo: pacienteId)
        .where('activa', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return {'id': doc.id, ...doc.data()};
  }

  /// Obtiene los metadatos de varios estímulos a partir de sus IDs.
  /// Omite silenciosamente los IDs que no existan o no estén aprobados.
  Future<List<Map<String, dynamic>>> getStimuliByIds(List<String> ids) async {
    final results = <Map<String, dynamic>>[];
    for (final id in ids) {
      try {
        results.add(await getStimulus(id));
      } catch (_) {
        // omitir estímulos inexistentes o no aprobados
      }
    }
    return results;
  }

  // ------------------------------------------------------------------
  // Progresión de nivel
  // ------------------------------------------------------------------

  /// Escribe el nuevo nivel clínico del paciente en `pacientes/{pacienteId}`.
  Future<void> setNivelActual(String pacienteId, int nivel) async {
    await _firestore.collection('pacientes').doc(pacienteId).update({
      'nivel_actual': nivel,
    });
  }

  /// Cuenta cuántas de las últimas [maxCheck] sesiones completadas tienen
  /// un [scorePct] ≥ [threshold]. El conteo se detiene en la primera sesión
  /// que no cumple el umbral (rachas consecutivas).
  Future<int> countConsecutiveHighSessions(
    String pacienteId, {
    int? nivel,
    double threshold = 90.0,
    int maxCheck = 5,
  }) async {
    var query = _firestore
        .collection('sesiones_TEM')
        .where('pacienteId', isEqualTo: pacienteId)
        .where('status', isEqualTo: 'completed');
    if (nivel != null) {
      query = query.where('nivel', isEqualTo: nivel);
    }
    final snap = await query
        .orderBy('completedAt', descending: true)
        .limit(maxCheck)
        .get();
    int count = 0;
    for (final doc in snap.docs) {
      final pct = (doc.data()['scorePct'] as num?)?.toDouble() ?? 0.0;
      if (pct >= threshold) {
        count++;
      } else {
        break; // racha interrumpida
      }
    }
    return count;
  }
}
