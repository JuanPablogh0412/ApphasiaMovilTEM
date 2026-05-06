import 'package:flutter/material.dart';
import '../../services/tem/narration_service.dart';

/// Botón de silencio rápido para la narración TTS.
///
/// Se repinta automáticamente cuando el estado de mute cambia,
/// sin necesitar [setState] en el widget padre.
///
/// Uso:
/// ```dart
/// MuteButton(narration: _narration)
/// ```
class MuteButton extends StatelessWidget {
  const MuteButton({super.key, required this.narration});

  final NarrationService narration;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: narration.muteNotifier,
      builder: (context, isMuted, _) {
        return IconButton(
          onPressed: narration.toggleMute,
          icon: Icon(
            isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          ),
          color: isMuted ? Colors.grey.shade400 : const Color(0xFFF48A63),
          iconSize: 26,
          tooltip: isMuted ? 'Activar narración' : 'Silenciar narración',
        );
      },
    );
  }
}
