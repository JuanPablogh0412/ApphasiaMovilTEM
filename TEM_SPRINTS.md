# 🎵 Plan de Sprints — Módulo TEM (Terapia de Entonación Melódica)
**Proyecto:** Mobile-App-RehabilitIA  
**Fecha inicio:** Marzo 2026  
**Estado:** Pendiente de validación

---

## 📋 Resumen General

| Sprint | Nombre | Duración | Estado |
|--------|--------|----------|--------|
| Sprint 0 | Andamiaje e integración base | 1 semana | ⬜ Pendiente |
| Sprint 1 | Reproductor + Grabación + Pantallas | 2 semanas | ⬜ Pendiente |
| Sprint 2 | Backend de análisis acústico | 2 semanas | ⬜ Pendiente |
| Sprint 3 | FSM clínica + Calibración + QA | 2 semanas | ⬜ Pendiente |

**Total estimado:** ~7 semanas

---

## ⚡ Sprint 0 — Andamiaje e Integración Base
**Duración:** 1 semana  
**Objetivo:** El módulo de labios queda integrado al proyecto, las rutas TEM existen, y el widget puede ser controlado desde un timeline JSON externo.

### Tareas

#### 0.1 · Dependencias al `pubspec.yaml`
Agregar los 4 paquetes que el módulo TEM necesita y que aún no existen en el proyecto:

```yaml
just_audio: ^0.9.40        # Reproductor WAV + segundo AudioPlayer dedicado al clic de metrónomo
record: ^5.0.0             # Grabación WAV 16kHz/mono/16-bit
firebase_storage: ^13.0.3  # Descargar timeline.json y audio desde Storage (^11.7.0 incompatible con firebase_auth ^6)
```

> `vibration` eliminado — el ritmo de sílabas se comunica mediante un **clic de metrónomo** (WAV corto reproducido con un `AudioPlayer` secundario en `RhythmEngine`) en lugar de vibración del dispositivo. Es menos invasivo, más consistente entre plataformas y más fácil de controlar en amplitud/tempo.

> `firebase_core`, `firebase_auth`, `cloud_firestore` ya están — NO volver a agregarlos.

---

#### 0.2 · Estructura de carpetas y archivos vacíos

> **Arquitectura:** El módulo TEM sigue la regla estricta `Presentation → Services → Data/Models`.
> Las capas **nunca** importan en dirección contraria.

Crear la estructura completa de carpetas y archivos vacíos que se irán llenando en sprints posteriores:

```
lib/
│
├── data/models/tem/                          ← MODELOS PUROS (sin imports Flutter UI)
│   ├── lip_viseme.dart    ← ✅ CREADO Sprint 0   (Viseme + Visemes constants)
│   ├── lip_timeline.dart  ← ✅ CREADO Sprint 0   (LipTimeline, syllabify())
│   └── lip_model.dart     ← ✅ CREADO Sprint 0   (geometría paramétrica labios/lengua)
│
├── services/tem/                             ← SERVICIOS (importan solo desde data/models/)
│   ├── stimulus_repository.dart  ← ✅ EXISTE   (actualizado: import data/models/tem/)
│   ├── rhythm_engine.dart        ← ✅ EXISTE   (actualizado: MetronomeClickEvent)
│   ├── session_manager.dart      ← ✅ CREADO Sprint 0  (algoritmo anti-perseveración)
│   └── recording_service.dart    ← ✅ CREADO Sprint 0  (grabación WAV 16kHz + upload)
│
├── presentation/viewmodels/tem/              ← VIEWMODELS (orquestan servicios, exponen estado)
│   └── tem_session_viewmodel.dart  ← ✅ CREADO Sprint 0  (stub con API pública definida)
│
└── presentation/screens/tem/                ← SCREENS (solo UI — leen ViewModel via Consumer)
    ├── lip_animation/                    ← YA EXISTE (no modificar — usa imports relativos)
    ├── tem_home_screen.dart              ← ✅ CREADO Sprint 0  (launcher de sesión)
    ├── tem_exercise_screen.dart          ← ✅ CREADO Sprint 0  (pantalla única de ejercicio + 5 pasos)
    ├── tem_session_summary_screen.dart   ← ✅ CREADO Sprint 0  (resumen al final de sesión)
    ├── tem_calibration_screen.dart       ← ✅ CREADO Sprint 0  (calibración híbrida 2 fases)
    └── tem_history_screen.dart           ← ✅ CREADO Sprint 0
```

> `tem_detail_screen.dart` **no se crea** — su contenido es el Paso 1 (escucha) dentro de `TemExerciseScreen`.
> `tem_summary_screen.dart` **no se crea** — se reemplaza por `tem_session_summary_screen.dart`.
> Los archivos en `lip_animation/` usan imports relativos entre sí — no necesitan cambios.
> Los archivos en `data/models/tem/` son la ubicación canónica; `services/` importa desde allí.

---

#### 0.3 · Rutas TEM en `app_router.dart`

Agregar las 6 rutas nuevas en el switch de `AppRouter.generateRoute()`:

```dart
case '/tem-home':
  return MaterialPageRoute(builder: (_) => const TemHomeScreen());

case '/tem-exercise':
  final args = settings.arguments as Map<String, dynamic>;
  return MaterialPageRoute(builder: (_) => TemExerciseScreen(args: args));

case '/tem-calibration':
  return MaterialPageRoute(builder: (_) => const TemCalibrationScreen());

case '/tem-session-summary':
  final args = settings.arguments as Map<String, dynamic>;
  return MaterialPageRoute(builder: (_) => TemSessionSummaryScreen(args: args));

case '/tem-history':
  return MaterialPageRoute(builder: (_) => const TemHistoryScreen());
```

> Rutas eliminadas: `/tem-list` (reemplazada por `/tem-home`) y `/tem-detail` (pantalla eliminada — fusionada en Paso 1 de `TemExerciseScreen`).

---

#### 0.4 · Card TEM en `menu_screen.dart`

Agregar la entrada TEM en el Tab "Terapias" del menú principal (junto a las cards de VNEST y SR existentes):

```dart
_TerapiaCard(
  titulo: 'TEM',
  subtitulo: 'Terapia de Entonación Melódica',
  icono: Icons.music_note_rounded,
  color: Color(0xFFF48A63),
  ruta: '/tem-home',
)
```

---

#### 0.5 · `LipTimeline.fromStimulusJson()` en `lip_timeline.dart`

Implementar el factory que convierte los campos de timing del JSON del servidor al formato interno `LipEvent`. **Los visemas NO vienen del servidor** — Flutter los calcula automáticamente a partir del texto usando `syllabify()` + `generateTimeline()` que ya están implementados en el módulo.

**Input esperado (de Firestore/Storage):**
```json
{
  "stimulusId": "ST_TEM_N1_001",
  "texto": "mamá",
  "syllables": ["ma", "má"],
  "num_silabas": 2,
  "patron_tonal": "LH",
  "onsets_ms": [0, 500],
  "durations_ms": [500, 500],
  "f0_template_hz": [155.0, 185.0],
  "audio_url": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N1_001_v1.wav",
  "image_url": "gs://apphasia-7a930.firebasestorage.app/stimuli/images/ST_TEM_N1_001.jpg",
  "nivel_clinico": 1
}
```

> ❌ El JSON **no incluye** `viseme_timeline`, `haptic_pattern_ms` ni `fase` — los visemas se calculan en Flutter; el patrón de metrónomo se deriva de `onsets_ms`.

> **`patron_tonal`:** cadena de `H` (alto ~185 Hz) y `L` (bajo ~155 Hz) por sílaba. Usada por `SessionManager` para alternar patrones entre estímulos consecutivos y evitar perseveraciones tonales (ver §1.5).

> **`onsets_ms` / `durations_ms`:** en TEM el tempo es lento y exagerado — ~500 ms por sílaba como valor base. Los valores definitivos se obtienen midiendo el audio grabado por el fonoaudiólogo con Praat.

**Paso previo — ampliar la clase `LipTimeline`:**

Antes de implementar el factory, añadir el campo `onsetsMs` a la propia clase para que `RhythmEngine` pueda acceder a los tiempos de cada sílaba sin parsear de nuevo. Los timelines generados desde texto (modo autónomo) lo dejan vacío.

```dart
// En lip_timeline.dart — modificar la clase existente
class LipTimeline {
  final List<LipEvent> events;
  final Duration totalDuration;
  final List<int> onsetsMs;          // ← campo nuevo

  const LipTimeline({
    required this.events,
    required this.totalDuration,
    this.onsetsMs = const [],        // vacío para timelines generados desde texto
  });
}
```

**Implementación del factory:**
```dart
factory LipTimeline.fromStimulusJson(Map<String, dynamic> json) {
  final syllableStrings = List<String>.from(json['syllables'] as List);
  final durationsMs     = List<int>.from(json['durations_ms'] as List);
  final onsetsMs        = List<int>.from(json['onsets_ms'] as List);

  // Validar invariante
  if (syllableStrings.length != durationsMs.length ||
      syllableStrings.length != onsetsMs.length) {
    throw ArgumentError(
      'syllables (${syllableStrings.length}), '
      'onsets_ms (${onsetsMs.length}) y '
      'durations_ms (${durationsMs.length}) deben tener la misma longitud.',
    );
  }

  // Flutter calcula los visemas — los tiempos vienen del audio real del servidor
  final events = <LipEvent>[];
  for (int i = 0; i < syllableStrings.length; i++) {
    final syllableList = syllabify(syllableStrings[i]);
    if (syllableList.isEmpty) continue;
    final syllableTimeline = generateTimeline(syllableList, durationsMs[i]);
    for (final event in syllableTimeline.events) {
      events.add(LipEvent(
        startViseme: event.startViseme,
        endViseme:   event.endViseme,
        duration:    event.duration,
        startTime:   Duration(milliseconds: onsetsMs[i]) + event.startTime,
      ));
    }
  }

  return LipTimeline(
    events: events,
    totalDuration: Duration(milliseconds: onsetsMs.last + durationsMs.last),
    onsetsMs: onsetsMs,    // ← pasar los onsets para que RhythmEngine los use
  );
}
```

**Invariante que validar siempre antes de parsear:**
```
syllables.length == onsets_ms.length == durations_ms.length
```
Si no se cumple → lanzar excepción descriptiva, NO mostrar el estímulo.

---

#### 0.6 · `LipAnimationWidget.fromTimeline()` en `lip_animation_widget.dart`

Agregar un constructor nombrado para modo "esclavo del audio":

```dart
// El widget ya tiene su constructor normal (genera timeline desde texto)
// Agregar este constructor adicional:

LipAnimationWidget.fromTimeline({
  Key? key,
  required LipTimeline timeline,
  required Stream<Duration> audioPosition,  // positionStream de just_audio
  Color lipColor = const Color(0xFFB71C1C),
  bool debug = false,
  bool loop = false,
})
```

En modo `fromTimeline`, el `AnimationController` **no corre autónomo**: recibe la posición del `AudioPlayer` vía stream y actualiza `controller.value` directamente, manteniendo labios y audio perfectamente sincronizados.

---

#### 0.7 · Corpus de estímulos TEM — Diseño inicial (27 estímulos)

**Contexto:** El protocolo MIT requiere "10 o más estímulos por sesión usando una diversidad de estímulos" (Helm-Estabrooks et al., 1989). El corpus MVP cubre los 3 niveles clínicos con 27 estímulos diseñados para: (a) favorecer consonantes bilabiales y sonidos visualizables en Nivel 1; (b) escalar en longitud y complejidad sintáctica hacia Nivel 3; (c) permitir rotación anti-perseveración alternando `patron_tonal` y `num_silabas` entre estímulos consecutivos.

> ⚠️ **Prerrequisito de producción:** cada estímulo necesita un audio WAV grabado por un fonoaudiólogo siguiendo el protocolo TEM (tempo lento ~500 ms/sílaba, entonación alto/bajo exagerada). Los `onsets_ms`, `durations_ms` y `f0_template_hz` definitivos se miden del audio real con Praat. Los valores abajo son **placeholders de desarrollo** (500 ms/sílaba uniformes).

##### Nivel 1 — 10 estímulos (bisílabas/trisílabas, bilabiales, visualizables)

| ID | texto | sílabas | num_sil | patron_tonal | f0_hz | onsets_ms | durations_ms |
|----|-------|---------|---------|--------------|-------|-----------|--------------|
| ST_TEM_N1_001 | mamá | ma·má | 2 | LH | [155,185] | [0,500] | [500,500] |
| ST_TEM_N1_002 | buenas | bue·nas | 2 | HL | [185,155] | [0,500] | [500,500] |
| ST_TEM_N1_003 | papá | pa·pá | 2 | LH | [155,185] | [0,500] | [500,500] |
| ST_TEM_N1_004 | mesa | me·sa | 2 | HL | [185,155] | [0,500] | [500,500] |
| ST_TEM_N1_005 | bebé | be·bé | 2 | LH | [155,185] | [0,500] | [500,500] |
| ST_TEM_N1_006 | paloma | pa·lo·ma | 3 | HLH | [185,155,185] | [0,500,1000] | [500,500,500] |
| ST_TEM_N1_007 | mañana | ma·ña·na | 3 | LHL | [155,185,155] | [0,500,1000] | [500,500,500] |
| ST_TEM_N1_008 | bonita | bo·ni·ta | 3 | HLL | [185,155,155] | [0,500,1000] | [500,500,500] |
| ST_TEM_N1_009 | familia | fa·mi·lia | 3 | HLH | [185,155,185] | [0,500,1000] | [500,500,500] |
| ST_TEM_N1_010 | peinado | pei·na·do | 3 | LHL | [155,185,155] | [0,500,1000] | [500,500,500] |

##### Nivel 2 — 10 estímulos (sintagmas de alta frecuencia)

| ID | texto | sílabas | num_sil | patron_tonal | f0_hz | onsets_ms | durations_ms |
|----|-------|---------|---------|--------------|-------|-----------|--------------|
| ST_TEM_N2_001 | buenos días | bue·nos·dí·as | 4 | HLHL | [185,155,185,155] | [0,500,1000,1500] | [500,500,500,500] |
| ST_TEM_N2_002 | quiero agua | quie·ro·a·gua | 4 | LHHL | [155,185,185,155] | [0,500,1000,1500] | [500,500,500,500] |
| ST_TEM_N2_003 | me duele | me·due·le | 3 | HLH | [185,155,185] | [0,500,1000] | [500,500,500] |
| ST_TEM_N2_004 | por favor | por·fa·vor | 3 | LHL | [155,185,155] | [0,500,1000] | [500,500,500] |
| ST_TEM_N2_005 | tengo sed | ten·go·sed | 3 | HLL | [185,155,155] | [0,500,1000] | [500,500,500] |
| ST_TEM_N2_006 | ven aquí | ven·a·quí | 3 | LLH | [155,155,185] | [0,500,1000] | [500,500,500] |
| ST_TEM_N2_007 | no puedo | no·pue·do | 3 | HHL | [185,185,155] | [0,500,1000] | [500,500,500] |
| ST_TEM_N2_008 | mi mamá | mi·ma·má | 3 | LLH | [155,155,185] | [0,500,1000] | [500,500,500] |
| ST_TEM_N2_009 | estoy bien | es·toy·bien | 3 | LHL | [155,185,155] | [0,500,1000] | [500,500,500] |
| ST_TEM_N2_010 | qué calor | qué·ca·lor | 3 | HLH | [185,155,185] | [0,500,1000] | [500,500,500] |

##### Nivel 3 — 7 estímulos (oraciones con prosodia normal progresiva)

| ID | texto | num_sil | patron_tonal |
|----|-------|---------|------|
| ST_TEM_N3_001 | quiero un vaso | 5 | HLHLL |
| ST_TEM_N3_002 | cómo te llamas | 5 | HLHLL |
| ST_TEM_N3_003 | buenos días doctor | 6 | HLHLLL |
| ST_TEM_N3_004 | tengo mucho dolor | 6 | HLLLLL |
| ST_TEM_N3_005 | necesito ayuda | 7 | LHLHLHL |
| ST_TEM_N3_006 | dónde está mi familia | 8 | HLHLHLHL |
| ST_TEM_N3_007 | quiero hablar con mi hijo | 8 | HLHLHLHL |

> Los `onsets_ms` y `durations_ms` del Nivel 3 se rellenan después de grabar el audio real. El Nivel 3 también requiere versiones en _sprechgesang_ (Paso 2 del nivel) y prosodia normal (Pasos 4-5).

**Colecciones Firestore a crear manualmente para desarrollo:**
- `stimuli_TEM/` — un documento por cada estímulo de la tabla anterior
- `sesiones_TEM/` — colección vacía (creada por `SessionManager` en runtime)
- `pacientes/{uid_test}/ejercicios_asignados/` — doc con `terapia: "TEM"`, `nivel_actual: 1`

---

### ✅ Criterios de éxito del Sprint 0

- [ ] `flutter pub get` pasa sin errores con las 3 dependencias nuevas (`just_audio`, `record`, `firebase_storage`)
- [ ] Las 5 rutas TEM (`/tem-home`, `/tem-exercise`, `/tem-calibration`, `/tem-session-summary`, `/tem-history`) están registradas en `AppRouter`
- [ ] La card TEM aparece en el Tab "Terapias" del menú y navega a `/tem-home`
- [ ] `LipTimeline.fromStimulusJson({...})` parsea el JSON mock (con `patron_tonal`, `num_silabas`, `image_url`) sin `viseme_timeline`, genera eventos válidos
- [ ] `LipAnimationWidget.fromTimeline(...)` acepta un `Stream<Duration>` y sincroniza el `controller.value`
- [ ] `flutter test` pasa (incluídos los tests unitarios de `LipTimeline.fromStimulusJson`)

---

---

## 🔊 Sprint 1 — Reproductor + Grabación + Pantallas
**Duración:** 2 semanas  
**Objetivo:** El paciente inicia una sesión TEM desde `TemHomeScreen` y el sistema sirve automáticamente una secuencia de estímulos (estilo Duolingo — sin selección libre). Para cada estímulo recorre los 5 pasos del Nivel 1 del protocolo MIT, ve la animación de labios sincronizada con el audio, escucha el metrónomo de sílabas y graba su réplica en los pasos que lo requieren. No hay FSM clínica completa ni análisis de score aún.

### Tareas

#### 1.1 · `StimulusRepository` (`lib/services/tem/stimulus_repository.dart`)

Capa de acceso a datos para estímulos TEM. Sigue el patrón de acceso directo a Firebase que usa el resto del proyecto:

```dart
class StimulusRepository {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // Leer ejercicios TEM asignados al paciente
  Future<List<Map<String, dynamic>>> getAsignados(String pacienteId);

  // Obtener datos del estímulo desde stimuli_TEM/{stimulusId}
  Future<Map<String, dynamic>> getStimulus(String stimulusId);

  // Descargar y parsear el timeline.json desde Storage
  Future<LipTimeline> getTimeline(String timelineUrl);

  // Cachear timeline localmente (SharedPreferences) para offline
  Future<void> cacheTimeline(String stimulusId, Map<String, dynamic> json);
  Future<Map<String, dynamic>?> getCachedTimeline(String stimulusId);
}
```

**Flujo de descarga del timeline:**
1. Verificar caché local (`SharedPreferences`)
2. Si no está → descargar desde `timelineUrl` (Firebase Storage gs://)
3. Parsear con `LipTimeline.fromStimulusJson()` — Flutter calculará los visemas automáticamente a partir de `syllables` + `durations_ms` + `onsets_ms`
4. Guardar en caché para siguiente sesión

---

#### 1.2 · `RhythmEngine` (`lib/services/tem/rhythm_engine.dart`)

Scheduler que coordina audio + haptics + eventos de visema. Emite un `Stream<RhythmEvent>` que las pantallas escuchan:

```dart
sealed class RhythmEvent {}
class VisemeChangeEvent      extends RhythmEvent { final Viseme viseme; }
class SyllableActivateEvent  extends RhythmEvent { final int syllableIndex; }
class MetronomeClickEvent    extends RhythmEvent {}   // ← reemplaza HapticPulseEvent
class PlaybackEndEvent       extends RhythmEvent {}

class RhythmEngine {
  final LipTimeline timeline;
  final AudioPlayer audioPlayer;       // reproduce el estímulo WAV principal
  final AudioPlayer metronomePlayer;   // reproduce clic de metrónomo en cada onset
  final int offsetMs;                  // desde pacientes/{id}/calibracion

  // El patrón de clics se DERIVA de los onsets del timeline — no es un parámetro externo
  // Equivale exactamente a timeline.onsetsMs (inicio de cada sílaba)
  List<int> get metronomePatternMs => List<int>.from(timeline.onsetsMs);

  Stream<RhythmEvent> get events;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  void dispose();
}
```

---

#### 1.3 · `RecordingService` (`lib/services/tem/recording_service.dart`)

Graba la réplica del paciente y la sube a Firebase Storage:

```dart
class RecordingService {
  // Configuración obligatoria: WAV 16kHz / mono / 16-bit
  static const RecordConfig kAudioConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
    bitRate: 256000,
  );

  Future<void> startRecording();
  Future<String> stopRecording();   // → path local del WAV

  // Sube el WAV y crea el attempt doc en Firestore
  // → devuelve attemptId
  Future<String> uploadAttempt({
    required String localPath,
    required String pacienteId,
    required String ejercicioId,
    required String stimulusId,
    required int step,
    required String stepName,
    required int attemptNumber,
  });
}
```

**Ruta en Storage:** `attempts/{pacienteId}/{sessionId}/{attemptId}.wav`

**Documento que crea en Firestore:**
```
sesiones_TEM/{sessionId}/attempts/{attemptId}
  stimulusId: "ST_TEM_N1_001"
  paso: 2
  stepName: "unisono"
  attemptNumber: 1
  status: "pending_analysis"
  audioUrl: "gs://..."
  pending_therapist_review: true
```

> Los attempts se guardan bajo `sesiones_TEM/` (no bajo `ejercicios_TEM/`) — con el modelo Duolingo no existen ejercicios individuales asignados, sino sesiones con secuencias de estímulos.

---

#### 1.4 · `TemHomeScreen` (reemplaza `TemListScreen`) — Launcher de sesión estilo Duolingo

**Diseño:** el paciente **no ve ni elige** qué estímulos van a aparecer. Simplemente ve su estado actual y pulsa "Iniciar sesión". Esto previene el efecto de perseveración que ocurre cuando el paciente selecciona libremente estímulos familiares o fáciles (Helm-Estabrooks et al., 1989).

**Contenido:**
- Nivel actual (1 / 2 / 3) con descripción breve
- Sesiones completadas (contador)
- Score promedio de las últimas 3 sesiones
- Botón principal: **"Iniciar sesión →"**
- Botones secundarios: Historial | Calibración

**Fuente de datos:** `StimulusRepository` + `SessionManager`

> Ruta definida: `/tem-home` → `TemHomeScreen`. El stub `tem_list_screen.dart` del Sprint 0 se crea ya con el nombre `tem_home_screen.dart`.

---

#### 1.5 · `SessionManager` (`lib/services/tem/session_manager.dart`)

Servicio que construye la secuencia de estímulos de cada sesión aplicando las reglas anti-perseveración del protocolo MIT:

```dart
class SessionManager {
  final StimulusRepository repository;

  // Construye la secuencia de la sesión actual (mínimo 10 estímulos por sesión)
  Future<List<String>> buildSession(String pacienteId, {int size = 10});

  // Algoritmo anti-perseveración (basado en manual MIT):
  // 1. Obtener todos los estímulos del nivel_actual del paciente
  // 2. Excluir estímulos intentados en las últimas 24h
  // 3. Excluir estímulos con 4 intentos fallidos consecutivos en sesiones recientes
  // 4. Priorizar estímulos con menos completions exitosas (balance de práctica)
  // 5. REGLA TONAL: no colocar dos estímulos consecutivos con el mismo patron_tonal
  //    y el mismo num_silabas (ej: dos bisílabas LH seguidas → perseveración)
  // 6. Devolver los primeros `size` de la lista resultante
  // → Guarda la sesión creada en sesiones_TEM/{sessionId}
}
```

**Colección Firestore `sesiones_TEM/{sessionId}`:**
```jsonc
{
  "sessionId": "SES_0001",
  "pacienteId": "uid_patient_01",
  "nivel": 1,
  "estimulosSecuencia": ["ST_TEM_N1_006", "ST_TEM_N1_001", "ST_TEM_N1_008", ...],
  "estimuloActualIndex": 0,
  "startedAt": "timestamp",
  "completedAt": null,
  "scoreSesion": null,
  "status": "in_progress"   // in_progress | completed | abandoned
}
```

---

#### 1.5b · Pantalla de preparación de estímulo (dentro de `TemExerciseScreen`)

`TemDetailScreen` queda **eliminada como pantalla navegable independiente**. Su contenido se convierte en la pantalla de preparación inicial (Paso 1 del protocolo — el tarareo del terapeuta):
- App muestra imagen semántica + texto con sílabas separadas a pantalla completa
- Reproduce el estímulo automáticamente 2 veces (sin que el paciente grabe)
- Texto: _"Escucha atentamente"_
- Después de las 2 reproducciones → avanza automáticamente al Paso 2

---

#### 1.6 · `TemExerciseScreen` — Pantalla principal del ejercicio

Es la pantalla más compleja del módulo. En Sprint 1 implementa la versión básica (sin FSM clínica):

**Doble barra de progreso (estilo Duolingo):**
```
[← ] Estímulo 3/10   [■■■□□□□□□□]     ← progreso de sesión
      Paso 2/5        [■■□□□]           ← progreso dentro del estímulo actual
```

**Secciones de la pantalla:**
1. **Header:** doble barra de progreso (sesión + paso actual)
2. **Imagen semántica** del ítem (prominente, ocupa 40% de la pantalla)
3. **Texto** del estímulo con sílaba activa resaltada
4. **Animación:** `LipAnimationWidget.fromTimeline(...)` sincronizado con audio
5. **Instrucción persistente (Pasos 2-4):** *"Golpea suavemente con tu mano izquierda cada sílaba resaltada"*
6. **Estado del paso:** etiqueta clara del paso actual

**Flujo de Nivel 1 — 5 pasos por estímulo (protocolo MIT original):**
```
Cargar timeline del estímulo
  → [Paso 1 — sin puntuación]
       App reproduce el audio 2 veces + metrónomo + animación
       Paciente escucha — NO graba
       Texto en pantalla: "Escucha atentamente"
  → [Paso 2 — 1 punto]
       App reproduce + paciente canta junto (graba con metrónomo)
       Texto: "Canta junto al audio"
  → [Paso 3 — 1 punto]
       App reproduce, baja volumen a mitad — paciente completa (graba)
       Texto: "Completa la frase solo"
  → [Paso 4 — 1 punto]
       App reproduce en silencio (solo metrónomo) — paciente repite (graba)
       Texto: "Repite solo"
  → [Paso 5 — 1 punto]
       App muestra pregunta de texto: ej "¿Qué acaba de decir?"
       Paciente responde (graba) — sin metrónomo en este paso
  → Si un paso falla 4 veces → estímulo abandonado, siguiente estímulo
  → Sin retrocesos en Nivel 1 (retrocesos solo en Niveles 2 y 3)
  → Completados todos los pasos → siguiente estímulo de la secuencia

Fin de todos los estímulos → TemSessionSummaryScreen
```

> ⚠️ **Corrección crítica vs. versión anterior:** el "humming" del paciente **no existe en el protocolo MIT**. El Paso 1 (tarareo) lo realiza el terapeuta/app — el paciente solo escucha. Esto fue corregido tras lectura directa del manual (Helm-Estabrooks et al., 1989).

---

#### 1.7 · `TemSessionSummaryScreen` — Resumen de sesión completa

Se muestra **solo al terminar todos los estímulos de la sesión** (Opción B — sin resúmenes intermedios entre estímulos).

**Contenido:**
- Estímulos completados: N / total de la sesión
- Estímulos abandonados (4 intentos fallidos): lista con texto
- Score provisional de la sesión (promedio de los attempts analizados)
- ⚠️ **Disclaimer:** _"Resultado preliminar — requiere validación del terapeuta antes de avanzar de nivel"_
- Botón "Volver al inicio"

> En Sprint 2 el score se completa con los resultados reales del backend.

---

### ✅ Criterios de éxito del Sprint 1

- [ ] `TemHomeScreen` muestra nivel actual y botón "Iniciar sesión" (sin lista de estímulos)
- [ ] `SessionManager.buildSession()` construye secuencia de 10 estímulos respetando regla tonal anti-perseveración
- [ ] `sesiones_TEM/{id}` se crea en Firestore al iniciar sesión
- [ ] `TemExerciseScreen` muestra doble barra de progreso (sesión + paso)
- [ ] Paso 1 reproduce audio 2 veces sin grabar
- [ ] Pasos 2-4 graban WAV con configuración 16kHz/mono/16-bit
- [ ] Paso 5 muestra pregunta de texto y graba respuesta (sin metrónomo)
- [ ] Estímulo fallido (4 intentos) → abandona y avanza al siguiente
- [ ] WAV se sube a ruta correcta en Firebase Storage
- [ ] Attempt doc se crea con `status: "pending_analysis"`
- [ ] `TemSessionSummaryScreen` muestra resumen al finalizar la sesión completa
- [ ] No hay regresiones: `flutter test` sigue pasando

---

---

## 🐍 Sprint 2 — Backend de Análisis Acústico
**Duración:** 2 semanas  
**Objetivo:** El backend Python analiza el WAV grabado, calcula scores por componente (pitch, ritmo, intensidad), y la app muestra el resultado en tiempo real vía listener de Firestore.

### Tareas

#### 2.1 · Arquitectura del backend — Cloud Run + Cloud Function proxy

**Decisión de infraestructura:** Cloud Run con `min-instances=0`

**Justificación:** Parselmouth (wrapper de Praat) requiere dependencias nativas del sistema (`libstdc++`, binarios precompilados) que no son instalables en el entorno de Cloud Functions. Cloud Run usa Docker — permite instalar cualquier dependencia sin restricciones de entorno.

**Stack:**
```
Python 3.11+
├── FastAPI          — servidor HTTP en Cloud Run
├── Parselmouth      — wrapper de Praat para análisis de F0
├── librosa          — onset detection, RMS, timing
├── firebase-admin   — leer Firestore + Storage
└── soundfile        — manejo de WAV
```

**Flujo de invocación — POST /analyze (análisis de intento):**
```
[Flutter] crea attempt doc (status: "pending_analysis")
    ↓
[Cloud Function Python — tiny proxy, ~20 líneas]
    recibe onCreate de Firestore
    POST { attemptId, ejercicioId, pacienteId } → Cloud Run /analyze
    ↓
[Cloud Run — backend_tem, siempre desplegado]
    descarga WAV desde Storage
    Parselmouth + librosa → métricas acústicas
    calcula scores 0-100 por componente
    escribe analysis_results_TEM/{analysisId}
    actualiza attempt.status → "analyzed"
    ↓
[Flutter] StreamBuilder detecta status "analyzed" → TemSummaryScreen
```

**Flujo de invocación — POST /calibrate (calibración vocal del paciente):**
```
[Flutter] graba vocal sostenida "aaaaa" (~3s WAV)
    ↓
[Flutter] sube WAV a Storage con metadata { type: "calibration", pacienteId }
    ↓
[Cloud Function Python — mismo proxy, ~20 líneas]
    recibe onFinalize de Storage (metadata.type == "calibration")
    POST { calibrationAudioUrl, pacienteId } → Cloud Run /calibrate
    ↓
[Cloud Run — reutiliza pitch_analyzer.py]
    descarga WAV vocal sostenida
    Parselmouth mide F0 frame a frame sobre toda la grabación
    extrae f0_min, f0_max, f0_comfort (percentiles p10/p90/p50 del rango voiced)
    librosa mide avg_syllable_duration_ms (onset detection sobre vocales)
    escribe pacientes/{pacienteId}/calibracion (parcial, sin offset_ms)
    ↓
[Flutter] lee resultado provisional de Firestore (~5-10s latencia total)
    → continúa a Fase 2 (medición local de offset_ms)
```

**Estructura de archivos del módulo Python:**
```
backend_tem/
├── main.py                   ← FastAPI app + endpoints POST /analyze y POST /calibrate
├── trigger/
│   └── main.py               ← Cloud Function tiny (proxy Firestore/Storage → Cloud Run)
├── analyzer/
│   ├── pitch_analyzer.py     ← F0 por sílaba con Parselmouth
│   ├── rhythm_analyzer.py    ← onset detection y timing con librosa
│   ├── scorer.py             ← convierte métricas a scores 0-100
│   └── syllable_aligner.py   ← alinea audio grabado con template de onsets
├── firebase_client.py        ← descarga WAV, lee/escribe Firestore
├── models.py                 ← dataclasses input/output
├── requirements.txt
└── Dockerfile
```

> ❌ El backend **NO genera ni almacena `viseme_timeline`** — los visemas son responsabilidad exclusiva del cliente Flutter. El backend solo conoce el audio, no la animación.

---

#### 2.2 · Esquema `analysis_results_TEM/{AN_XXXX}`

Documento que escribe el backend y lee la app:

```jsonc
{
  "analysisId": "AN_0001",
  "attemptId": "ATT_0001",
  "ejercicioId": "E_TEM_0001",
  "pacienteId": "uid_patient_01",
  "score_global": 72,
  "components": {
    "pitch_accuracy": 68,      // qué tan cerca estuvo F0 del template por sílaba
    "rhythm_regularity": 75,   // regularidad del timing entre sílabas (IOI std dev)
    "voicing_ratio": 80,       // % de tiempo con voz presente vs silencios internos
    "legato": 65               // continuidad de F0 en transiciones entre sílabas
  },
  "per_syllable": [
    {
      "syllable": "ca",
      "f0_measured_hz": 173,
      "f0_template_hz": 185,
      "voiced_ratio": 0.91,
      "onset_detected_ms": 12,
      "onset_expected_ms": 0,
      "timing_error_ms": 12
    }
  ],
  "warnings": ["low_voicing_syllable_2", "timing_late_onset_1"],
  "confidence": 0.83,
  "analysis_version": "praat_cloud_run_v1.0"
}
```

---

#### 2.3 · Listener en tiempo real en `TemExerciseScreen`

Después de subir el WAV, la pantalla queda escuchando el attempt doc con `StreamBuilder`:

```dart
StreamBuilder<DocumentSnapshot>(
  stream: FirebaseFirestore.instance
    .collection('ejercicios_TEM')
    .doc(ejercicioId)
    .collection('attempts')
    .doc(attemptId)
    .snapshots(),
  builder: (context, snapshot) {
    final status = snapshot.data?['status'];
    if (status == 'analyzed') {
      // Navegar a TemSummaryScreen con el resultado
    }
  },
)
```

---

#### 2.4 · `TemSummaryScreen` extendida con score

Actualizar la pantalla de resumen para mostrar el score real:

- Score global en grande (ej: `72/100`)
- Desglose por componente: Tono | Ritmo | Intensidad
- Barra de progreso visual por componente
- ⚠️ **Disclaimer obligatorio** (hardcodeado, no opcional):  
  _"Resultado preliminar — requiere validación del terapeuta antes de avanzar de nivel"_
- Botón "Volver a ejercicios"

---

### ✅ Criterios de éxito del Sprint 2

- [ ] Cloud Function se dispara al crear attempt con `status: "pending_analysis"`
- [ ] Backend descarga y procesa WAV sin errores
- [ ] `analysis_results_TEM` se escribe con score y métricas
- [ ] `attempt.status` transiciona correctamente `pending_analysis → analyzed`
- [ ] Flutter recibe el cambio en ≤ 5 segundos vía listener
- [ ] `TemSummaryScreen` muestra score desglosado + disclaimer
- [ ] Score 0–100 en escala visible para el paciente

---

---

## 🎛️ Sprint 3 — FSM Clínica + Calibración + QA Final
**Duración:** 2 semanas  
**Objetivo:** Implementar la lógica clínica completa (4 intentos, retroceso, avance de nivel), la calibración por paciente, historial, y QA cruzado del módulo completo.

### Tareas

#### 3.1 · FSM Clínica en `TemExerciseScreen`

Máquina de estados que controla el flujo de un ejercicio completo:

```
Estados:
idle → playing → recording → uploading → analyzing → result
                                                         │
                                    ┌────────────────────┤
                                    │                    │
                               score OK?             score bajo
                                    │                    │
                              next_step            attempt < 4?
                                    │               │        │
                              (avanza paso)        SÍ       NO
                                                    │        │
                                                retry    abandon
                                                       (score_step = 0)
```

**Reglas clínicas por nivel (protocolo Helm-Estabrooks et al., 1989):**

**NIVEL 1 — sin retrocesos, puntuación 0/1 por paso:**
- Paso 1: sin puntuación (paciente solo escucha)
- Pasos 2-5: 1 punto si éxito, 0 si falla
- Si falla 4 veces en cualquier paso → estímulo abandonado (`score_step = 0`), nuevo estímulo desde Paso 1
- **No hay retrocesos en Nivel 1**
- Metrónomo activo en Pasos 1-4; **desactivado en Paso 5** (respuesta a pregunta)

**NIVEL 2 — con retrocesos formales, puntuación 0/1/2 por paso:**
- Paso 1: sin puntuación
- Paso 2 (unísono con apagado): 1 punto
- Paso 3 (repetición con pausa 6s): **2 pts** sin retroceso / **1 pt** con retroceso al Paso 2
- Paso 4 (respuesta a pregunta con pausa 6s): **2 pts** sin retroceso / **1 pt** con retroceso al Paso 3
- Si falla tras retroceso → estímulo abandonado

**NIVEL 3 — sprechgesang + prosodia normal, puntuación 0/1/2:**
- Paso 1 (repetición diferida): **2 pts** / **1 pt** con retroceso a unísono+apagado
- Paso 2 (presentación sprechgesang): sin puntuación
- Paso 3 (sprechgesang con apagado): **2 pts** / **1 pt** con retroceso
- Paso 4 (repetición hablada diferida, prosodia normal): **2 pts** / **1 pt** con retroceso
- Paso 5 (pregunta de prueba, prosodia normal): **2 pts** / **1 pt** con retroceso

**Criterio de avance de nivel (longitudinal entre sesiones):**
- Permanecer en programa: media de 3 sesiones recientes > media de las 3 anteriores
- **Avanzar al nivel superior:** ≥ 90% en 5 sesiones consecutivas usando diversidad de estímulos
- Este criterio es **calculado en el panel del terapeuta**, NO en la app del paciente
- La app solo registra los datos; el terapeuta aprueba el avance

**Avance de paso dentro de un estímulo:** guiado por el score automático + regla de intentos; attempt doc incluye `pending_therapist_review: true`

**Pasos clínicos del TEM (3 niveles del protocolo original):**

| Nivel | Paso | Nombre | Puntuación | Retroceso a |
|-------|------|--------|------------|-------------|
| 1 | 1 | Tarareo (app entona, paciente escucha) | Sin puntuación | — |
| 1 | 2 | Entonación al unísono | 0/1 | — (abandona) |
| 1 | 3 | Unísono con apagado | 0/1 | — (abandona) |
| 1 | 4 | Repetición inmediata | 0/1 | — (abandona) |
| 1 | 5 | Respuesta a pregunta | 0/1 | — (abandona) |
| 2 | 1 | Presentación del estímulo | Sin puntuación | — |
| 2 | 2 | Unísono con apagado | 0/1 | — (abandona) |
| 2 | 3 | Repetición con pausa (6s) | 0/1/2 | Paso 2 |
| 2 | 4 | Respuesta a pregunta (6s) | 0/1/2 | Paso 3 |
| 3 | 1 | Repetición diferida | 0/1/2 | Unísono+apagado |
| 3 | 2 | Presentación sprechgesang | Sin puntuación | — |
| 3 | 3 | Sprechgesang con apagado | 0/1/2 | Sprechgesang unísono |
| 3 | 4 | Repetición hablada diferida | 0/1/2 | Paso 3 |
| 3 | 5 | Respuesta a pregunta (prosodia normal) | 0/1/2 | Paso 4 |

---

#### 3.2 · Calibración individual (`TemCalibrationScreen`)

Pantalla que determina los parámetros acústicos base del paciente. Implementa una **arquitectura híbrida de 2 fases**: las métricas vocales (F0 + timing) se calculan en Cloud Run con Parselmouth (rigor clínico, maneja voces débiles o afónicas), mientras que la latencia del hardware se mide localmente en Dart (~30 líneas).

---

**Fase 1 — Métricas vocales (Cloud Run, ~5-10s)**

1. UI muestra instrucción: *"Emita una vocal sostenida 'aaaaa' cuando escuche el tono"*
2. Flutter reproduce tono de inicio y graba ~3s de vocal sostenida (WAV 16kHz mono)
3. Sube WAV a Storage: `calibraciones/{pacienteId}/vocal_{timestamp}.wav` con metadata `{ type: "calibration", pacienteId }`
4. Cloud Function detecta el archivo y llama `POST /calibrate` en Cloud Run
5. Cloud Run / Parselmouth:
   - Mide F0 frame a frame (solo frames voiced)
   - `f0_min` = percentil p10, `f0_max` = percentil p90, `f0_comfort` = mediana p50
   - `avg_syllable_duration_ms` = onset detection sobre vocales repetidas (si se pide al paciente repetir "pa-pa-pa")
6. Cloud Run escribe `pacientes/{pacienteId}/calibracion` parcial (sin `offset_ms`) en Firestore
7. Flutter muestra resultado provisional (spinner mientras espera Firestore update)

**Por qué Cloud Run y no Flutter local:** patients con afasia frecuentemente tienen voz débil, temblorosa o entrecortada. Librerías Dart de pitch (`pitch_detector_dart`, `tarso`) están diseñadas para voz normal. Parselmouth/Praat tiene algoritmos YIN + SWIPE' robustos para F0 en señal débil, sin mínimo de amplitud.

---

**Fase 2 — Latencia del hardware (Flutter local Dart, ~30 líneas)**

Mide el desfase entre el instante en que el altavoz emite un clic y el instante en que el micrófono lo detecta. Es una propiedad del hardware del dispositivo, no del paciente — se mide una sola vez por dispositivo.

```dart
// Pseudocódigo — ~30 líneas Dart
Future<int> measureOffsetMs() async {
  final recorder = AudioRecorder();
  await recorder.start(config, path: tempWavPath);

  final clickMs = DateTime.now().millisecondsSinceEpoch;
  await audioPlayer.play(AssetSource('assets/audio/calibration_click.wav'));

  await Future.delayed(const Duration(milliseconds: 500));
  await recorder.stop();

  // Leer buffer WAV, encontrar índice de pico de amplitud
  final buffer = await WavReader.readSamples(tempWavPath);
  final peakIndex = buffer.indexOf(buffer.reduce(max));
  final peakMs = (peakIndex / sampleRate * 1000).round();

  return peakMs; // offset_ms = tiempo desde inicio de grabación hasta pico del clic
}
```

1. Flutter reproduce `calibration_click.wav` por altavoz mientras graba simultáneamente
2. Detecta índice del pico de amplitud en el buffer de audio capturado
3. `offset_ms` = milisegundos desde inicio de grabación hasta el pico
4. Combina con los datos de Fase 1 y escribe el documento completo en Firestore

---

**Documento resultado (`pacientes/{pacienteId}/calibracion`):**
```jsonc
{
  "f0_min": 120,
  "f0_max": 210,
  "f0_comfort": 155,
  "avg_syllable_duration_ms": 720,
  "offset_ms": 60,          // medido localmente en Dart (Fase 2)
  "last_calibrated_at": "timestamp",
  "calibration_version": "hybrid_v1.0"
}
```

**Asset requerido:** `assets/audio/calibration_click.wav` — clic corto (~5ms, amplitud alta, 1kHz) para detección precisa del pico.

---

#### 3.3 · `TemHistoryScreen` — Historial de ejercicios

Lista de attempts completados por el paciente:

- Fecha, estímulo, score global, estado (analyzed / validated)
- Filtro por estímulo o por rango de fechas
- Si `status == "validated"` → mostrar icono de terapeuta ✅

---

#### 3.4 · Integración del `offset_ms` en `RhythmEngine`

Leer `pacientes/{pacienteId}/calibracion.offset_ms` y pasarlo al `RhythmEngine` para compensar la latencia micrófono-altavoz del dispositivo específico del paciente.

---

#### 3.5 · QA Cruzado

Verificar integridad del módulo completo contra los criterios del HANDOFF:

| Criterio | Método de verificación |
|----------|------------------------|
| `LipAnimationWidget.fromTimeline` sincronizado ±80ms | Test unitario con timeline mock |
| WAV 16kHz / mono / 16-bit | `ffprobe` o `RecordConfig` verificación |
| Attempt doc creado antes de mostrar resultado | Revisar orden de operaciones en código |
| Backend escribe `analysis_results_TEM` correctamente | Test de integración con backend |
| Transición `pending_analysis → analyzed` en Flutter | Test con Firestore emulado |
| FSM: 4 intentos → abandon funciona | Test de estados |
| Retroceso de paso funciona | Test de estados |
| 10 estímulos visibles y reproducibles | Test manual |
| `flutter test` 80 tests pasan sin regresiones | CI/CD |

---

### ✅ Criterios de éxito del Sprint 3 (Definición de Hecho MVP-1)

- [ ] FSM completa: 4 intentos, retroceso, abandon — todos los flujos probados
- [ ] Calibración guarda parámetros correctos en Firestore
- [ ] `offset_ms` se aplica en `RhythmEngine`
- [ ] `TemHistoryScreen` muestra historial real del paciente
- [ ] Disclaimer de validación del terapeuta visible en todos los resultados
- [ ] Promoción de nivel: DESHABILITADA en cliente (solo terapeuta vía consola/panel)
- [ ] 10 estímulos reales (o mock sólidos) visibles y reproducibles
- [ ] `flutter test` pasa los ≥80 tests sin regresiones
- [ ] QA cruzado completo con todos los criterios del HANDOFF ✅

---

---

## 📦 Colecciones Firestore a Crear

Resumen de todas las colecciones nuevas que introduce el módulo TEM:

| Colección | Quién escribe | Quién lee |
|-----------|---------------|-----------|
| `stimuli_TEM/` | Sistema / Fonoaudiólogo | Flutter (StimulusRepository) |
| `sesiones_TEM/` | Flutter (SessionManager) | Flutter + Backend |
| `sesiones_TEM/{id}/attempts/` | Flutter (RecordingService) | Flutter + Backend |
| `analysis_results_TEM/` | Backend Python (Cloud Run) | Flutter (listener) |
| `pacientes/{id}/calibracion` | Flutter (TemCalibrationScreen) | Flutter (RhythmEngine) |
| `pacientes/{id}/nivel_tem` | Sistema / Terapeuta (panel web) | Flutter (SessionManager) |

> `ejercicios_TEM/` eliminada del modelo TEM — con sesiones Duolingo no existe el concepto de "ejercicio asignado individual". El nivel del paciente vive en `pacientes/{id}/nivel_tem`.

---

## 📦 Storage: Rutas Estandarizadas

```
gs://apphasia-7a930.firebasestorage.app/
├── stimuli/
│   ├── audio/      ST_TEM_N1_001_v1.wav   ← formato: ST_TEM_{nivel}_{num}_v{version}.wav
│   └── images/     ST_TEM_N1_001.jpg
└── attempts/
    └── {pacienteId}/
        └── {sessionId}/
            └── {attemptId}.wav
```

> `timelines/` eliminado — el timeline se calcula en Flutter a partir de `syllables`, `onsets_ms` y `durations_ms` del documento en `stimuli_TEM/`. No hay archivo JSON separado en Storage.

**Formato de audio obligatorio en TODA la app TEM:** WAV PCM 16-bit, mono, 16000 Hz

---

## ⚠️ Reglas No Negociables (de cualquier sprint)

1. `unifyCommissures()` siempre antes de pintar labios — ya implementado en `LipPainter`
2. Nunca regenerar el timeline desde texto si hay `timeline.json` disponible
3. Validar invariante `syllables.length == onsets_ms.length == durations_ms.length` al parsear
4. Audio: **WAV PCM 16-bit, mono, 16000 Hz** — sin excepciones
5. **Metrónomo:** clic de audio (WAV corto) en cada `onsetsMs[i]` via `AudioPlayer` dedicado — sin vibración del dispositivo; desactivado en el Paso de respuesta a pregunta (último paso de cada nivel)
6. **Imagen semántica:** siempre visible en `TemExerciseScreen` (Pasos 1-5) cuando `image_url` está disponible — `TemDetailScreen` no existe
7. Score siempre con disclaimer de validación del terapeuta
8. **Avance de paso** (Pasos 1→N dentro de un estímulo): guiado por score automático + regla de 4 intentos, con `pending_therapist_review: true`; **avance de nivel** (Nivel 1→2→3): exclusivamente el terapeuta desde el panel web tras verificar ≥90% en 5 sesiones consecutivas
9. Usar `pacienteId` (no `patientId`) en todo el código TEM — coherente con Firestore existente
10. **No existe selección libre de estímulos** — el `SessionManager` construye la secuencia; el paciente solo inicia la sesión

---

*Versión: MVP-1 | Fecha: 1 de marzo de 2026*  
*Basado en: HANDOFF_TEM_MODULE.md*
