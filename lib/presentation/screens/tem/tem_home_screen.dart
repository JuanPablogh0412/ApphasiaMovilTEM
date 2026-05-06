import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../services/tem/narration_service.dart';
import '../../viewmodels/tem/tem_session_viewmodel.dart';
import '../../widgets/mute_button.dart';
import '../register/register_viewmodel.dart';
import 'speaking_indicator.dart';
import 'tem_calibration_screen.dart';
import 'tem_pre_session_screen.dart';
import 'tem_tour_overlay.dart';

/// Pantalla de inicio de la Terapia de Entonación Melódica.
///
/// Rediseño accesible para pacientes con afasia de Broca:
///   - Botón PRACTICAR grande y prominente
///   - Grid 2 columnas para Calibrar / Progreso
///   - Toggle de voz TTS
///   - Fuentes mínimas 14px, títulos 24-32px
///   - Narración TTS automática al entrar
class TemHomeScreen extends StatefulWidget {
  const TemHomeScreen({super.key});

  @override
  State<TemHomeScreen> createState() => _TemHomeScreenState();
}

class _TemHomeScreenState extends State<TemHomeScreen> {
  static const _accentColor = Color(0xFFF48A63);
  static const _bgColor = Color(0xFFFFF7F2);

  bool _isCalibrated = false;
  final NarrationService _narration = NarrationService();

  // GlobalKeys para el tour de bienvenida
  final _practicarKey = GlobalKey();
  final _calibrarKey = GlobalKey();
  final _progressKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadData();
      await _narration.init();
      // Warm-up Cloud Run para evitar cold-start en el primer ejercicio
      // ignore: unawaited_futures
      Dio()
          .get('https://backend-tem-835895355070.us-central1.run.app/health')
          .then((_) {}, onError: (_) {});
      await _narration.speakAndWait('home_bienvenida');
      if (!mounted) return;
      final tourSeen = await temTourAlreadySeen();
      if (!mounted) return;
      if (!tourSeen) {
        await showTemTour(
          context: context,
          narration: _narration,
          practicarKey: _practicarKey,
          calibrarKey: _calibrarKey,
          progressKey: _progressKey,
        );
      }
    });
  }

  @override
  void dispose() {
    _narration.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!mounted) return;

    final calFuture = FirebaseFirestore.instance
        .collection('pacientes')
        .doc(uid)
        .get()
        .then((snap) {
          final cal = snap.data()?['calibracion'];
          return cal is Map && cal['last_calibrated_at'] != null;
        })
        .catchError((_) => false);

    await context.read<TemSessionViewModel>().loadHomeData(uid);
    final calibrated = await calFuture;
    if (mounted) setState(() => _isCalibrated = calibrated);
  }

  Future<void> _onStartSession(TemSessionViewModel vm) async {
    if (!_isCalibrated) {
      _showCalibrationRequired();
      return;
    }
    await _narration.stop();
    if (!mounted) return;
    // Navegar a Pre-Session en vez de empezar directo
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: vm,
              child: TemPreSessionScreen(narration: _narration),
            ),
          ),
        )
        .then((_) {
          if (mounted) _loadData();
        });
  }

  void _showCalibrationRequired() {
    HapticFeedback.mediumImpact();
    _narration.speak('calib_intro');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 44,
                  color: _accentColor,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Calibración necesaria',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Necesitamos calibrar tu voz antes de empezar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w400,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TemCalibrationScreen(narration: _narration),
                      ),
                    ).then((result) {
                      if (result == true) {
                        if (mounted) setState(() => _isCalibrated = true);
                      } else {
                        _loadData();
                      }
                    });
                  },
                  icon: const Icon(Icons.mic_rounded, size: 28),
                  label: const Text(
                    'Calibrar',
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Ahora no',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TemSessionViewModel>(
      builder: (context, vm, _) {
        final rawNombre = context.watch<RegisterViewModel>().nombre;
        final nombre = rawNombre.isNotEmpty
            ? rawNombre.split(' ').first
            : 'Paciente';

        return Scaffold(
          backgroundColor: _bgColor,
          body: SafeArea(
            child: vm.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _accentColor),
                  )
                : Column(
                    children: [
                      // -- Botón volver + mute --------------------------
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 4,
                          top: 4,
                          right: 4,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 28,
                                color: Colors.black87,
                              ),
                              tooltip: 'Volver',
                            ),
                            const Spacer(),
                            MuteButton(narration: _narration),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // -- Logo + título --------------------------
                              Image.asset(
                                'assets/icons/brain_logo.png',
                                width: 80,
                                height: 80,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Terapia de Entonación Melódica',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _accentColor,
                                  fontSize: 18,
                                  fontFamily: 'Manrope',
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // -- Saludo -----------------------------------------
                              Text(
                                'Hola $nombre',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 32,
                                  fontFamily: 'Manrope',
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 28),

                              // ── BOTÓN PRACTICAR (prominente) ──────────────────
                              _PracticarButton(
                                key: _practicarKey,
                                nivel: vm.nivelActual,
                                onPressed: vm.isLoading
                                    ? null
                                    : () => _onStartSession(vm),
                              ),
                              const SizedBox(height: 24),

                              // ── Grid 2 columnas: Calibrar / Progreso ──────────
                              Row(
                                children: [
                                  Expanded(
                                    child: _ActionTile(
                                      key: _calibrarKey,
                                      icon: Icons.mic_rounded,
                                      label: 'Calibrar',
                                      color: const Color(0xFF64B5F6),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                TemCalibrationScreen(
                                                  narration: _narration,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _ActionTile(
                                      key: _progressKey,
                                      icon: Icons.bar_chart_rounded,
                                      label: 'Progreso',
                                      color: const Color(0xFF81C784),
                                      onTap: () {
                                        Navigator.pushNamed(
                                          context,
                                          '/tem-history',
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),

                              // ── Toggle TTS ────────────────────────────────────
                              _TtsToggle(narration: _narration),
                              const SizedBox(height: 12),
                              SpeakingIndicatorBadge(narration: _narration),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Botón PRACTICAR prominente
// ---------------------------------------------------------------------------

class _PracticarButton extends StatelessWidget {
  final int nivel;
  final VoidCallback? onPressed;
  const _PracticarButton({
    super.key,
    required this.nivel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          onPressed?.call();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF48A63),
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: const Color(0xFFF48A63).withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_filled_rounded, size: 48),
            const SizedBox(height: 8),
            const Text(
              'PRACTICAR',
              style: TextStyle(
                fontSize: 24,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nivel $nivel',
              style: const TextStyle(
                fontSize: 16,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de acción (Calibrar / Progreso)
// ---------------------------------------------------------------------------

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D2D2D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle de narración TTS
// ---------------------------------------------------------------------------

class _TtsToggle extends StatefulWidget {
  final NarrationService narration;
  const _TtsToggle({required this.narration});

  @override
  State<_TtsToggle> createState() => _TtsToggleState();
}

class _TtsToggleState extends State<_TtsToggle> {
  @override
  Widget build(BuildContext context) {
    final n = widget.narration;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.volume_up_rounded,
                size: 28,
                color: Color(0xFFF48A63),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Narración por voz',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: n.enabled,
                activeColor: const Color(0xFFF48A63),
                onChanged: (v) async {
                  await n.setEnabled(v);
                  setState(() {});
                },
              ),
            ],
          ),
          if (n.enabled) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _VoiceChip(
                  label: 'Femenina',
                  icon: Icons.woman_rounded,
                  selected: n.voice == 'female',
                  onTap: () async {
                    await n.setVoice('female');
                    setState(() {});
                  },
                ),
                const SizedBox(width: 12),
                _VoiceChip(
                  label: 'Masculina',
                  icon: Icons.man_rounded,
                  selected: n.voice == 'male',
                  onTap: () async {
                    await n.setVoice('male');
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _VoiceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF48A63).withOpacity(0.12)
              : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? const Color(0xFFF48A63) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? const Color(0xFFF48A63) : Colors.black54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Manrope',
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? const Color(0xFFF48A63) : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
