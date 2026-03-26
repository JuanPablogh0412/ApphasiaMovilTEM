library;

import 'lip_viseme.dart';

/// Evento temporal en la animación labial
///
/// UBICACIÓN CANÓNICA: lib/data/models/tem/
/// Esta clase es un modelo de datos puro.

class LipEvent {
  final Viseme startViseme;
  final Viseme endViseme;
  final Duration duration;
  final Duration startTime;

  const LipEvent({
    required this.startViseme,
    required this.endViseme,
    required this.duration,
    required this.startTime,
  });

  Duration get endTime => startTime + duration;

  Viseme? getVisemeAtTime(Duration currentTime) {
    if (currentTime < startTime || currentTime > endTime) return null;
    final elapsed = currentTime - startTime;
    final t = elapsed.inMicroseconds / duration.inMicroseconds;
    return startViseme.lerp(endViseme, t.clamp(0.0, 1.0));
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
  final List<LipEvent> events;
  final Duration totalDuration;

  /// Tiempos de inicio (en ms) de cada sílaba en el audio real.
  /// Usado por [RhythmEngine] para disparar el metrónomo.
  final List<int> onsetsMs;

  const LipTimeline({
    required this.events,
    required this.totalDuration,
    this.onsetsMs = const [],
  });

  Viseme getVisemeAtTime(Duration currentTime) {
    for (var event in events) {
      final viseme = event.getVisemeAtTime(currentTime);
      if (viseme != null) return viseme;
    }
    return Visemes.neutral;
  }

  bool isFinished(Duration currentTime) => currentTime >= totalDuration;

  @override
  String toString() {
    return 'LipTimeline(${events.length} events, '
        'total: ${totalDuration.inMilliseconds}ms)';
  }

  // ---- factory: desde JSON de estímulo TEM --------------------------------

  /// Construye un [LipTimeline] a partir del JSON de estímulo TEM.
  ///
  /// El JSON debe contener:
  /// - `syllables`    : lista de strings con las sílabas del estímulo
  /// - `onsets_ms`    : tiempo de inicio (ms) de cada sílaba en el audio real
  /// - `durations_ms` : duración (ms) de cada sílaba en el audio real
  ///
  /// Los visemas los calcula Flutter (via [syllabify] + [generateTimeline]).
  /// Lanza [ArgumentError] si las tres listas no tienen la misma longitud.
  factory LipTimeline.fromStimulusJson(Map<String, dynamic> json) {
    final syllableStrings = List<String>.from(json['syllables'] as List);
    final durationsMs = List<int>.from(json['durations_ms'] as List);
    final onsetsMs = List<int>.from(json['onsets_ms'] as List);

    if (syllableStrings.length != durationsMs.length ||
        syllableStrings.length != onsetsMs.length) {
      throw ArgumentError(
        'Invariante TEM violada: '
        'syllables (${syllableStrings.length}), '
        'onsets_ms (${onsetsMs.length}) y '
        'durations_ms (${durationsMs.length}) deben tener la misma longitud.',
      );
    }

    final events = <LipEvent>[];

    for (int i = 0; i < syllableStrings.length; i++) {
      final syllableList = syllabify(syllableStrings[i]);
      if (syllableList.isEmpty) continue;

      final syllableTimeline = generateTimeline(syllableList, durationsMs[i]);

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

    return LipTimeline(
      events: events,
      totalDuration: Duration(milliseconds: onsetsMs.last + durationsMs.last),
      onsetsMs: onsetsMs,
    );
  }
}

// ==================== Estructura silábica ====================

class Syllable {
  final String onset;
  final String nucleus;
  final String coda;

  const Syllable({
    required this.onset,
    required this.nucleus,
    required this.coda,
  });

  String get fullText => onset + nucleus + coda;
  bool get hasOnset => onset.isNotEmpty;
  bool get hasCoda => coda.isNotEmpty;

  @override
  String toString() => 'Syllable($onset-$nucleus-$coda)';
}

// ==================== Silabificación del español ====================

const Set<String> _DIPHTHONGS = {
  'ai',
  'au',
  'ei',
  'eu',
  'oi',
  'ou',
  'ia',
  'ie',
  'io',
  'ua',
  'ue',
  'uo',
  'iu',
  'ui',
  'ái',
  'áu',
  'éi',
  'éu',
  'ói',
  'óu',
  'iá',
  'ié',
  'ió',
  'uá',
  'ué',
  'uó',
  'iú',
  'uí',
};

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

const Set<String> _DIGRAPHS = {'ch', 'll', 'rr', 'qu', 'gu'};
const Set<String> _STRONG_VOWELS = {'a', 'e', 'o', 'á', 'é', 'ó'};

/// Silabifica una palabra en español siguiendo el principio del onset máximo
List<Syllable> syllabify(String word) {
  if (word.isEmpty) return [];

  String normalized = word.toLowerCase();
  normalized = normalized
      .replaceAll('ch', 'ç')
      .replaceAll('ll', 'ł')
      .replaceAll('rr', 'ř')
      .replaceAll('qu', 'q');

  final syllables = <Syllable>[];
  int i = 0;

  while (i < normalized.length) {
    String onset = '';
    String nucleus = '';
    String coda = '';

    while (i < normalized.length && !_isVowel(normalized[i])) {
      onset += normalized[i];
      i++;
    }

    if (onset.length >= 2) {
      final lastTwo = onset.substring(onset.length - 2);
      if (!_ONSET_CLUSTERS.contains(lastTwo)) {
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

    if (i < normalized.length && _isVowel(normalized[i])) {
      nucleus += normalized[i];
      i++;
      if (i < normalized.length && _isVowel(normalized[i])) {
        final potential = nucleus + normalized[i];
        if (_DIPHTHONGS.contains(potential) ||
            _isDiphthong(nucleus, normalized[i])) {
          nucleus += normalized[i];
          i++;
        }
      }
    }

    if (i < normalized.length && !_isVowel(normalized[i])) {
      final consonantStart = i;
      int consonantCount = 0;
      while (i < normalized.length && !_isVowel(normalized[i])) {
        consonantCount++;
        i++;
      }

      if (i >= normalized.length) {
        coda = normalized.substring(consonantStart, i);
      } else {
        if (consonantCount == 1) {
          i = consonantStart;
        } else if (consonantCount >= 2) {
          final lastTwo = normalized.substring(i - 2, i);
          if (_ONSET_CLUSTERS.contains(lastTwo)) {
            if (consonantCount > 2) {
              coda = normalized.substring(consonantStart, i - 2);
              i = consonantStart + coda.length;
            } else {
              i = consonantStart;
            }
          } else {
            coda = normalized.substring(consonantStart, i - 1);
            i = consonantStart + coda.length;
          }
        }
      }
    }

    onset = _restoreDigraphs(onset);
    nucleus = _restoreDigraphs(nucleus);
    coda = _restoreDigraphs(coda);

    if (nucleus.isNotEmpty) {
      syllables.add(Syllable(onset: onset, nucleus: nucleus, coda: coda));
    }
  }

  return syllables;
}

bool _isVowel(String char) => 'aeiouáéíóúü'.contains(char);

bool _isDiphthong(String v1, String v2) {
  final isV1Strong = _STRONG_VOWELS.contains(v1);
  final isV2Strong = _STRONG_VOWELS.contains(v2);
  return isV1Strong != isV2Strong ||
      (v1 == 'i' && v2 == 'u') ||
      (v1 == 'u' && v2 == 'i');
}

String _restoreDigraphs(String text) {
  return text
      .replaceAll('ç', 'ch')
      .replaceAll('ł', 'll')
      .replaceAll('ř', 'rr')
      .replaceAll('q', 'qu');
}

// ==================== Generación de timeline ====================

String _extractPhoneme(String text) {
  if (text.isEmpty) return '';
  final lowerText = text.toLowerCase();
  if (lowerText.length >= 2) {
    final firstTwo = lowerText.substring(0, 2);
    if (_DIGRAPHS.contains(firstTwo)) return firstTwo;
  }
  return lowerText[0];
}

/// Genera [LipTimeline] desde sílabas con distribución temporal TEM
///
/// Distribución base: 30% onset / 60% nucleus / 10% coda
/// Redistribución automática si onset o coda están vacíos.
LipTimeline generateTimeline(List<Syllable> syllables, int totalDurationMs) {
  if (syllables.isEmpty) {
    return const LipTimeline(events: [], totalDuration: Duration.zero);
  }

  final events = <LipEvent>[];
  final durationPerSyllable = totalDurationMs / syllables.length;
  int currentTimeMs = 0;

  for (var syllable in syllables) {
    double onsetPercent = syllable.hasOnset ? 0.30 : 0.0;
    double codaPercent = syllable.hasCoda ? 0.10 : 0.0;
    double nucleusPercent = 1.0 - onsetPercent - codaPercent;

    final onsetDuration = (durationPerSyllable * onsetPercent).round();
    final nucleusDuration = (durationPerSyllable * nucleusPercent).round();
    final codaDuration = (durationPerSyllable * codaPercent).round();

    final onsetViseme = syllable.hasOnset
        ? Visemes.fromPhoneme(_extractPhoneme(syllable.onset))
        : Visemes.neutral;
    final codaViseme = syllable.hasCoda
        ? Visemes.fromPhoneme(_extractPhoneme(syllable.coda))
        : Visemes.neutral;

    final nucleusChars = syllable.nucleus;
    final isDiphthong =
        nucleusChars.length >= 2 &&
        _isVowel(nucleusChars[0]) &&
        _isVowel(nucleusChars[1]);

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

    if (isDiphthong) {
      final v1 = nucleusChars[0];
      final v2 = nucleusChars[1];
      final v1IsWeak = (v1 == 'i' || v1 == 'u' || v1 == 'í' || v1 == 'ú');
      final firstDuration = (nucleusDuration * (v1IsWeak ? 0.35 : 0.65))
          .round();
      final secondDuration = nucleusDuration - firstDuration;
      final v1Viseme = Visemes.fromPhoneme(v1);
      final v2Viseme = Visemes.fromPhoneme(v2);

      events.add(
        LipEvent(
          startViseme: onsetViseme,
          endViseme: v1Viseme,
          duration: Duration(milliseconds: firstDuration),
          startTime: Duration(milliseconds: currentTimeMs),
        ),
      );
      currentTimeMs += firstDuration;

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
