// Tests de validación Sprint 1 — Módulo TEM
//
// Estrategia: sólo funciones PURAS / estáticas y un widget test sin Firebase.
//
//   1. SessionManager.applyTonalAntiPerseveration → método estático puro.
//   2. RhythmEngine.hapticPatternMs             → derivado de LipTimeline.
//   3. RecordingService.kAudioConfig             → constante estática.
//   4. TemSessionViewModel.maxAttempts            → constante estática.
//   5. TemSessionSummaryScreen.withArgs          → widget sin Provider/Firebase.
//
// Las partes que requieren Firebase (Firestore, Storage, mic) se cubren
// con tests de integración en un entorno de emuladores.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:aphasia_mobile/services/tem/session_manager.dart';
import 'package:aphasia_mobile/services/tem/rhythm_engine.dart';
import 'package:aphasia_mobile/services/tem/recording_service.dart';
import 'package:aphasia_mobile/presentation/viewmodels/tem/tem_session_viewmodel.dart';
import 'package:aphasia_mobile/presentation/screens/tem/tem_session_summary_screen.dart';
import 'package:aphasia_mobile/data/models/tem/lip_timeline.dart';
import 'package:just_audio/just_audio.dart';

// ---------------------------------------------------------------------------
// Fixtures — datos de prueba sin dependencias externas
// ---------------------------------------------------------------------------

/// Cinco estímulos con variedad de [patron_tonal] y [num_silabas].
List<Map<String, dynamic>> _buildStimuliList() => [
  {
    'id': 'ST_001',
    'patron_tonal': 'LH',
    'num_silabas': 2,
    'nivel_clinico': 1,
    'num_completions': 0,
    'texto': 'mama',
  },
  {
    'id': 'ST_002',
    'patron_tonal': 'LH',
    'num_silabas': 2,
    'nivel_clinico': 1,
    'num_completions': 0,
    'texto': 'papa',
  },
  {
    'id': 'ST_003',
    'patron_tonal': 'HL',
    'num_silabas': 2,
    'nivel_clinico': 1,
    'num_completions': 1,
    'texto': 'casa',
  },
  {
    'id': 'ST_004',
    'patron_tonal': 'LH',
    'num_silabas': 3,
    'nivel_clinico': 1,
    'num_completions': 0,
    'texto': 'caballo',
  },
  {
    'id': 'ST_005',
    'patron_tonal': 'HL',
    'num_silabas': 3,
    'nivel_clinico': 1,
    'num_completions': 2,
    'texto': 'camino',
  },
];

/// Peor caso: todos homogéneos (mismo patron_tonal + num_silabas).
List<Map<String, dynamic>> _buildHomogeneousStimuliList() => [
  {
    'id': 'H_001',
    'patron_tonal': 'LH',
    'num_silabas': 2,
    'num_completions': 0,
    'texto': 'a',
  },
  {
    'id': 'H_002',
    'patron_tonal': 'LH',
    'num_silabas': 2,
    'num_completions': 0,
    'texto': 'b',
  },
  {
    'id': 'H_003',
    'patron_tonal': 'LH',
    'num_silabas': 2,
    'num_completions': 0,
    'texto': 'c',
  },
  {
    'id': 'H_004',
    'patron_tonal': 'LH',
    'num_silabas': 2,
    'num_completions': 0,
    'texto': 'd',
  },
];

// ===========================================================================
// TESTS
// ===========================================================================

void main() {
  // =========================================================================
  // 1. SessionManager — algoritmo anti-perseveración tonal (estático puro)
  // =========================================================================
  group('Sprint1 / SessionManager.applyTonalAntiPerseveration', () {
    test('retorna lista del tamaño solicitado', () {
      final stimuli = _buildStimuliList();
      final result = SessionManager.applyTonalAntiPerseveration(stimuli, 3);
      expect(result.length, equals(3));
    });

    test('retorna todos cuando size > número de candidatos', () {
      final stimuli = _buildStimuliList();
      final result = SessionManager.applyTonalAntiPerseveration(
        stimuli,
        stimuli.length + 10,
      );
      expect(result.length, equals(stimuli.length));
    });

    test('lista vacía → resultado vacío', () {
      final result = SessionManager.applyTonalAntiPerseveration([], 5);
      expect(result, isEmpty);
    });

    test('no hay dos consecutivos con MISMO patron_tonal Y num_silabas', () {
      final stimuli = _buildStimuliList();
      final result = SessionManager.applyTonalAntiPerseveration(
        stimuli,
        stimuli.length,
      );
      for (int i = 1; i < result.length; i++) {
        final prev = result[i - 1];
        final curr = result[i];
        final sameTonal = prev['patron_tonal'] == curr['patron_tonal'];
        final sameSilabas = prev['num_silabas'] == curr['num_silabas'];
        expect(
          sameTonal && sameSilabas,
          isFalse,
          reason:
              '${prev['id']} (${prev['patron_tonal']}/${prev['num_silabas']}) '
              '→ ${curr['id']} (${curr['patron_tonal']}/${curr['num_silabas']}) '
              'violan la regla tonal',
        );
      }
    });

    test('caso homogéneo: resultado sin IDs duplicados aunque no se pueda '
        'satisfacer la regla tonal', () {
      final stimuli = _buildHomogeneousStimuliList();
      final result = SessionManager.applyTonalAntiPerseveration(
        stimuli,
        stimuli.length,
      );
      final ids = result.map((s) => s['id']).toSet();
      expect(
        ids.length,
        equals(result.length),
        reason: 'No debe haber estímulos duplicados en la secuencia',
      );
    });

    test('estímulos sin patron_tonal no causan excepción', () {
      final sinTonal = [
        {'id': 'A', 'texto': 'uno', 'num_completions': 0},
        {'id': 'B', 'texto': 'dos', 'num_completions': 0},
        {'id': 'C', 'texto': 'tres', 'num_completions': 0},
      ];
      expect(
        () => SessionManager.applyTonalAntiPerseveration(sinTonal, 3),
        isNot(throwsException),
      );
    });

    test('mismo patron_tonal pero distinto num_silabas → ambos aparecen', () {
      final mixedSilabas = [
        {
          'id': 'M_001',
          'patron_tonal': 'LH',
          'num_silabas': 2,
          'num_completions': 0,
        },
        {
          'id': 'M_002',
          'patron_tonal': 'LH',
          'num_silabas': 3,
          'num_completions': 0,
        },
      ];
      final result = SessionManager.applyTonalAntiPerseveration(
        mixedSilabas,
        2,
      );
      expect(result.length, equals(2));
    });

    test('distinto patron_tonal pero mismo num_silabas → ambos aparecen', () {
      final mixedTonal = [
        {
          'id': 'T_001',
          'patron_tonal': 'LH',
          'num_silabas': 2,
          'num_completions': 0,
        },
        {
          'id': 'T_002',
          'patron_tonal': 'HL',
          'num_silabas': 2,
          'num_completions': 0,
        },
      ];
      final result = SessionManager.applyTonalAntiPerseveration(mixedTonal, 2);
      expect(result.length, equals(2));
    });
  });

  // =========================================================================
  // 2. RhythmEngine — hapticPatternMs (puro sobre LipTimeline)
  // =========================================================================
  group('Sprint1 / RhythmEngine', () {
    final testJson = {
      'syllables': ['ma', 'ma'],
      'onsets_ms': [0, 500],
      'durations_ms': [450, 450],
    };

    test('hapticPatternMs coincide exactamente con onsets_ms del timeline', () {
      final timeline = LipTimeline.fromStimulusJson(testJson);
      final engine = RhythmEngine(
        timeline: timeline,
        audioPlayer: AudioPlayer(),
      );
      expect(engine.hapticPatternMs, equals([0, 500]));
      engine.dispose();
    });

    test('hapticPatternMs devuelve COPIA — mutarla no afecta el engine', () {
      final timeline = LipTimeline.fromStimulusJson(testJson);
      final engine = RhythmEngine(
        timeline: timeline,
        audioPlayer: AudioPlayer(),
      );

      final pattern = engine.hapticPatternMs;
      pattern[0] = 9999; // Mutamos la copia

      // El engine debe devolver el valor original
      expect(engine.hapticPatternMs[0], equals(0));
      engine.dispose();
    });

    test('events es un stream broadcast (multi-listener)', () {
      final timeline = LipTimeline.fromStimulusJson(testJson);
      final engine = RhythmEngine(
        timeline: timeline,
        audioPlayer: AudioPlayer(),
      );

      // Dos escuchas simultáneas no deben lanzar excepción
      expect(() {
        engine.events.listen((_) {});
        engine.events.listen((_) {});
      }, isNot(throwsException));

      engine.dispose();
    });

    test('dispose no lanza excepción', () {
      final timeline = LipTimeline.fromStimulusJson(testJson);
      final engine = RhythmEngine(
        timeline: timeline,
        audioPlayer: AudioPlayer(),
      );
      expect(() => engine.dispose(), isNot(throwsException));
    });

    test('hapticPatternMs de timeline de 3 sílabas tiene 3 elementos', () {
      final json3 = {
        'syllables': ['ca', 'ba', 'llo'],
        'onsets_ms': [0, 300, 600],
        'durations_ms': [280, 280, 400],
      };
      final timeline = LipTimeline.fromStimulusJson(json3);
      final engine = RhythmEngine(
        timeline: timeline,
        audioPlayer: AudioPlayer(),
      );
      expect(engine.hapticPatternMs.length, equals(3));
      engine.dispose();
    });
  });

  // =========================================================================
  // 3. RecordingService — configuración WAV (constante estática)
  // =========================================================================
  group('Sprint1 / RecordingService.kAudioConfig', () {
    test('encoder es WAV', () {
      expect(RecordingService.kAudioConfig.encoder, equals(AudioEncoder.wav));
    });

    test('sampleRate es 16000 Hz', () {
      expect(RecordingService.kAudioConfig.sampleRate, equals(16000));
    });

    test('numChannels es 1 (mono)', () {
      expect(RecordingService.kAudioConfig.numChannels, equals(1));
    });

    test('bitRate es 256000 bps', () {
      expect(RecordingService.kAudioConfig.bitRate, equals(256000));
    });
  });

  // =========================================================================
  // 4. TemSessionViewModel — constantes del protocolo MIT
  // =========================================================================
  // Nota: los tests de la FSM (advanceStep, recordAttemptResult, etc.) requieren
  // Firebase inicializado (StimulusRepository y SessionManager usan Firestore).
  // Esos tests se ubican en test/integration/tem_viewmodel_integration_test.dart.
  group('Sprint1 / TemSessionViewModel — constantes', () {
    test('maxAttempts es 4 (cuatro intentos antes de abandon)', () {
      expect(TemSessionViewModel.maxAttempts, equals(4));
    });
  });

  // =========================================================================
  // 5. TemSessionSummaryScreen — widget sin Provider ni Firebase
  // =========================================================================
  group('Sprint1 / TemSessionSummaryScreen widget', () {
    testWidgets('renderiza AppBar "Resultado de la sesión"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TemSessionSummaryScreen.withArgs(args: {})),
      );
      expect(find.text('Resultado de la sesión'), findsOneWidget);
    });

    testWidgets('muestra disclaimer "Resultado preliminar"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TemSessionSummaryScreen.withArgs(args: {})),
      );
      expect(find.textContaining('Resultado preliminar'), findsOneWidget);
    });

    testWidgets('muestra botón "Volver al inicio"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TemSessionSummaryScreen.withArgs(args: {})),
      );
      expect(find.text('Volver al inicio'), findsOneWidget);
    });

    testWidgets('muestra score cuando se pasa en args', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TemSessionSummaryScreen.withArgs(args: {'score': 12}),
        ),
      );
      await tester.pump();
      expect(find.textContaining('12'), findsAtLeastNWidgets(1));
    });

    testWidgets('chips de estímulos abandonados se muestran desde args', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TemSessionSummaryScreen.withArgs(
            args: const {
              'completed': <String>[],
              'abandoned': ['ST_001', 'ST_002'],
              'total': 2,
            },
          ),
        ),
      );
      await tester.pump();
      // Los chips de abandonados se muestran solo cuando la lista no está vacía
      expect(find.text('ST_001'), findsOneWidget);
      expect(find.text('ST_002'), findsOneWidget);
    });

    testWidgets('no lanza excepción con args vacío (valores por defecto)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: TemSessionSummaryScreen.withArgs(args: {})),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
