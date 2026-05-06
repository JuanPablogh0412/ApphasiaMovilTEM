import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio de narración TTS para pantallas TEM.
///
/// Reproduce audios pre-generados almacenados en Firebase Storage
/// bajo la ruta `tts/{voice}/{key}.mp3`.
///
/// Usa un [AudioPlayer] independiente para no interferir con el
/// reproductor de estímulos del RhythmEngine.
///
/// Ejemplo de uso:
/// ```dart
/// final narration = NarrationService();
/// await narration.init();          // carga preferencia de voz
/// await narration.speak('home_bienvenida');
/// await narration.stop();
/// narration.dispose();
/// ```
class NarrationService {
  NarrationService();

  final AudioPlayer _player = AudioPlayer();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Notifica cuando la narración está activa (true) o inactiva (false).
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  /// Voz activa: 'male' (default) o 'female'.
  String _voice = 'male';
  String get voice => _voice;

  /// Si la narración está habilitada globalmente.
  bool _enabled = true;
  bool get enabled => _enabled;

  /// Si la narración está silenciada por el usuario (mute rápido).
  /// Persiste entre sesiones en SharedPreferences.
  bool _muted = false;
  bool get muted => _muted;

  /// Notifica cambios de estado de mute para actualizar la UI sin setState.
  final ValueNotifier<bool> muteNotifier = ValueNotifier(false);

  /// Cache de URLs ya resueltas: key → downloadUrl.
  final Map<String, String> _urlCache = {};

  // ── Inicialización ─────────────────────────────────────────────────

  /// Carga la preferencia de voz desde Firestore y el estado de mute
  /// desde SharedPreferences (funciona sin autenticación).
  Future<void> init() async {
    // Cargar mute desde SharedPreferences (no requiere auth).
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool('tts_muted') ?? false;
      muteNotifier.value = _muted;
    } catch (_) {
      // Mantener default false si falla.
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('pacientes')
          .doc(uid)
          .get();
      final data = snap.data();
      if (data != null) {
        _voice = (data['tts_voice'] as String?) ?? 'male';
        _enabled = (data['tts_enabled'] as bool?) ?? true;
      }
    } catch (_) {
      // Usar defaults si falla la lectura.
    }
  }

  // ── Control de preferencias ────────────────────────────────────────

  /// Cambia la voz y persiste en Firestore.
  Future<void> setVoice(String voice) async {
    if (voice != 'female' && voice != 'male') return;
    _voice = voice;
    _urlCache.clear(); // las URLs cambian con la voz
    await _persistPreference();
  }

  /// Activa/desactiva narración y persiste.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) await stop();
    await _persistPreference();
  }

  /// Alterna el silencio rápido (mute).
  ///
  /// Síncrono — actualiza la UI inmediatamente.
  /// Detiene el audio en curso si se está muteando.
  /// Persiste en SharedPreferences (se recuerda entre sesiones).
  void toggleMute() {
    _muted = !_muted;
    muteNotifier.value = _muted;
    if (_muted) unawaited(stop());
    unawaited(_saveMutePreference());
  }

  Future<void> _saveMutePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tts_muted', _muted);
    } catch (_) {
      // silencioso
    }
  }

  Future<void> _persistPreference() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('pacientes').doc(uid).set({
        'tts_voice': _voice,
        'tts_enabled': _enabled,
      }, SetOptions(merge: true));
    } catch (_) {
      // silencioso
    }
  }

  // ── Reproducción ──────────────────────────────────────────────────

  /// Reproduce el audio TTS asociado a [key].
  ///
  /// Si la narración está deshabilitada, no hace nada.
  /// Si el audio ya se está reproduciendo, lo detiene primero.
  Future<void> speak(String key) async {
    if (!_enabled || _muted) return;

    try {
      final url = await _resolveUrl(key);
      if (url == null) return;

      await _player.stop();
      await _player.setUrl(url);
      isPlayingNotifier.value = true;
      await _player.play();
    } catch (_) {
      // No interrumpir la app si falla la narración.
    } finally {
      isPlayingNotifier.value = false;
    }
  }

  /// Reproduce el audio TTS y espera a que termine.
  Future<void> speakAndWait(String key) async {
    if (!_enabled || _muted) return;

    try {
      final url = await _resolveUrl(key);
      if (url == null) return;

      await _player.stop();
      await _player.setUrl(url);
      isPlayingNotifier.value = true;
      _player.play(); // no await — escuchamos el stream
      // Acepta 'completed' (fin normal) o 'idle' (stop() llamado durante reproducción)
      // para evitar que speakAndWait se quede colgado si el usuario mutea.
      await _player.playerStateStream.firstWhere(
        (s) =>
            s.processingState == ProcessingState.completed ||
            s.processingState == ProcessingState.idle,
      );
    } catch (_) {
      // silencioso
    } finally {
      isPlayingNotifier.value = false;
    }
  }

  /// Reproduce un audio desde una URL directa (e.g. audio_pregunta_url).
  Future<void> speakUrl(String url) async {
    if (!_enabled || _muted) return;
    try {
      await _player.stop();
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {
      // silencioso
    }
  }

  /// Detiene la narración en curso.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // silencioso
    } finally {
      isPlayingNotifier.value = false;
    }
  }

  /// Libera recursos. Llamar en dispose() del widget.
  void dispose() {
    _player.stop();
    _player.dispose();
    isPlayingNotifier.dispose();
    muteNotifier.dispose();
  }

  // ── Helpers internos ──────────────────────────────────────────────

  /// Resuelve la URL de descarga para `tts/{voice}/{key}.mp3`.
  ///
  /// Si el usuario no está autenticado (registro), usa la URL pública de GCS
  /// directamente (los archivos de registro son públicos por ACL).
  Future<String?> _resolveUrl(String key) async {
    final cacheKey = '$_voice/$key';
    if (_urlCache.containsKey(cacheKey)) return _urlCache[cacheKey];

    final isAuthenticated = FirebaseAuth.instance.currentUser != null;

    if (!isAuthenticated) {
      // Usar URL pública de GCS para archivos accesibles sin autenticación
      const bucket = 'apphasia-7a930.firebasestorage.app';
      final url = 'https://storage.googleapis.com/$bucket/tts/$_voice/$key.mp3';
      _urlCache[cacheKey] = url;
      return url;
    }

    try {
      final ref = _storage.ref('tts/$_voice/$key.mp3');
      final url = await ref.getDownloadURL();
      _urlCache[cacheKey] = url;
      return url;
    } catch (_) {
      return null;
    }
  }
}
