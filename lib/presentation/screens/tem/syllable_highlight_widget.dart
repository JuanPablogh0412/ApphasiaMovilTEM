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

  /// Texto original del estímulo (para detectar límites de palabras).
  final String? texto;

  const SyllableHighlightWidget({
    super.key,
    required this.syllables,
    required this.onsetsMs,
    required this.durationsMs,
    required this.audioPosition,
    this.texto,
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

    // Calcular índices donde empieza una nueva palabra
    final wordBreaks = _computeWordBreaks();

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
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: () {
          // Agrupar sílabas por palabra en Rows; Wrap solo corta entre palabras.
          final wordWidgets = <Widget>[];
          final currentWordSylls = <Widget>[];

          void flushWord() {
            if (currentWordSylls.isNotEmpty) {
              wordWidgets.add(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.from(currentWordSylls),
                ),
              );
              currentWordSylls.clear();
            }
          }

          for (int i = 0; i < widget.syllables.length; i++) {
            if (wordBreaks.contains(i)) flushWord();

            final isActive = i == _activeIndex;
            currentWordSylls.add(
              AnimatedScale(
                scale: isActive ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 2,
                  ),
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
              ),
            );
          }
          flushWord();
          return wordWidgets;
        }(),
      ),
    );
  }

  /// Calcula los índices de sílabas que inician una nueva palabra
  /// comparando la concatenación de sílabas contra las palabras del texto.
  Set<int> _computeWordBreaks() {
    final texto = widget.texto;
    if (texto == null || texto.isEmpty) return {};

    final words = texto.trim().split(RegExp(r'\s+'));
    if (words.length <= 1) return {};

    final breaks = <int>{};
    int syllIdx = 0;

    for (final word in words) {
      final normalizedWord = word.toLowerCase().replaceAll(
        RegExp(r'[^a-záéíóúüñ]'),
        '',
      );
      String accumulated = '';
      while (syllIdx < widget.syllables.length) {
        accumulated += widget.syllables[syllIdx].toLowerCase().replaceAll(
          RegExp(r'[^a-záéíóúüñ]'),
          '',
        );
        syllIdx++;
        if (accumulated == normalizedWord) break;
      }
      // La siguiente sílaba (si existe) inicia una nueva palabra
      if (syllIdx < widget.syllables.length) {
        breaks.add(syllIdx);
      }
    }

    return breaks;
  }
}
