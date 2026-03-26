import 'dart:async';
import 'package:flutter/material.dart';

/// Widget que muestra una palabra/frase descompuesta en sílabas y resalta
/// la sílaba activa en sincronía con la posición de un AudioPlayer.
///
/// Cada sílaba se muestra en un recuadro con borde redondeado. La sílaba
/// que se está pronunciando actualmente se subraya y se escala ligeramente
/// para dar feedback visual al paciente.
class SyllableHighlightWidget extends StatefulWidget {
  /// Lista de sílabas (ej: ['ma', 'má']).
  final List<String> syllables;

  /// Tiempos de inicio de cada sílaba en ms.
  final List<int> onsetsMs;

  /// Duraciones de cada sílaba en ms.
  final List<int> durationsMs;

  /// Stream de posición del AudioPlayer (just_audio positionStream).
  final Stream<Duration> audioPosition;

  const SyllableHighlightWidget({
    super.key,
    required this.syllables,
    required this.onsetsMs,
    required this.durationsMs,
    required this.audioPosition,
  });

  @override
  State<SyllableHighlightWidget> createState() =>
      _SyllableHighlightWidgetState();
}

class _SyllableHighlightWidgetState extends State<SyllableHighlightWidget> {
  int _activeIndex = -1;
  StreamSubscription<Duration>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(SyllableHighlightWidget old) {
    super.didUpdateWidget(old);
    if (!identical(old.audioPosition, widget.audioPosition)) {
      _sub?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _sub = widget.audioPosition.listen((pos) {
      final ms = pos.inMilliseconds;
      int idx = -1;
      for (int i = widget.onsetsMs.length - 1; i >= 0; i--) {
        if (ms >= widget.onsetsMs[i]) {
          // Check if still within this syllable's duration
          final end = widget.onsetsMs[i] + widget.durationsMs[i];
          if (ms <= end) {
            idx = i;
          }
          break;
        }
      }
      if (idx != _activeIndex && mounted) {
        setState(() => _activeIndex = idx);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.syllables.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF48A63), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.syllables.length, (i) {
          final isActive = i == _activeIndex;
          return AnimatedScale(
            scale: isActive ? 1.2 : 1.0,
            duration: const Duration(milliseconds: 180),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive
                        ? const Color(0xFFF48A63)
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                widget.syllables[i].toUpperCase(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isActive
                      ? const Color(0xFFF48A63)
                      : const Color(0xFF2D2D2D),
                  letterSpacing: 0.0,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
