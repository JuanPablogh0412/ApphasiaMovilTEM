import 'package:flutter/material.dart';
import '../../../services/tem/narration_service.dart';

/// Indicador visual animado que muestra si la narración TTS está activa.
///
/// Coloca este widget en el AppBar → actions de cualquier pantalla TEM:
/// ```dart
/// actions: [SpeakingIndicator(narration: _narration)],
/// ```
/// Cuando la narración está activa, muestra un círculo naranja que pulsa.
/// Cuando está inactiva, muestra un icono de altavoz estático.
class SpeakingIndicator extends StatefulWidget {
  const SpeakingIndicator({super.key, required this.narration});

  final NarrationService narration;

  @override
  State<SpeakingIndicator> createState() => _SpeakingIndicatorState();
}

class _SpeakingIndicatorState extends State<SpeakingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.35,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    widget.narration.isPlayingNotifier.addListener(_onPlayingChanged);
  }

  void _onPlayingChanged() {
    if (!mounted) return;
    if (widget.narration.isPlayingNotifier.value) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    widget.narration.isPlayingNotifier.removeListener(_onPlayingChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.narration.isPlayingNotifier,
      builder: (_, isPlaying, __) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPlaying
                    ? const Color(0xFFF48A63)
                    : Colors.white.withOpacity(0.2),
              ),
              child: Icon(
                isPlaying ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                size: 20,
                color: isPlaying ? Colors.white : Colors.white70,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Versión inline del indicador de voz para pantallas sin AppBar.
///
/// Muestra una fila con icono animado + texto "Escuchando…" cuando la
/// narración está activa. Invisible (tamaño cero) cuando está inactiva.
class SpeakingIndicatorBadge extends StatefulWidget {
  const SpeakingIndicatorBadge({super.key, required this.narration});

  final NarrationService narration;

  @override
  State<SpeakingIndicatorBadge> createState() => _SpeakingIndicatorBadgeState();
}

class _SpeakingIndicatorBadgeState extends State<SpeakingIndicatorBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    widget.narration.isPlayingNotifier.addListener(_onPlayingChanged);
  }

  void _onPlayingChanged() {
    if (!mounted) return;
    if (widget.narration.isPlayingNotifier.value) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    widget.narration.isPlayingNotifier.removeListener(_onPlayingChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.narration.isPlayingNotifier,
      builder: (_, isPlaying, __) {
        if (!isPlaying) return const SizedBox.shrink();
        return ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF48A63),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.volume_up_rounded, size: 18, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Escuchando…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
