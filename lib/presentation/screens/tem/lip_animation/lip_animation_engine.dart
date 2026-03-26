library;

import 'lip_timeline.dart' as timeline;
import 'lip_viseme.dart';

// CHANGES: Simplified to use syllabify() and generateTimeline() from lip_timeline.dart
// CHANGES: Removed duplicate Syllable class (now in lip_timeline.dart)
// CHANGES: Engine is now a thin wrapper over timeline generation functions
// CHANGES: Added detailed analysis info for debugging syllabification and viseme mapping

/// Información de análisis detallado de una sílaba
class SyllableAnalysisInfo {
  final String syllableText;
  final String onset;
  final String nucleus;
  final String coda;
  final List<PhonemeVisemeMapping> onsetMappings;
  final List<PhonemeVisemeMapping> nucleusMappings;
  final List<PhonemeVisemeMapping> codaMappings;
  final int onsetDurationMs;
  final int nucleusDurationMs;
  final int codaDurationMs;

  const SyllableAnalysisInfo({
    required this.syllableText,
    required this.onset,
    required this.nucleus,
    required this.coda,
    required this.onsetMappings,
    required this.nucleusMappings,
    required this.codaMappings,
    required this.onsetDurationMs,
    required this.nucleusDurationMs,
    required this.codaDurationMs,
  });

  int get totalDurationMs =>
      onsetDurationMs + nucleusDurationMs + codaDurationMs;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('  Sílaba: "$syllableText"');
    buffer.writeln(
        '    Estructura: onset="$onset" nucleus="$nucleus" coda="$coda"');
    buffer.writeln(
        '    Duración: onset=${onsetDurationMs}ms nucleus=${nucleusDurationMs}ms coda=${codaDurationMs}ms (total=${totalDurationMs}ms)');

    if (onsetMappings.isNotEmpty) {
      buffer.writeln('    Onset fonemas → visemas:');
      for (final mapping in onsetMappings) {
        buffer.writeln('      "$mapping"');
      }
    }

    buffer.writeln('    Nucleus fonemas → visemas:');
    for (final mapping in nucleusMappings) {
      buffer.writeln('      "$mapping"');
    }

    if (codaMappings.isNotEmpty) {
      buffer.writeln('    Coda fonemas → visemas:');
      for (final mapping in codaMappings) {
        buffer.writeln('      "$mapping"');
      }
    }

    return buffer.toString();
  }
}

/// Mapeo de un fonema a un visema
class PhonemeVisemeMapping {
  final String phoneme;
  final String visemeName;

  const PhonemeVisemeMapping(this.phoneme, this.visemeName);

  @override
  String toString() => '$phoneme → $visemeName';
}

/// Análisis completo de procesamiento de texto
class TextAnalysisInfo {
  final String originalText;
  final List<SyllableAnalysisInfo> syllables;
  final int totalDurationMs;

  const TextAnalysisInfo({
    required this.originalText,
    required this.syllables,
    required this.totalDurationMs,
  });

  // CHANGES (v2.1): Obtener índice de sílaba activa en un tiempo dado
  /// Retorna el índice de la sílaba que está siendo pronunciada en [currentTimeMs]
  /// Retorna -1 si no hay sílaba activa (antes del inicio o después del fin)
  int getActiveSyllableIndex(int currentTimeMs) {
    if (syllables.isEmpty || currentTimeMs < 0) return -1;
    
    int accumulatedTime = 0;
    
    for (int i = 0; i < syllables.length; i++) {
      final syllableDuration = syllables[i].totalDurationMs;
      
      if (currentTimeMs >= accumulatedTime && 
          currentTimeMs < accumulatedTime + syllableDuration) {
        return i;
      }
      
      accumulatedTime += syllableDuration;
    }
    
    // Después del final
    return -1;
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer
        .writeln('═══════════════════════════════════════════════════════════');
    buffer.writeln('ANÁLISIS DE ANIMACIÓN LABIAL');
    buffer
        .writeln('═══════════════════════════════════════════════════════════');
    buffer.writeln('Texto original: "$originalText"');
    buffer.writeln('Número de sílabas: ${syllables.length}');
    buffer.writeln('Duración total: ${totalDurationMs}ms');
    buffer
        .writeln('───────────────────────────────────────────────────────────');

    for (int i = 0; i < syllables.length; i++) {
      buffer.writeln('Sílaba ${i + 1}/${syllables.length}:');
      buffer.write(syllables[i]);
      if (i < syllables.length - 1) {
        buffer.writeln(
            '───────────────────────────────────────────────────────────');
      }
    }

    buffer
        .writeln('═══════════════════════════════════════════════════════════');
    return buffer.toString();
  }
}

/// Motor temporal de animación labial para TEM
///
/// Responsabilidades:
/// - Recibir texto y parámetros temporales
/// - Usar syllabify() para silabificar
/// - Delegar a generateTimeline() para crear eventos
///
/// CHANGES: Ahora es un wrapper simple sobre las funciones de lip_timeline.dart

/// Motor de animación temporal
class LipAnimationEngine {
  /// Duración por sílaba (default: 800ms)
  final Duration durationPerSyllable;

  /// Factor de elongación vocálica (default: 1.0)
  ///
  /// NOTA: Actualmente no implementado en generateTimeline()
  /// Todas las sílabas usan distribución TEM uniforme
  final double vowelStretchFactor;

  const LipAnimationEngine({
    this.durationPerSyllable = const Duration(milliseconds: 800),
    this.vowelStretchFactor = 1.0,
  }) : assert(vowelStretchFactor >= 1.0);

  /// Genera timeline de animación desde texto
  ///
  /// CHANGES: Ahora usa syllabify() y generateTimeline() de lip_timeline.dart
  ///
  /// [text] Texto de entrada (palabra o frase)
  ///
  /// Retorna timeline completa con eventos
  timeline.LipTimeline generateTimeline(String text) {
    // Silabificar usando función robusta
    final syllables = timeline.syllabify(text);

    // Si no hay sílabas, retornar timeline vacía
    if (syllables.isEmpty) {
      return const timeline.LipTimeline(
        events: [],
        totalDuration: Duration.zero,
      );
    }

    // Calcular duración total
    final totalDurationMs =
        syllables.length * durationPerSyllable.inMilliseconds;

    // Generar timeline con redistribución temporal
    return timeline.generateTimeline(syllables, totalDurationMs);
  }

  /// CHANGES: Genera análisis detallado del procesamiento de texto
  ///
  /// Muestra descomposición completa: sílabas → onset/nucleus/coda → fonemas → visemas
  ///
  /// [text] Texto de entrada a analizar
  ///
  /// Retorna información detallada de análisis que puede ser mostrada en UI o consola
  TextAnalysisInfo generateAnalysis(String text) {
    // Silabificar
    final syllables = timeline.syllabify(text);

    if (syllables.isEmpty) {
      return TextAnalysisInfo(
        originalText: text,
        syllables: [],
        totalDurationMs: 0,
      );
    }

    // Calcular duración total
    final totalDurationMs =
        syllables.length * durationPerSyllable.inMilliseconds;
    final durationPerSyllableMs = durationPerSyllable.inMilliseconds;

    // Analizar cada sílaba
    final analysisInfoList = <SyllableAnalysisInfo>[];

    for (final syl in syllables) {
      // Calcular distribución temporal TEM con redistribución
      final hasOnset = syl.onset.isNotEmpty;
      final hasCoda = syl.coda.isNotEmpty;

      double onsetPercent = hasOnset ? 0.30 : 0.0;
      double codaPercent = hasCoda ? 0.10 : 0.0;
      double nucleusPercent = 1.0 - onsetPercent - codaPercent;

      final onsetDurationMs = (durationPerSyllableMs * onsetPercent).round();
      final nucleusDurationMs =
          (durationPerSyllableMs * nucleusPercent).round();
      final codaDurationMs = (durationPerSyllableMs * codaPercent).round();

      // Mapear fonemas a visemas
      final onsetMappings = _mapPhonemesToVisemes(syl.onset);
      final nucleusMappings = _mapPhonemesToVisemes(syl.nucleus);
      final codaMappings = _mapPhonemesToVisemes(syl.coda);

      analysisInfoList.add(SyllableAnalysisInfo(
        syllableText: syl.onset + syl.nucleus + syl.coda,
        onset: syl.onset,
        nucleus: syl.nucleus,
        coda: syl.coda,
        onsetMappings: onsetMappings,
        nucleusMappings: nucleusMappings,
        codaMappings: codaMappings,
        onsetDurationMs: onsetDurationMs,
        nucleusDurationMs: nucleusDurationMs,
        codaDurationMs: codaDurationMs,
      ));
    }

    return TextAnalysisInfo(
      originalText: text,
      syllables: analysisInfoList,
      totalDurationMs: totalDurationMs,
    );
  }

  /// Mapea una cadena de fonemas a sus visemas correspondientes
  List<PhonemeVisemeMapping> _mapPhonemesToVisemes(String phonemes) {
    if (phonemes.isEmpty) return [];

    final mappings = <PhonemeVisemeMapping>[];
    final chars = phonemes.split('');

    for (final char in chars) {
      final viseme = Visemes.fromPhoneme(char);
      mappings.add(PhonemeVisemeMapping(char, viseme.name));
    }

    return mappings;
  }
}
