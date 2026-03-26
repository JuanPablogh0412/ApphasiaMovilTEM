// Tests de validación Sprint 0 — Módulo TEM
//
// Cubre los criterios de aceptación de Sprint 0 que son verificables con
// tests unitarios puros (sin Firebase, sin audio, sin UI).

import 'package:flutter_test/flutter_test.dart';
import 'package:aphasia_mobile/presentation/screens/tem/lip_animation/lip_timeline.dart';

void main() {
  group('Sprint 0 — LipTimeline.fromStimulusJson', () {
    // JSON mock base (válido)
    final validJson = {
      'stimulusId': 'ST_TEM_MOCK_001',
      'texto': 'mama',
      'syllables': ['ma', 'ma'],
      'onsets_ms': [0, 500],
      'durations_ms': [450, 450],
      'audio_url': '',
      'f0_template_hz': [180.0, 175.0],
      'nivel_clinico': 1,
      'fase': 'union_ritmica',
    };

    test('parsea JSON válido y genera eventos no vacíos', () {
      final timeline = LipTimeline.fromStimulusJson(validJson);
      expect(timeline.events, isNotEmpty);
    });

    test('totalDuration refleja onsets_ms.last + durations_ms.last', () {
      final timeline = LipTimeline.fromStimulusJson(validJson);
      final expectedMs = 500 + 450; // 950 ms
      expect(timeline.totalDuration.inMilliseconds, equals(expectedMs));
    });

    test('onsetsMs queda expuesto en el timeline resultante', () {
      final timeline = LipTimeline.fromStimulusJson(validJson);
      expect(timeline.onsetsMs, equals([0, 500]));
    });

    test('los eventos tienen startTime >= 0', () {
      final timeline = LipTimeline.fromStimulusJson(validJson);
      for (final event in timeline.events) {
        expect(event.startTime.inMilliseconds, greaterThanOrEqualTo(0));
      }
    });

    test(
      'los eventos del segundo sílaba empiezan en onset 500ms o después',
      () {
        final timeline = LipTimeline.fromStimulusJson(validJson);
        // Al menos algún evento debe empezar >= 500ms (el segundo sílaba)
        final hasLateEvent = timeline.events.any(
          (e) => e.startTime.inMilliseconds >= 500,
        );
        expect(hasLateEvent, isTrue);
      },
    );

    test(
      'lanza ArgumentError si syllables y onsets_ms tienen distintas longitudes',
      () {
        final badJson = {
          'syllables': ['ma', 'ma', 'extra'],
          'onsets_ms': [0, 500],
          'durations_ms': [450, 450],
        };
        expect(
          () => LipTimeline.fromStimulusJson(badJson),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('lanza ArgumentError si durations_ms difiere de syllables', () {
      final badJson = {
        'syllables': ['ca', 'sa'],
        'onsets_ms': [0, 400],
        'durations_ms': [360], // solo 1 elemento
      };
      expect(
        () => LipTimeline.fromStimulusJson(badJson),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'funciona con estímulo de 3 sílabas (carro no — pero casa, agua sí)',
      () {
        final tresSilabas = {
          'syllables': ['ca', 'ba', 'llo'],
          'onsets_ms': [0, 400, 800],
          'durations_ms': [380, 380, 500],
          'audio_url': '',
        };
        final timeline = LipTimeline.fromStimulusJson(tresSilabas);
        expect(timeline.onsetsMs.length, equals(3));
        expect(timeline.totalDuration.inMilliseconds, equals(800 + 500));
      },
    );

    test('el visema en t=0ms no es nulo', () {
      final timeline = LipTimeline.fromStimulusJson(validJson);
      final viseme = timeline.getVisemeAtTime(Duration.zero);
      expect(viseme, isNotNull);
    });
  });

  group('Sprint 0 — LipTimeline constructor básico con onsetsMs', () {
    test('constructor const acepta onsetsMs vacío por defecto', () {
      const timeline = LipTimeline(events: [], totalDuration: Duration.zero);
      expect(timeline.onsetsMs, isEmpty);
    });

    test('constructor acepta onsetsMs cuando se provee', () {
      const timeline = LipTimeline(
        events: [],
        totalDuration: Duration(milliseconds: 900),
        onsetsMs: [0, 450],
      );
      expect(timeline.onsetsMs, equals([0, 450]));
    });
  });
}
