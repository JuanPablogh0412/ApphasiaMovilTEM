library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'lip_viseme.dart';

/// Evento temporal en la animación labial
///
/// Representa una transición entre dos visemas durante un período de tiempo

class LipEvent {
  /// Visema de inicio
  final Viseme startViseme;

  /// Visema de destino
  final Viseme endViseme;

  /// Duración del evento
  final Duration duration;

  /// Tiempo de inicio relativo en la timeline
  final Duration startTime;

  const LipEvent({
    required this.startViseme,
    required this.endViseme,
    required this.duration,
    required this.startTime,
  });

  /// Tiempo de finalización del evento
  Duration get endTime => startTime + duration;

  /// Calcula el visema interpolado en un tiempo específico
  ///
  /// [currentTime] Tiempo actual de la animación
  ///
  /// Retorna el visema interpolado o null si está fuera del rango
  Viseme? getVisemeAtTime(Duration currentTime) {
    if (currentTime < startTime || currentTime > endTime) {
      return null;
    }

    // Calcular factor de interpolación [0.0 - 1.0]
    final elapsed = currentTime - startTime;
    final t = elapsed.inMicroseconds / duration.inMicroseconds;
    final clampedT = t.clamp(0.0, 1.0);

    // Interpolar entre visemas
    return startViseme.lerp(endViseme, clampedT);
  }

  @override
  String toString() {
    return 'LipEvent(${startViseme.name} -> ${endViseme.name}, '
        'duration: ${duration.inMilliseconds}ms, '
        'start: ${startTime.inMilliseconds}ms)';
  }
}

/// Timeline completa de eventos de animación labial
class LipTimeline {
  /// Lista ordenada de eventos
  final List<LipEvent> events;

  /// Duración total de la timeline
  final Duration totalDuration;

  /// Tiempos de inicio (en ms) de cada sílaba, tal como vienen del audio real.
  /// Vacío para timelines generados desde texto (modo autónomo).
  /// Usado por [RhythmEngine.hapticPatternMs] para disparar haptics.
  final List<int> onsetsMs;

  const LipTimeline({
    required this.events,
    required this.totalDuration,
    this.onsetsMs = const [],
  });

  /// Obtiene el visema actual en un tiempo específico
  ///
  /// [currentTime] Tiempo actual de la animación
  ///
  /// Retorna el visema interpolado o el visema neutral
  Viseme getVisemeAtTime(Duration currentTime) {
    // Buscar el evento activo
    for (var event in events) {
      final viseme = event.getVisemeAtTime(currentTime);
      if (viseme != null) {
        return viseme;
      }
    }

    // Si no hay evento activo, retornar neutral
    return Visemes.neutral;
  }

  /// Verifica si la animación ha terminado
  bool isFinished(Duration currentTime) {
    return currentTime >= totalDuration;
  }

  @override
  String toString() {
    return 'LipTimeline(${events.length} events, '
        'total: ${totalDuration.inMilliseconds}ms)';
  }

  // ---- factory: desde JSON de estímulo TEM --------------------------------

  /// Construye un [LipTimeline] a partir del JSON de estímulo TEM.
  ///
  /// Los visemas los calcula Flutter (via [syllabify] + [generateTimeline]).
  /// Los tiempos reales del audio vienen del servidor en `onsets_ms` + `durations_ms`.
  ///
  /// El JSON debe contener:
  /// - `syllables`        : lista de strings con las sílabas del estímulo
  /// - `onsets_ms`        : tiempo de inicio (ms) de cada sílaba en el audio real
  /// - `durations_ms`     : duración (ms) de cada sílaba en el audio real
  /// - `audio_duration_ms`: duración total del WAV en ms (fuente de verdad para
  ///                        la normalización del AnimationController). Si no está
  ///                        presente, se usa onsetsMs.last + durationsMs.last.
  ///
  /// El JSON NO contiene `viseme_timeline` — Flutter los genera internamente.
  ///
  /// Lanza [ArgumentError] si las tres listas no tienen la misma longitud.
  factory LipTimeline.fromStimulusJson(Map<String, dynamic> json) {
    final syllableStrings = List<String>.from(json['syllables'] as List);
    final durationsMs = List<int>.from(json['durations_ms'] as List);
    final onsetsMs = List<int>.from(json['onsets_ms'] as List);

    // Validar invariante obligatoria del módulo TEM
    if (syllableStrings.length != durationsMs.length ||
        syllableStrings.length != onsetsMs.length) {
      throw ArgumentError(
        'Invariante TEM violada: '
        'syllables (${syllableStrings.length}), '
        'onsets_ms (${onsetsMs.length}) y '
        'durations_ms (${durationsMs.length}) deben tener la misma longitud.',
      );
    }

    // Flutter calcula los visemas — los tiempos reales vienen del JSON del servidor
    final events = <LipEvent>[];

    for (int i = 0; i < syllableStrings.length; i++) {
      final syllableList = syllabify(syllableStrings[i]);
      if (syllableList.isEmpty) continue;

      // generateTimeline produce tiempos relativos dentro de la sílaba (desde 0)
      final syllableTimeline = generateTimeline(syllableList, durationsMs[i]);

      // Re-offset los eventos al tiempo real del audio (onset absoluto del JSON)
      for (final event in syllableTimeline.events) {
        events.add(
          LipEvent(
            startViseme: event.startViseme,
            endViseme: event.endViseme,
            duration: event.duration,
            startTime: Duration(milliseconds: onsetsMs[i]) + event.startTime,
          ),
        );
      }
    }

    // Duración total del WAV = fuente de verdad para el AnimationController.
    // El seed script guarda audio_duration_ms (duración exacta leída del header
    // del WAV). Si no está presente (docs viejos), calculamos desde los onsets.
    final int totalMs =
        (json['audio_duration_ms'] as num?)?.toInt() ??
        (onsetsMs.last + durationsMs.last);

    // ── Escala proporcional para garantizar sincronía perfecta ──────────────
    //
    // Whisper suele reportar un end_ms más corto que la duración real de la
    // palabra (especialmente en fricativas/sibilantes como "gracias→s" y
    // consonantes líquidas como "dolor→r"). Esto provoca que todos los visemas
    // terminen antes de que el audio concluya y la boca se congele en neutral.
    //
    // Solución: escalar TODOS los eventos proporcionalmente para que el
    // span detectado [first_onset, last_onset+last_dur] se estire hasta
    // [first_onset, audio_duration_ms].  El ritmo relativo entre sílabas
    // se preserva; solo cambia la escala temporal.  Si el span ya cubre el
    // audio completo, scale == 1.0 y no se modifica nada.
    final int wordStartMs = onsetsMs.isNotEmpty ? onsetsMs.first : 0;
    final int detectedEndMs = onsetsMs.isNotEmpty
        ? onsetsMs.last + durationsMs.last
        : totalMs;
    final int detectedSpanMs = detectedEndMs - wordStartMs;
    final int targetSpanMs = totalMs - wordStartMs;
    final double scale = (detectedSpanMs > 0 && targetSpanMs > detectedSpanMs)
        ? targetSpanMs / detectedSpanMs
        : 1.0;

    final scaledEvents = events.map((e) {
      final relStartMs = e.startTime.inMilliseconds - wordStartMs;
      final newStartMs = wordStartMs + (relStartMs * scale).round();
      final newDurMs = math.max(
        30,
        (e.duration.inMilliseconds * scale).round(),
      );
      return LipEvent(
        startViseme: e.startViseme,
        endViseme: e.endViseme,
        duration: Duration(milliseconds: newDurMs),
        startTime: Duration(milliseconds: newStartMs),
      );
    }).toList();

    // ── Logs de diagnóstico (solo en debug) ─────────────────────────────────
    if (kDebugMode) {
      final id = json['id'] ?? json['texto'] ?? '?';
      debugPrint(
        '[LipSync] $id | word=[${wordStartMs}ms..${detectedEndMs}ms] '
        'audio=${totalMs}ms | escala=${scale.toStringAsFixed(2)} '
        '(${scaledEvents.length} eventos)',
      );
      for (final e in scaledEvents) {
        debugPrint(
          '[LipSync]   ${e.startTime.inMilliseconds}ms–'
          '${e.endTime.inMilliseconds}ms  '
          '${e.startViseme.name}→${e.endViseme.name}  '
          '(${e.duration.inMilliseconds}ms)',
        );
      }
    }

    return LipTimeline(
      events: scaledEvents,
      totalDuration: Duration(milliseconds: totalMs),
      onsetsMs: onsetsMs,
    );
  }
}

// ==================== CHANGES: Nueva estructura silábica ====================

/// Clase que representa una sílaba en español con estructura onset-nucleus-coda
class Syllable {
  /// Onset: consonantes iniciales (pueden estar vacías)
  final String onset;

  /// Nucleus: vocal o diptongo (obligatorio)
  final String nucleus;

  /// Coda: consonantes finales (pueden estar vacías)
  final String coda;

  const Syllable({
    required this.onset,
    required this.nucleus,
    required this.coda,
  });

  /// Representación completa de la sílaba
  String get fullText => onset + nucleus + coda;

  /// Verifica si la sílaba tiene onset
  bool get hasOnset => onset.isNotEmpty;

  /// Verifica si la sílaba tiene coda
  bool get hasCoda => coda.isNotEmpty;

  @override
  String toString() => 'Syllable($onset-$nucleus-$coda)';
}

// ==================== CHANGES: Silabificación del español ====================

/// Diptongos válidos del español (vocal fuerte + débil o débil + fuerte)
const Set<String> _DIPHTHONGS = {
  'ai', 'au', 'ei', 'eu', 'oi', 'ou', // Decrecientes (fuerte + débil)
  'ia', 'ie', 'io', 'ua', 'ue', 'uo', // Crecientes (débil + fuerte)
  'iu', 'ui', // Dobles débiles
  'ái', 'áu', 'éi', 'éu', 'ói', 'óu', // Con acentos
  'iá', 'ié', 'ió', 'uá', 'ué', 'uó',
  'iú', 'uí',
};

/// Grupos consonánticos válidos para onset en español (maximal onset)
const Set<String> _ONSET_CLUSTERS = {
  'pr',
  'pl',
  'br',
  'bl',
  'tr',
  'dr',
  'cr',
  'cl',
  'fr',
  'fl',
  'gr',
  'gl',
};

/// Dígrafos del español (tratados como una sola consonante)
const Set<String> _DIGRAPHS = {'ch', 'll', 'rr', 'qu', 'gu'};

/// Vocales fuertes (a, e, o)
const Set<String> _STRONG_VOWELS = {'a', 'e', 'o', 'á', 'é', 'ó'};

/// Silabifica una palabra en español siguiendo el principio del onset máximo
///
/// CHANGES: Implementación COMPLETA de reglas del español
///
/// Reglas aplicadas:
/// 1. Normalizar: minúsculas, dígrafos como una sola unidad
/// 2. Detectar diptongos (grupo inseparable de vocales)
/// 3. Principio del onset máximo: asignar el mayor número de consonantes al onset
/// 4. Tratar dígrafos (ch, ll, rr, qu, gu) como consonantes simples
///
/// [word] Palabra a silabificar
/// Retorna lista de Syllable
List<Syllable> syllabify(String word) {
  if (word.isEmpty) return [];

  // Normalizar: minúsculas
  String normalized = word.toLowerCase();

  // Reemplazar dígrafos por símbolos únicos
  normalized = normalized
      .replaceAll('ch', 'ç')
      .replaceAll('ll', 'ł')
      .replaceAll('rr', 'ř')
      .replaceAll('qu', 'q');
  // NOTA: 'gu' NO se reemplaza porque solo es dígrafo antes de e/i

  final syllables = <Syllable>[];
  int i = 0;

  while (i < normalized.length) {
    String onset = '';
    String nucleus = '';
    String coda = '';

    // 1. Extraer ONSET (consonantes iniciales)
    while (i < normalized.length && !_isVowel(normalized[i])) {
      onset += normalized[i];
      i++;
    }

    // Si onset tiene más de 1 consonante, aplicar onset máximo
    if (onset.length >= 2) {
      // Verificar si las últimas 2 consonantes forman un cluster válido
      final lastTwo = onset.substring(onset.length - 2);
      if (!_ONSET_CLUSTERS.contains(lastTwo)) {
        // No es cluster válido: última consonante pasa a coda de sílaba anterior
        if (syllables.isNotEmpty) {
          final prev = syllables.removeLast();
          syllables.add(
            Syllable(
              onset: prev.onset,
              nucleus: prev.nucleus,
              coda: prev.coda + onset[0],
            ),
          );
          onset = onset.substring(1);
        }
      }
    }

    // 2. Extraer NUCLEUS (vocal o diptongo)
    if (i < normalized.length && _isVowel(normalized[i])) {
      nucleus += normalized[i];
      i++;

      // Verificar si hay diptongo
      if (i < normalized.length && _isVowel(normalized[i])) {
        final potential = nucleus + normalized[i];
        if (_DIPHTHONGS.contains(potential) ||
            _isDiphthong(nucleus, normalized[i])) {
          nucleus += normalized[i];
          i++;
        }
      }
    }

    // 3. Extraer CODA (consonantes finales hasta próxima vocal o fin)
    // CHANGES: Aplicar onset máximo correctamente
    if (i < normalized.length && !_isVowel(normalized[i])) {
      // Hay consonante(s) después de la vocal
      final consonantStart = i;
      int consonantCount = 0;

      // Contar consonantes hasta próxima vocal o fin
      while (i < normalized.length && !_isVowel(normalized[i])) {
        consonantCount++;
        i++;
      }

      if (i >= normalized.length) {
        // Final de palabra: todas las consonantes son coda
        coda = normalized.substring(consonantStart, i);
      } else {
        // Hay otra vocal después: aplicar onset máximo
        if (consonantCount == 1) {
          // 1 consonante entre vocales → onset de próxima sílaba (V-CV)
          i = consonantStart; // Retroceder, no tomar como coda
        } else if (consonantCount >= 2) {
          // 2+ consonantes: verificar cluster
          final lastTwo = normalized.substring(i - 2, i);
          if (_ONSET_CLUSTERS.contains(lastTwo)) {
            // Cluster válido: tomar todo excepto cluster como coda
            if (consonantCount > 2) {
              coda = normalized.substring(consonantStart, i - 2);
              i = consonantStart + coda.length;
            } else {
              // Solo 2 consonantes y forman cluster: ambas son onset
              i = consonantStart;
            }
          } else {
            // No es cluster: tomar todo excepto última consonante como coda
            coda = normalized.substring(consonantStart, i - 1);
            i = consonantStart + coda.length;
          }
        }
      }
    }

    // Restaurar dígrafos (convertir símbolos de vuelta)
    onset = _restoreDigraphs(onset);
    nucleus = _restoreDigraphs(nucleus);
    coda = _restoreDigraphs(coda);

    // Agregar sílaba solo si tiene nucleus
    if (nucleus.isNotEmpty) {
      syllables.add(Syllable(onset: onset, nucleus: nucleus, coda: coda));
    }
  }

  return syllables;
}

/// Verifica si un carácter es vocal
bool _isVowel(String char) {
  return 'aeiouáéíóúü'.contains(char);
}

/// Determina si dos vocales forman diptongo (regla: fuerte+débil o débil+fuerte)
bool _isDiphthong(String v1, String v2) {
  final isV1Strong = _STRONG_VOWELS.contains(v1);
  final isV2Strong = _STRONG_VOWELS.contains(v2);

  // Diptongo si una es fuerte y otra débil (no ambas fuertes ni ambas débiles)
  return isV1Strong != isV2Strong ||
      (v1 == 'i' && v2 == 'u') ||
      (v1 == 'u' && v2 == 'i');
}

/// Restaura dígrafos desde símbolos únicos
String _restoreDigraphs(String text) {
  return text
      .replaceAll('ç', 'ch')
      .replaceAll('ł', 'll')
      .replaceAll('ř', 'rr')
      .replaceAll('q', 'qu');
  // Nota: 'q' y 'g' ya están en forma simple, no necesitan restauración
}

// ==================== CHANGES: Generación de timeline con redistribución ====================

/// Extrae el fonema representativo de una cadena (detectando dígrafos)
///
/// CHANGES: Función auxiliar para detectar dígrafos en onset/nucleus/coda
///
/// [text] Texto del cual extraer fonema (onset, nucleus o coda)
/// Retorna el dígrafo completo si existe, o el primer carácter
String _extractPhoneme(String text) {
  if (text.isEmpty) return '';

  final lowerText = text.toLowerCase();

  // Detectar dígrafos comunes del español (2 caracteres)
  if (lowerText.length >= 2) {
    final firstTwo = lowerText.substring(0, 2);
    if (_DIGRAPHS.contains(firstTwo)) {
      return firstTwo; // Retornar dígrafo completo
    }
  }

  // Si no es dígrafo, retornar primer carácter
  return lowerText[0];
}

/// Genera timeline desde sílabas con distribución temporal TEM
///
/// CHANGES: Implementa redistribución temporal cuando falta onset/coda
///
/// Distribución base TEM (para monosílabo):
/// - 30% onset (consonante inicial)
/// - 60% nucleus (vocal)
/// - 10% coda (consonante final)
///
/// Redistribución:
/// - Si no hay onset: 60% + 30% = 90% para nucleus
/// - Si no hay coda: 60% + 10% = 70% para nucleus
/// - Si no hay ni onset ni coda: 100% para nucleus
///
/// [syllables] Lista de sílabas a animar
/// [totalDurationMs] Duración total de la timeline en milisegundos
/// Retorna LipTimeline
LipTimeline generateTimeline(List<Syllable> syllables, int totalDurationMs) {
  if (syllables.isEmpty) {
    return const LipTimeline(events: [], totalDuration: Duration.zero);
  }

  final events = <LipEvent>[];
  final durationPerSyllable = totalDurationMs / syllables.length;
  int currentTimeMs = 0;

  for (var syllable in syllables) {
    // Calcular porcentajes con redistribución
    double onsetPercent = syllable.hasOnset ? 0.30 : 0.0;
    double codaPercent = syllable.hasCoda ? 0.10 : 0.0;
    double nucleusPercent = 1.0 - onsetPercent - codaPercent; // Recibe el resto

    // Duración de cada parte
    final onsetDuration = (durationPerSyllable * onsetPercent).round();
    final nucleusDuration = (durationPerSyllable * nucleusPercent).round();
    final codaDuration = (durationPerSyllable * codaPercent).round();

    // CHANGES: Detectar dígrafos antes de extraer fonema
    // Visemas para cada parte
    final onsetViseme = syllable.hasOnset
        ? Visemes.fromPhoneme(_extractPhoneme(syllable.onset))
        : Visemes.neutral;
    final codaViseme = syllable.hasCoda
        ? Visemes.fromPhoneme(_extractPhoneme(syllable.coda))
        : Visemes.neutral;

    // Detectar si el nucleus es un diptongo (2 vocales)
    // CHANGES: Diptongos → 2 sub-eventos con distribución asimétrica:
    //   vocal débil (semivocal) = 35% del tiempo del nucleus (transición rápida)
    //   vocal fuerte (núcleo silábico) = 65% del tiempo del nucleus (posición sostenida)
    // Esto reproduce el gesto labial natural: deslizamiento rápido + vocal sostenida.
    final nucleusChars = syllable.nucleus;
    final isDiphthong =
        nucleusChars.length >= 2 &&
        _isVowel(nucleusChars[0]) &&
        _isVowel(nucleusChars[1]);

    // Evento 1: ONSET (si existe)
    if (syllable.hasOnset) {
      events.add(
        LipEvent(
          startViseme: Visemes.neutral,
          endViseme: onsetViseme,
          duration: Duration(milliseconds: onsetDuration),
          startTime: Duration(milliseconds: currentTimeMs),
        ),
      );
      currentTimeMs += onsetDuration;
    }

    // Evento 2: NUCLEUS — diptongo o vocal simple
    if (isDiphthong) {
      // Determinar cuál vocal es débil (i/u) y cuál es fuerte (a/e/o)
      // En diptongos crecientes (ia, ie, ua, ue...) la débil va primero → 35%
      // En diptongos decrecientes (ai, ei, au...) la débil va después → 65% primero
      final v1 = nucleusChars[0];
      final v2 = nucleusChars[1];
      final v1IsWeak = (v1 == 'i' || v1 == 'u' || v1 == 'í' || v1 == 'ú');

      // La vocal que actúa como semivocal/semisílabica recibe 35% del tiempo
      // La vocal núcleo (más audible/visible) recibe 65%
      final firstDuration = (nucleusDuration * (v1IsWeak ? 0.35 : 0.65))
          .round();
      final secondDuration = nucleusDuration - firstDuration;

      final v1Viseme = Visemes.fromPhoneme(v1);
      final v2Viseme = Visemes.fromPhoneme(v2);

      // Sub-evento 2a: primera vocal del diptongo
      events.add(
        LipEvent(
          startViseme: onsetViseme,
          endViseme: v1Viseme,
          duration: Duration(milliseconds: firstDuration),
          startTime: Duration(milliseconds: currentTimeMs),
        ),
      );
      currentTimeMs += firstDuration;

      // Sub-evento 2b: segunda vocal del diptongo
      events.add(
        LipEvent(
          startViseme: v1Viseme,
          endViseme: v2Viseme,
          duration: Duration(milliseconds: secondDuration),
          startTime: Duration(milliseconds: currentTimeMs),
        ),
      );
      currentTimeMs += secondDuration;
    } else {
      // Vocal simple → un único evento como antes
      final nucleusViseme = Visemes.fromPhoneme(_extractPhoneme(nucleusChars));
      events.add(
        LipEvent(
          startViseme: onsetViseme,
          endViseme: nucleusViseme,
          duration: Duration(milliseconds: nucleusDuration),
          startTime: Duration(milliseconds: currentTimeMs),
        ),
      );
      currentTimeMs += nucleusDuration;
    }

    // Evento 3: CODA (si existe)
    // El visema de inicio es la última vocal animada
    final lastNucleusViseme = isDiphthong
        ? Visemes.fromPhoneme(nucleusChars[nucleusChars.length - 1])
        : Visemes.fromPhoneme(_extractPhoneme(nucleusChars));

    if (syllable.hasCoda) {
      events.add(
        LipEvent(
          startViseme: lastNucleusViseme,
          endViseme: codaViseme,
          duration: Duration(milliseconds: codaDuration),
          startTime: Duration(milliseconds: currentTimeMs),
        ),
      );
      currentTimeMs += codaDuration;
    }
  }

  return LipTimeline(
    events: events,
    totalDuration: Duration(milliseconds: totalDurationMs),
  );
}
