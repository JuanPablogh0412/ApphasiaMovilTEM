# Sprint 0 — Completado ✅
**Fecha:** 2 de marzo de 2026  
**Duración real:** 1 sesión  
**Estado:** Todos los criterios de aceptación verificados

---

## Resumen de lo implementado

El andamiaje completo del módulo TEM quedó integrado al proyecto `Mobile-App-RehabilitIA`.  
Las rutas existen, el menú muestra la nueva terapia, y el núcleo del módulo de labios  
puede recibir tiempos reales del audio del servidor para sincronizar la animación.

---

## Archivos creados

### Pantallas TEM (stubs compilables)
| Archivo | Ruta | Implementado en |
|---------|------|-----------------|
| `tem_list_screen.dart` | `lib/presentation/screens/tem/` | Sprint 1 |
| `tem_detail_screen.dart` | `lib/presentation/screens/tem/` | Sprint 1 |
| `tem_exercise_screen.dart` | `lib/presentation/screens/tem/` | Sprint 1 + 3 |
| `tem_calibration_screen.dart` | `lib/presentation/screens/tem/` | Sprint 3 |
| `tem_summary_screen.dart` | `lib/presentation/screens/tem/` | Sprint 1 + 2 |
| `tem_history_screen.dart` | `lib/presentation/screens/tem/` | Sprint 3 |

### Servicios TEM (stubs compilables)
| Archivo | Ruta | Implementado en |
|---------|------|-----------------|
| `stimulus_repository.dart` | `lib/services/tem/` | Sprint 1 |
| `rhythm_engine.dart` | `lib/services/tem/` | Sprint 1 |
| `recording_service.dart` | `lib/services/tem/` | Sprint 1 |

### Datos mock
| Archivo | Ruta | Propósito |
|---------|------|-----------|
| `README.md` | `firestore_seed/` | Instrucciones para seed manual en Firestore |

### Tests
| Archivo | Ruta | Tests |
|---------|------|-------|
| `widget_test.dart` (reescrito) | `test/` | 11 tests unitarios de `LipTimeline.fromStimulusJson` |

---

## Archivos modificados

### `pubspec.yaml`
Dependencias agregadas:
```yaml
just_audio: ^0.9.40          # Reproductor WAV con positionStream
record: ^5.0.0               # Grabación WAV 16kHz / mono / 16-bit
vibration: ^1.8.4            # Haptics en onsets silábicos
firebase_storage: ^13.0.3    # Storage (^11.7.0 era incompatible con firebase_auth ^6)
```

> **Nota:** Se detectó conflicto de versión entre `firebase_storage ^11.7.0` y  
> `firebase_auth ^6.1.0` (ambos requerían versiones incompatibles de  
> `firebase_core_platform_interface`). Se resolvió subiendo a `^13.0.3`.

### `lib/routes/app_router.dart`
6 rutas TEM agregadas al switch de `AppRouter.generateRoute()`:
```
/tem-list         → TemListScreen
/tem-detail       → TemDetailScreen(args)
/tem-exercise     → TemExerciseScreen(args)
/tem-calibration  → TemCalibrationScreen
/tem-summary      → TemSummaryScreen(args)
/tem-history      → TemHistoryScreen
```

### `lib/presentation/screens/menu/menu_screen.dart`
Card TEM agregada en `_buildTherapies()` después de "Recuperación Espaciada":
```dart
_therapyCard(
  title: "Entonación Melódica",
  description: "Canta sílabas sincronizadas con movimientos labiales para recuperar el habla.",
  icon: Icons.music_note_rounded,
  onTap: () => Navigator.pushNamed(context, '/tem-list'),
)
```

### `lib/presentation/screens/tem/lip_animation/lip_timeline.dart`
**Cambio 1 — Campo `onsetsMs` en la clase `LipTimeline`:**
```dart
class LipTimeline {
  final List<LipEvent> events;
  final Duration totalDuration;
  final List<int> onsetsMs;   // ← nuevo campo

  const LipTimeline({
    required this.events,
    required this.totalDuration,
    this.onsetsMs = const [],  // vacío para timelines autónomos (desde texto)
  });
}
```

**Cambio 2 — Factory constructor `LipTimeline.fromStimulusJson()`:**
- Lee `syllables`, `onsets_ms`, `durations_ms` del JSON del servidor
- Valida invariante: las tres listas deben tener la misma longitud
- Llama `syllabify()` + `generateTimeline()` internamente (Flutter calcula los visemas)
- Re-offsetea los eventos al tiempo real del audio (`onsets_ms`)
- Expone `onsetsMs` en el resultado para que `RhythmEngine` derive `hapticPatternMs`
- NO lee ni espera `viseme_timeline` en el JSON

### `lib/presentation/screens/tem/lip_animation/lip_animation_widget.dart`
**Cambio 1 — Import `dart:async`:**  
Necesario para `StreamSubscription<Duration>`.

**Cambio 2 — Nuevos campos en `LipAnimationWidget`:**
```dart
final LipTimeline? externalTimeline;
final Stream<Duration>? audioPosition;
```

**Cambio 3 — Constructor nombrado `LipAnimationWidget.fromTimeline()`:**
```dart
const LipAnimationWidget.fromTimeline({
  required LipTimeline timeline,
  required Stream<Duration> audioPositionStream,
  Color lipColor,
  bool debug,
  bool loop,
})
```

**Cambio 4 — Campo `_audioSubscription` en el State:**
```dart
StreamSubscription<Duration>? _audioSubscription;
```

**Cambio 5 — Lógica de modo `fromTimeline` en `_initializeAnimation()`:**  
Si `widget.externalTimeline != null`, usa la timeline provista y se suscribe  
al stream del AudioPlayer para espejar su posición en `controller.value`:
```dart
_audioSubscription = widget.audioPosition!.listen((position) {
  final value = (position.inMicroseconds / totalUs).clamp(0.0, 1.0);
  _controller!.value = value;
  _updateVisemeFromController();
});
```

**Cambio 6 — Método `_updateVisemeFromController()` extraído:**  
La lógica de actualización del visema se movió a un método separado  
para ser compartida entre el modo autónomo y el modo `fromTimeline`.

**Cambio 7 — `dispose()` actualizado:**  
Cancela `_audioSubscription` antes de disponer el controller.

---

## Criterios de aceptación verificados

| Criterio | Estado | Evidencia |
|----------|--------|-----------|
| `flutter pub get` sin errores con 4 dependencias nuevas | ✅ | Ejecutado OK |
| Las 6 rutas `/tem-*` están registradas en `AppRouter` | ✅ | Código en app_router.dart |
| La card TEM aparece en el Tab "Terapias" | ✅ | Código en menu_screen.dart |
| `LipTimeline.fromStimulusJson()` parsea correctamente | ✅ | 7 tests unitarios pasan |
| `LipTimeline.onsetsMs` expuesto para `RhythmEngine` | ✅ | 2 tests unitarios pasan |
| `LipAnimationWidget.fromTimeline()` acepta `Stream<Duration>` | ✅ | Código compila |
| `flutter test` — 11/11 tests pasan | ✅ | `+11: All tests passed!` |
| `flutter analyze` — 0 errores/warnings en código TEM nuevo | ✅ | Solo pre-existentes del módulo original |

---

## Decisiones técnicas (con justificación)

### firebase_storage ^13.0.3 en lugar de ^11.7.0
El resolver de pub detectó incompatibilidad entre `firebase_storage ^11.7.0` (requería  
`firebase_core_platform_interface ^5`) y `firebase_auth ^6.1.0` (requería `^6`).  
Se subió a `^13.0.3` que es compatible. **Actualizar también en TEM_SPRINTS.md.**

### Factory en la clase vs. extensión estática
Se probó una extensión `LipTimelineFromJson on LipTimeline` con método estático.  
Los métodos estáticos en extensiones Dart se llaman como  
`LipTimelineFromJson.fromStimulusJson(...)` — no como `LipTimeline.fromStimulusJson(...)`.  
Se cambió a `factory LipTimeline.fromStimulusJson()` directamente en la clase para  
una API idiomática y consistente con el resto de Flutter.

### Tests unitarios puros (sin Firebase)
El `widget_test.dart` original era el template defecto de Flutter con `MyApp`  
que no existe en el proyecto. Se reemplazó con 11 tests unitarios de  
`LipTimeline.fromStimulusJson` que no requieren Firebase, UI, ni emuladores.

### Stubs compilables con `throw UnimplementedError`
Los stubs de servicios (`StimulusRepository`, `RhythmEngine`, `RecordingService`)  
tienen firmas completas y correctas para Sprint 1, pero lanzan `UnimplementedError`  
hasta que se implementen. Esto permite que el proyecto compile con rutas funcionales  
y que el tipo-chequeo de Dart valide las firmas desde ahora.

---

## Estado del proyecto al cerrar Sprint 0

```
lib/
├── presentation/screens/tem/
│   ├── lip_animation/        ← 7 archivos (sin cambios de arquitectura)
│   │   ├── lip_timeline.dart     ← MODIFICADO: +onsetsMs, +fromStimulusJson
│   │   └── lip_animation_widget.dart ← MODIFICADO: +fromTimeline, +stream mode
│   ├── tem_list_screen.dart      ← NUEVO (stub)
│   ├── tem_detail_screen.dart    ← NUEVO (stub)
│   ├── tem_exercise_screen.dart  ← NUEVO (stub)
│   ├── tem_calibration_screen.dart ← NUEVO (stub)
│   ├── tem_summary_screen.dart   ← NUEVO (stub)
│   └── tem_history_screen.dart   ← NUEVO (stub)
├── routes/
│   └── app_router.dart           ← MODIFICADO: +6 rutas TEM
├── presentation/screens/menu/
│   └── menu_screen.dart          ← MODIFICADO: +card TEM
└── services/tem/
    ├── stimulus_repository.dart  ← NUEVO (stub)
    ├── rhythm_engine.dart        ← NUEVO (stub)
    └── recording_service.dart    ← NUEVO (stub)
firestore_seed/
└── README.md                     ← NUEVO: instrucciones + JSONs mock
test/
└── widget_test.dart              ← REESCRITO: 11 tests Sprint 0
```

---

*Siguiente sprint: **Sprint 1** — Reproductor + Grabación + Pantallas*  
*Ver detalles en `TEM_SPRINTS.md`*
