import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Modelo de cada fase de calibración
// ═══════════════════════════════════════════════════════════════════════════

class _CalibPhase {
  final String id; // vowel_a, vowel_i, vowel_u, glide
  final String vowelDisplay; // "Aaaa", "Iiiii", …
  final String instruction; // texto corto para el paciente
  final IconData icon;
  final Color color;
  final int durationSec;

  const _CalibPhase({
    required this.id,
    required this.vowelDisplay,
    required this.instruction,
    required this.icon,
    required this.color,
    this.durationSec = 5,
  });
}

const _phases = [
  _CalibPhase(
    id: 'vowel_a',
    vowelDisplay: 'Aaaa',
    instruction: 'Mantén el sonido "Aaaa" con tu voz natural.',
    icon: Icons.record_voice_over,
    color: Color(0xFFF48A63),
  ),
  _CalibPhase(
    id: 'vowel_i',
    vowelDisplay: 'Iiiii',
    instruction: 'Ahora mantén el sonido "Iiiii" sin forzar.',
    icon: Icons.record_voice_over,
    color: Color(0xFF64B5F6),
  ),
  _CalibPhase(
    id: 'vowel_u',
    vowelDisplay: 'Uuuu',
    instruction: 'Mantén el sonido "Uuuu" de forma relajada.',
    icon: Icons.record_voice_over,
    color: Color(0xFF81C784),
  ),
  _CalibPhase(
    id: 'glide',
    vowelDisplay: 'Aaaa ↗',
    instruction: 'Di "Aaaa" empezando grave y subiendo poco a poco.',
    icon: Icons.trending_up,
    color: Color(0xFFBA68C8),
  ),
];

// ═══════════════════════════════════════════════════════════════════════════
// Pantalla principal
// ═══════════════════════════════════════════════════════════════════════════

/// Pantalla de calibración de voz multi-fase.
///
/// Protocolo pensado para pacientes con afasia de Broca:
///   1. Instrucciones visuales de preparación.
///   2. Vocal sostenida /a/ (5 s) → F0 cómodo.
///   3. Vocal sostenida /i/ (5 s) → registro alto del tracto vocal.
///   4. Vocal sostenida /u/ (5 s) → registro bajo / redondeado.
///   5. Glissando ascendente en /a/ (5 s) → rango F0 completo.
///
/// Cada fase sube un WAV a Storage con metadata:
///   `type: calibration, phase: <id>, phase_index: <0..3>,
///    total_phases: 4, pacienteId: <uid>`.
/// Solo el **último** archivo lleva `is_last: true` para que la
/// Cloud Function `on_calibration_finalized` procese el conjunto.
class TemCalibrationScreen extends StatefulWidget {
  const TemCalibrationScreen({super.key});

  @override
  State<TemCalibrationScreen> createState() => _TemCalibrationScreenState();
}

enum _ScreenStep {
  instructions,
  recording,
  uploading,
  phaseDone,
  allDone,
  error,
}

class _TemCalibrationScreenState extends State<TemCalibrationScreen> {
  static const _bgColor = Color(0xFFFFF7F2);
  static const _accentColor = Color(0xFFF48A63);

  final _recorder = AudioRecorder();

  _ScreenStep _step = _ScreenStep.instructions;
  int _phaseIndex = 0;
  int _countdown = 5;
  Timer? _timer;
  String? _errorMessage;
  String? _pacienteId;

  _CalibPhase get _currentPhase => _phases[_phaseIndex];
  bool get _isLastPhase => _phaseIndex == _phases.length - 1;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Permissions
  // ──────────────────────────────────────────────────────────────────

  Future<bool> _ensureReady() async {
    _pacienteId = FirebaseAuth.instance.currentUser?.uid;
    if (_pacienteId == null) {
      _showError('No hay sesión activa. Vuelve a iniciar sesión.');
      return false;
    }
    final granted = await _recorder.hasPermission();
    if (!granted) {
      _showError('Permiso de micrófono denegado. Actívalo en Ajustes.');
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _step = _ScreenStep.error;
      _errorMessage = msg;
    });
  }

  // ──────────────────────────────────────────────────────────────────
  // Recording flow
  // ──────────────────────────────────────────────────────────────────

  Future<void> _beginPhase() async {
    if (!await _ensureReady()) return;

    String localPath;
    if (kIsWeb) {
      localPath =
          'calib_${_currentPhase.id}_${DateTime.now().millisecondsSinceEpoch}.wav';
    } else {
      final dir = await getTemporaryDirectory();
      localPath =
          '${dir.path}/calib_${_currentPhase.id}_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: localPath,
    );

    setState(() {
      _step = _ScreenStep.recording;
      _countdown = _currentPhase.durationSec;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        t.cancel();
        await _stopAndUpload();
      }
    });
  }

  Future<void> _stopAndUpload() async {
    final path = await _recorder.stop();
    if (!mounted) return;

    if (path == null || path.isEmpty) {
      _showError('No se pudo obtener el audio grabado.');
      return;
    }

    setState(() => _step = _ScreenStep.uploading);

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath =
          'calibration/$_pacienteId/${_currentPhase.id}_$ts.wav';
      final ref = FirebaseStorage.instance.ref(storagePath);
      final metadata = SettableMetadata(
        contentType: 'audio/wav',
        customMetadata: {
          'type': 'calibration',
          'phase': _currentPhase.id,
          'phase_index': '$_phaseIndex',
          'total_phases': '${_phases.length}',
          'is_last': _isLastPhase ? 'true' : 'false',
          'pacienteId': _pacienteId!,
        },
      );

      if (kIsWeb) {
        final response = await Dio().get<List<int>>(
          path,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = Uint8List.fromList(response.data ?? []);
        await ref.putData(bytes, metadata);
      } else {
        await ref.putFile(File(path), metadata);
      }

      if (!mounted) return;
      setState(() {
        _step = _isLastPhase ? _ScreenStep.allDone : _ScreenStep.phaseDone;
      });
    } catch (e) {
      _showError('Error al guardar la calibración: $e');
    }
  }

  void _nextPhase() {
    setState(() {
      _phaseIndex++;
      _step = _ScreenStep.recording; // will start in _beginPhase
    });
    _beginPhase();
  }

  void _restart() {
    setState(() {
      _phaseIndex = 0;
      _step = _ScreenStep.instructions;
      _errorMessage = null;
    });
  }

  // ──────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text('Calibración de voz'),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _ScreenStep.instructions:
        return _InstructionsView(
          key: const ValueKey('instr'),
          onStart: _beginPhase,
        );
      case _ScreenStep.recording:
        return _RecordingPhaseView(
          key: ValueKey('rec_$_phaseIndex'),
          phase: _currentPhase,
          phaseIndex: _phaseIndex,
          totalPhases: _phases.length,
          countdown: _countdown,
        );
      case _ScreenStep.uploading:
        return const _UploadingView(key: ValueKey('upload'));
      case _ScreenStep.phaseDone:
        return _PhaseDoneView(
          key: ValueKey('done_$_phaseIndex'),
          completedPhase: _currentPhase,
          nextPhase: _phases[_phaseIndex + 1],
          phaseIndex: _phaseIndex,
          totalPhases: _phases.length,
          onNext: _nextPhase,
        );
      case _ScreenStep.allDone:
        return _AllDoneView(key: const ValueKey('allDone'), onRetry: _restart);
      case _ScreenStep.error:
        return _ErrorView(
          key: const ValueKey('err'),
          message: _errorMessage ?? 'Error desconocido',
          onRetry: _restart,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Vista 1 — Instrucciones de preparación (visual)
// ═══════════════════════════════════════════════════════════════════════════

class _InstructionsView extends StatelessWidget {
  final VoidCallback onStart;
  const _InstructionsView({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          const Text(
            'Preparemos tu calibración',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              color: Color(0xFFF48A63),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vamos a grabar 4 sonidos cortos para conocer tu voz.\nSigue estas indicaciones antes de empezar:',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Manrope',
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 28),

          // Instrucción 1 — Posición del celular
          _InstructionTile(
            icon: Icons.smartphone,
            color: const Color(0xFFF48A63),
            title: 'Sostén el celular a la altura del pecho',
            subtitle: 'A unos 20-30 cm de tu boca, sin tapar el micrófono.',
          ),
          const SizedBox(height: 16),

          // Instrucción 2 — Ambiente tranquilo
          _InstructionTile(
            icon: Icons.volume_off,
            color: const Color(0xFF64B5F6),
            title: 'Busca un lugar silencioso',
            subtitle:
                'Apaga la TV o la música. El ruido afecta la calibración.',
          ),
          const SizedBox(height: 16),

          // Instrucción 3 — Relajarse
          _InstructionTile(
            icon: Icons.self_improvement,
            color: const Color(0xFF81C784),
            title: 'Relájate y respira',
            subtitle:
                'No necesitas forzar la voz. Usa tu tono natural y cómodo.',
          ),
          const SizedBox(height: 16),

          // Instrucción 4 — Qué vamos a hacer
          _InstructionTile(
            icon: Icons.format_list_numbered,
            color: const Color(0xFFBA68C8),
            title: 'Grabaremos 4 sonidos',
            subtitle:
                'Vocal "Aaaa", vocal "Iiiii", vocal "Uuuu" y un "Aaaa" subiendo de tono. Cada uno dura solo 5 segundos.',
          ),

          const SizedBox(height: 36),

          // Vista previa de las fases
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_phases.length, (i) {
              final p = _phases[i];
              return Column(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: p.color.withOpacity(0.15),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w800,
                        color: p.color,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.vowelDisplay,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                      color: p.color,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            }),
          ),

          const SizedBox(height: 36),

          SizedBox(
            width: 200,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.mic),
              label: const Text(
                'Comenzar',
                style: TextStyle(
                  fontSize: 17,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF48A63),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InstructionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _InstructionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Vista 2 — Grabando una fase
// ═══════════════════════════════════════════════════════════════════════════

class _RecordingPhaseView extends StatelessWidget {
  final _CalibPhase phase;
  final int phaseIndex;
  final int totalPhases;
  final int countdown;

  const _RecordingPhaseView({
    super.key,
    required this.phase,
    required this.phaseIndex,
    required this.totalPhases,
    required this.countdown,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          // Progreso
          _PhaseProgressBar(current: phaseIndex, total: totalPhases),
          const SizedBox(height: 24),

          Text(
            'Sonido ${phaseIndex + 1} de $totalPhases',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 12),

          // Vocal grande
          Text(
            phase.vowelDisplay,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              fontSize: 56,
              color: phase.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            phase.instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              color: Colors.black54,
            ),
          ),

          const Spacer(),

          // Icono micrófono pulsante
          Icon(Icons.mic, size: 64, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(
            '$countdown',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              fontSize: 56,
              color: Colors.red.shade400,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Grabando…',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: Colors.red,
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Vista 3 — Fase completada (no la última)
// ═══════════════════════════════════════════════════════════════════════════

class _PhaseDoneView extends StatelessWidget {
  final _CalibPhase completedPhase;
  final _CalibPhase nextPhase;
  final int phaseIndex;
  final int totalPhases;
  final VoidCallback onNext;

  const _PhaseDoneView({
    super.key,
    required this.completedPhase,
    required this.nextPhase,
    required this.phaseIndex,
    required this.totalPhases,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          _PhaseProgressBar(current: phaseIndex + 1, total: totalPhases),
          const Spacer(),
          Icon(Icons.check_circle, size: 64, color: completedPhase.color),
          const SizedBox(height: 12),
          Text(
            '¡"${completedPhase.vowelDisplay}" listo!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: completedPhase.color,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Ahora viene: "${nextPhase.vowelDisplay}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nextPhase.instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              color: Colors.black38,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 200,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward),
              label: const Text(
                'Siguiente',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: nextPhase.color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Vista 4 — Todas las fases completadas
// ═══════════════════════════════════════════════════════════════════════════

class _AllDoneView extends StatelessWidget {
  final VoidCallback onRetry;
  const _AllDoneView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration, size: 80, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            '¡Calibración completa!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Se grabaron los 4 sonidos correctamente.\n'
            'Tu perfil de voz se está procesando en segundo plano.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Manrope',
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 32),

          // Resumen visual
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_phases.length, (i) {
              final p = _phases[i];
              return Column(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: p.color.withOpacity(0.15),
                    child: Icon(Icons.check, color: p.color, size: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.vowelDisplay,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w600,
                      color: p.color,
                      fontSize: 11,
                    ),
                  ),
                ],
              );
            }),
          ),

          const SizedBox(height: 36),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Calibrar de nuevo',
              style: TextStyle(color: Color(0xFFF48A63), fontFamily: 'Manrope'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Vista — Error
// ═══════════════════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'Manrope',
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF48A63),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: const Text(
              'Intentar de nuevo',
              style: TextStyle(fontFamily: 'Manrope'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Widget compartido — Barra de progreso de fases
// ═══════════════════════════════════════════════════════════════════════════

class _PhaseProgressBar extends StatelessWidget {
  final int current; // 0-based for "recording", or index+1 for "done"
  final int total;
  const _PhaseProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final done = i < current;
        final active = i == current;
        final color = _phases[i].color;
        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
            decoration: BoxDecoration(
              color: done
                  ? color
                  : (active ? color.withOpacity(0.4) : Colors.grey.shade200),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Vista — Uploading (compartida)
// ═══════════════════════════════════════════════════════════════════════════

class _UploadingView extends StatelessWidget {
  const _UploadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: Color(0xFFF48A63)),
        SizedBox(height: 24),
        Text(
          'Guardando audio…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Manrope',
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
