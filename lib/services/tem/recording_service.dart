import 'dart:io' show File;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Servicio de grabación de réplicas del paciente.
/// Graba WAV 16 kHz / mono / 16-bit y sube a Firebase Storage.
///
/// Sprint 1 — implementación completa.
class RecordingService {
  final _recorder = AudioRecorder();
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  /// Ruta local del WAV en curso (null si no hay grabación activa).
  String? _currentPath;

  /// Configuración de grabación obligatoria para TEM.
  static const RecordConfig kAudioConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
    bitRate: 256000,
  );

  // ------------------------------------------------------------------
  // Grabación local
  // ------------------------------------------------------------------

  /// Inicia la grabación WAV en el directorio temporal del dispositivo.
  Future<void> startRecording() async {
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw StateError(
        'Permiso de micrófono denegado. '
        'Actívalo en Ajustes → Aplicaciones → RehabilitIA → Permisos.',
      );
    }
    if (kIsWeb) {
      _currentPath = 'web_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    } else {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'tem_attempt_${DateTime.now().millisecondsSinceEpoch}.wav';
      _currentPath = '${tempDir.path}/$fileName';
    }
    await _recorder.start(kAudioConfig, path: _currentPath!);
  }

  /// Detiene la grabación y devuelve la ruta local del WAV generado.
  ///
  /// Lanza [StateError] si no había una grabación activa.
  Future<String> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null || path.isEmpty) {
      throw StateError(
        'RecordingService.stopRecording: no hay grabación activa o'
        ' el archivo no se creó.',
      );
    }
    _currentPath = null;
    return path;
  }

  // ------------------------------------------------------------------
  // Upload a Firebase Storage + doc Firestore
  // ------------------------------------------------------------------

  /// Sube el audio a Firebase Storage y crea el attempt doc en Firestore.
  ///
  /// Ruta en Storage:
  ///   `attempts/{pacienteId}/{sessionId}/{attemptId}.wav`  (web)
  ///   `attempts/{pacienteId}/{sessionId}/{attemptId}.m4a`  (móvil)
  ///
  /// Documento creado:
  ///   `sesiones_TEM/{sessionId}/attempts/{attemptId}`
  ///   con `status: "pending_analysis"` y `pending_therapist_review: true`.
  ///
  /// Devuelve el [attemptId] generado (basado en timestamp).
  Future<String> uploadAttempt({
    required String localPath,
    required String pacienteId,
    required String sessionId,
    required String stimulusId,
    required int step,
    required String stepName,
    required int attemptNumber,
  }) async {
    final attemptId = 'ATT_${sessionId}_${stimulusId}_s${step}_a$attemptNumber';
    final storagePath = 'attempts/$pacienteId/$sessionId/$attemptId.wav';

    // 1. Subir WAV a Storage
    final ref = _storage.ref(storagePath);
    final UploadTask uploadTask;
    if (kIsWeb) {
      final response = await Dio().get<List<int>>(
        localPath,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data ?? []);
      uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'audio/wav'),
      );
    } else {
      uploadTask = ref.putFile(
        File(localPath),
        SettableMetadata(contentType: 'audio/wav'),
      );
    }
    final snapshot = await uploadTask;
    final audioUrl = await snapshot.ref.getDownloadURL();

    // 2. Crear documento de attempt en Firestore
    await _firestore
        .collection('sesiones_TEM')
        .doc(sessionId)
        .collection('attempts')
        .doc(attemptId)
        .set({
          'attemptId': attemptId,
          'stimulusId': stimulusId,
          'paso': step,
          'stepName': stepName,
          'attemptNumber': attemptNumber,
          'status': 'pending_analysis',
          'audioUrl': audioUrl,
          'storagePath': storagePath,
          'pacienteId': pacienteId,
          'pending_therapist_review': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

    // 3. Limpiar archivo temporal (solo en móvil; en web es una blob URL)
    if (!kIsWeb) {
      try {
        await File(localPath).delete();
      } catch (_) {
        // Ignorar si el archivo ya no existe
      }
    }

    return attemptId;
  }

  // ------------------------------------------------------------------
  // Estado
  // ------------------------------------------------------------------

  /// Devuelve true si hay una grabación activa en este momento.
  Future<bool> get isRecording => _recorder.isRecording();

  /// Libera recursos del grabador.
  void dispose() {
    _recorder.dispose();
  }
}
