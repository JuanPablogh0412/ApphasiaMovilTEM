import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/tem/lip_timeline.dart';

/// Repositorio de datos para estímulos TEM.
/// Accede a Firestore (stimuli_TEM, ejercicios_TEM) y Firebase Storage.
/// Sprint 1 — implementación completa.
class StimulusRepository {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

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
  /// Incluye: texto, syllables, onsets_ms, durations_ms, audio_url,
  /// timeline_url, nivel_clinico, patron_tonal, num_silabas, etc.
  Future<Map<String, dynamic>> getStimulus(String stimulusId) async {
    final doc = await _firestore
        .collection('stimuli_TEM')
        .doc(stimulusId)
        .get();
    if (!doc.exists) {
      throw StateError('Estímulo "$stimulusId" no encontrado en stimuli_TEM.');
    }
    return {'id': doc.id, ...doc.data()!};
  }

  // ------------------------------------------------------------------
  // Timeline (JSON de visemas + onsets)
  // ------------------------------------------------------------------

  /// Descarga el JSON de la timeline desde Firebase Storage y lo
  /// parsea con [LipTimeline.fromStimulusJson].
  /// Usa caché local (SharedPreferences) para funcionar sin conexión.
  Future<LipTimeline> getTimeline(String stimulusId, String timelineUrl) async {
    // 1. Intentar caché local
    final cached = await getCachedTimeline(stimulusId);
    if (cached != null) {
      return LipTimeline.fromStimulusJson(cached);
    }

    // 2. Descargar desde Firebase Storage
    final ref = _storage.refFromURL(timelineUrl);
    final bytes = await ref.getData();
    if (bytes == null) {
      throw StateError(
        'No se pudo descargar la timeline de "$stimulusId" ($timelineUrl).',
      );
    }
    final jsonMap =
        jsonDecode(String.fromCharCodes(bytes)) as Map<String, dynamic>;

    // 3. Guardar en caché y parsear
    await cacheTimeline(stimulusId, jsonMap);
    return LipTimeline.fromStimulusJson(jsonMap);
  }

  // ------------------------------------------------------------------
  // Caché local (SharedPreferences)
  // ------------------------------------------------------------------

  /// Guarda el JSON de la timeline en SharedPreferences para uso offline.
  Future<void> cacheTimeline(
    String stimulusId,
    Map<String, dynamic> json,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tem_timeline_$stimulusId', jsonEncode(json));
  }

  /// Lee el JSON de la timeline desde SharedPreferences.
  /// Devuelve `null` si no existe.
  Future<Map<String, dynamic>?> getCachedTimeline(String stimulusId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tem_timeline_$stimulusId');
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
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

  /// Devuelve los estímulos disponibles para [nivelClinico] desde
  /// la colección `stimuli_TEM`.
  Future<List<Map<String, dynamic>>> getStimuliForNivel(
    int nivelClinico,
  ) async {
    final snap = await _firestore
        .collection('stimuli_TEM')
        .where('nivel_clinico', isEqualTo: nivelClinico)
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
}
