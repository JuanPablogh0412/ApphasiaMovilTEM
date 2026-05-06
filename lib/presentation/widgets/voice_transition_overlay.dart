import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/tem/narration_service.dart';

/// Overlay audio-driven que reemplaza el countdown 3-2-1.
///
/// Muestra una card centrada con un ícono pulsante y la frase de
/// transición correspondiente al paso. Se auto-descarta cuando
/// [NarrationService.speakAndWait] termina, o al tocar la pantalla.
/// Un timer de 6 s actúa como fallback (mute activo / fallo de red).
class VoiceTransitionOverlay extends StatefulWidget {
  const VoiceTransitionOverlay({
    super.key,
    required this.narration,
    required this.audioKey,
    required this.label,
    required this.icon,
    required this.onDone,
  });

  final NarrationService narration;

  /// Clave TTS — debe existir en tts_texts.json y en Firebase Storage.
  final String audioKey;

  /// Texto corto mostrado debajo del ícono (≤ 3 palabras).
  final String label;

  /// Ícono representativo del paso.
  final IconData icon;

  /// Llamado una única vez cuando el overlay debe cerrarse.
  final VoidCallback onDone;

  @override
  State<VoiceTransitionOverlay> createState() => _VoiceTransitionOverlayState();
}

class _VoiceTransitionOverlayState extends State<VoiceTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _fallback;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();

    // Animación de pulso del ícono.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..repeat(reverse: true);

    // Timer de seguridad: si el audio falla o está muteado, avanza igual.
    _fallback = Timer(const Duration(seconds: 6), _dismiss);

    // Reproduce el audio y descarta cuando termina.
    _playAndDismiss();
  }

  Future<void> _playAndDismiss() async {
    await widget.narration.speakAndWait(widget.audioKey);
    _dismiss();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _fallback?.cancel();
    unawaited(widget.narration.stop());
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fallback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismiss,
      child: Container(
        // Cubre toda la pantalla con overlay semitransparente.
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ícono pulsante en círculo coral.
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Transform.scale(
                    scale: 0.92 + 0.08 * _pulse.value,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFE8DD),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.icon,
                        color: const Color(0xFFF48A63),
                        size: 42,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                // Frase del paso.
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                // Indicador de interactividad.
                Text(
                  'Toca para continuar',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
