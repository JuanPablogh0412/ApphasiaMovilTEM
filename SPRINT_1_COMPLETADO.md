# Sprint 1 — Módulo TEM: Sesión completa Nivel 1

**Fecha de cierre:** Sprint 1  
**Estado:** ✅ COMPLETADO  
**Tests:** 36/36 ✅ (11 Sprint 0 + 25 Sprint 1)  
**Warnings nuevos:** 0  
**Errores de compilación:** 0

---

## Resumen ejecutivo

Sprint 1 implementa el flujo completo de sesión TEM (Therapist Enhanced Melodic Intonation) desde la pantalla de inicio hasta el resumen post-sesión, incluyendo todos los servicios de backend (Firestore, Firebase Storage, grabación WAV), el motor de ritmo con sincronización lip-sync y el algoritmo anti-perseveración del protocolo MIT.

El protocolo implementado corresponde al **Nivel 1** (5 pasos por estímulo, máximo 4 intentos antes de abandon), según la especificación de Helm-Estabrooks et al. (1989).

---

## Componentes implementados

### 1. `StimulusRepository` — `lib/services/tem/stimulus_repository.dart`

Repositorio de datos para estímulos TEM. Accede a Firestore y Firebase Storage.

**Métodos nuevos:**

| Método | Descripción |
|--------|-------------|
| `getAsignados(pacienteId)` | Devuelve ejercicios TEM asignados al paciente desde `ejercicios_TEM` |
| `getStimulus(stimulusId)` | Obtiene metadatos del estímulo desde `stimuli_TEM/{id}` |
| `getTimeline(stimulusId, url)` | Descarga timeline JSON desde Firebase Storage, cachea en SharedPreferences |
| `cacheTimeline / getCachedTimeline` | Caché local con clave `tem_timeline_{stimulusId}` |
| `getNivelActual(pacienteId)` | Lee `pacientes/{uid}.nivel_actual` de Firestore |
| `getStimuliForNivel(nivelClinico)` | Filtra `stimuli_TEM` por `nivel_clinico` |
| `getSessionsSince(pacienteId, since)` | Historial de sesiones recientes para anti-perseveración |
| `getCompletedSessions(pacienteId)` | Sesiones completadas para estadísticas del Home |

---

### 2. `RhythmEngine` — `lib/services/tem/rhythm_engine.dart`

Motor de ritmo que sincroniza reproducción de audio con animación labial y metrónomo.

**Campos nuevos:**

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `metronomePlayer` | `AudioPlayer?` | Reproductor opcional de clic de metrónomo |
| `_positionSub` | `StreamSubscription?` | Suscripción a `positionStream` del audio |
| `_stateSub` | `StreamSubscription?` | Suscripción a `playerStateStream` |
| `_lastSyllableIndex` | `int` | Índice de la última sílaba activada |

**Implementación de `play()`:**

1. Reinicia `_lastSyllableIndex = -1` y empieza audio
2. Suscribe `positionStream` → detecta cruces de onset por sondeo descendente
3. En cada cruce: emite `MetronomeClickEvent` + activa metrónomo audio (si presente)
4. Emite `SyllableActivateEvent(index)` en cada onset cruzado
5. Emite `VisemeChangeEvent` en cada frame (llamada a `timeline.getVisemeAtTime`)
6. Suscribe `playerStateStream` → emite `PlaybackEndEvent` al completar

**Eventos emitidos:**

```
MetronomeClickEvent  → clic de metrónomo por cada sílaba
SyllableActivateEvent(index) → activar sílaba N en UI
VisemeChangeEvent(viseme) → actualizar forma labial actual
PlaybackEndEvent → reproducción terminada
```

**Corrección de bug:**  
Se eliminó el chequeo `if (viseme != null)` redundante ya que `LipTimeline.getVisemeAtTime` devuelve `Viseme` (no-nullable). Se corrigió el patrón de null-check encadenado sobre `metronomePlayer` que generaba `unnecessary_null_comparison`.

---

### 3. `RecordingService` — `lib/services/tem/recording_service.dart`

Servicio de grabación WAV + upload a Firebase Storage + creación de doc en Firestore.

**Constante de configuración (obligatoria en toda la app TEM):**

```dart
static const RecordConfig kAudioConfig = RecordConfig(
  encoder: AudioEncoder.wav,
  sampleRate: 16000,
  numChannels: 1,
  bitRate: 256000,
);
```

**Flujo de `uploadAttempt`:**

1. Calcula `attemptId = 'ATT_{sessionId}_{stimulusId}_s{step}_a{attemptNumber}'`
2. Sube WAV a Storage en `attempts/{pacienteId}/{sessionId}/{attemptId}.wav`
3. Crea doc Firestore en `sesiones_TEM/{sessionId}/attempts/{attemptId}`:
   ```json
   {
     "attemptId": "ATT_...",
     "stimulusId": "...",
     "step": 2,
     "stepName": "unisono",
     "attemptNumber": 1,
     "audioPath": "attempts/.../...",
     "recordedAt": "<serverTimestamp>",
     "status": "pending_analysis",
     "pending_therapist_review": true
   }
   ```
4. Elimina el archivo WAV local

**BREAKING CHANGE vs stub:** Parámetro `ejercicioId` renombrado a `sessionId` para alinearse con la nomenclatura Firestore.

---

### 4. `SessionManager` — `lib/services/tem/session_manager.dart`

Orquesta la construcción de la sesión TEM con 5 reglas anti-perseveración.

**Algoritmo `buildSession`:**

```
1. getNivelActual(pacienteId)         → nivel = 1|2|3
2. getStimuliForNivel(nivel)          → todos los estímulos del nivel
3. getSessionsSince(paciente, 24h)    → excluir intentados ayer
   └─ fallback si < [size] restantes
4. filtrar fallos_consecutivos < 4   → excluir "demasiado difíciles"
   └─ fallback si todos filtrados
5. sort by num_completions ASC        → priorizar los menos practicados
6. applyTonalAntiPerseveration        → shuffle respetando regla tonal
7. Crear doc sesiones_TEM/{SES_<ms>}  → status: 'in_progress'
8. Exponer lastSessionId              → para el ViewModel
```

**Regla tonal (Regla 5):**  
No colocar dos estímulos CONSECUTIVOS con el mismo `patron_tonal` Y el mismo `num_silabas`. Implementada como método estático público `applyTonalAntiPerseveration` para permitir pruebas unitarias puras.

**API Firestore:**

| Método | Doc actualizado |
|--------|----------------|
| `markStimulusCompleted` | `sesiones_TEM/{sessionId}` — `estimuloActualIndex++`, array `completedStimuli` |
| `markStimulusAbandoned` | `sesiones_TEM/{sessionId}` — `estimuloActualIndex++`, array `abandonedStimuli` |
| `closeSession` | `sesiones_TEM/{sessionId}` — `status: 'completed'`, `scoreSesion`, `completedAt` |

---

### 5. `TemSessionViewModel` — `lib/presentation/viewmodels/tem/tem_session_viewmodel.dart`

ViewModel principal del módulo TEM. Orquesta todas las capas (Repository, SessionManager, RhythmEngine, RecordingService) y expone la FSM de la sesión como propiedades observables.

**Constantes del protocolo:**

```dart
static const int totalSteps = 5;    // Nivel 1: escucha/unísono/completion/repetición/pregunta
static const int maxAttempts = 4;   // MIT: 4 intentos antes de abandon
```

**FSM de sesión (simplified):**

```
Estado inicial: sessionActive=false, currentStep=1, currentAttempt=1

startSession(uid)
  → buildSession → _stimulusIds[]
  → _loadCurrentStimulus() → currentStimulus
  → sessionActive = true

advanceStep()
  → currentStep < 5: currentStep++
  → currentStep == 5: _advanceStimulus(completed: true)

recordAttemptResult(score)
  → score > 0: sessionScore += score → advanceStep()
  → score == 0 && attempt < maxAttempts: currentAttempt++
  → score == 0 && attempt >= maxAttempts: abandonCurrentStimulus()

_advanceStimulus(completed)
  → Firestore: markCompleted | markAbandoned
  → ultimoEstímulo: finishSession()
  → sino: currentStimulusIndex++, currentStep=1, currentAttempt=1
      → _loadCurrentStimulus()

finishSession()
  → sessionFinished = true
  → closeSession(sessionId, scoreSesion)
```

**Getters derivados:**

| Getter | Lógica |
|--------|--------|
| `currentStepName` | `escucha / unisono / completion / repeticion / pregunta` |
| `isRecordingStep` | `step >= 2` |
| `hasMetronome` | `step <= 4` |
| `showTextQuestion` | `step == 5` |
| `stepInstruction` | Texto de instrucción para la UI |

---

### 6. `TemHomeScreen` — `lib/presentation/screens/tem/tem_home_screen.dart`

Pantalla de inicio del módulo TEM para el paciente.

**Elementos UI:**

- `_NivelCard`: tarjeta degradado con nivel clínico actual y descripción
- `_StatsRow` + `_StatCard`: fila de estadísticas (sesiones completadas, score promedio)
- `_StartButton`: botón principal "Iniciar sesión TEM"
- `_SecondaryButtons`: accesos a Historial y Calibración (rutas futuras)

**Flujo de navegación:**

```dart
// Al pulsar "Iniciar sesión":
vm.startSession(uid)
→ Navigator.push(ChangeNotifierProvider.value(value: vm, child: TemExerciseScreen()))
```

---

### 7. `TemExerciseScreen` — `lib/presentation/screens/tem/tem_exercise_screen.dart`

Pantalla principal de ejercicio. Implementa los 5 pasos del protocolo MIT Nivel 1.

**Constructor dual (compatibilidad con router):**

```dart
const TemExerciseScreen({super.key}) : args = const {};
const TemExerciseScreen.withArgs({super.key, required this.args});
```

**Protocolo por pasos:**

| Paso | Nombre | Acción del paciente | UI |
|------|--------|--------------------|----|
| 1 | Escucha y entona | Escuchar (máx. 2 veces) | `_Paso1Actions` — botón play 1/2, 2/2, "Continuar" |
| 2 | Entona en unísono | Grabar junto al audio | `_RecordingActions` |
| 3 | Completion intoning | Grabar la segunda mitad | `_RecordingActions` |
| 4 | Repetición | Grabar sin audio guía | `_RecordingActions` |
| 5 | Pregunta Sí/No | Responder la pregunta clínica | `_QuestionCard` + `_RecordingActions` |

**Elementos UI:**

- `_StimulusProgressBar`: progreso estímulos (N/total)
- `_StepProgressBar`: progreso pasos (1-5)
- `_InstructionBanner`: instrucción del paso actual
- `_LipAnimationPanel`: animación labial autónoma (loop permanente)
- `_StimulusText`: texto del estímulo (oculto en paso 5)
- `_Paso1Actions` / `_RecordingActions`: controles de acción según el paso

**Flujo de grabación:**

```
_startRecording() → recordingService.startRecording()
_stopRecording()  → recordingService.stopRecording() → _recordedPath
_uploadAndAdvance → recordingService.uploadAttempt() → vm.recordAttemptResult(1)
_onMarkFailed()   → vm.recordAttemptResult(0)
```

---

### 8. `TemSessionSummaryScreen` — `lib/presentation/screens/tem/tem_session_summary_screen.dart`

Pantalla de resumen post-sesión.

**Constructor dual:**

```dart
const TemSessionSummaryScreen({super.key}) : args = const {};
const TemSessionSummaryScreen.withArgs({super.key, required this.args});
```

**Fallback de datos:**  
Accede al ViewModel vía `context.read<TemSessionViewModel>()` con try/catch; si no hay Provider disponible (acceso por ruta nominada), usa el mapa `args`.

**Elementos UI:**

- `_SummaryHeader`: tarjeta degradado con score y mensaje motivacional
- `_StimuliSummary`: conteo completados/abandonados + chips de IDs abandonados
- `_DisclaimerCard`: "Resultado preliminar — requiere validación del terapeuta"
- `_HomeButton`: navega a `/tem-home` limpiando todo el stack de navegación

---

### 9. `app_router.dart` — `lib/routes/app_router.dart`

Actualizado para inyectar el `ChangeNotifierProvider` en la ruta `/tem-home`.

```dart
'/tem-home': (_) => ChangeNotifierProvider(
  create: (_) => TemSessionViewModel(
    repository: StimulusRepository(),
    sessionManager: SessionManager(repository: StimulusRepository()),
    recordingService: RecordingService(),
  ),
  child: const TemHomeScreen(),
),
'/tem-exercise': (ctx) => TemExerciseScreen.withArgs(args: ...),
'/tem-session-summary': (ctx) => TemSessionSummaryScreen.withArgs(args: ...),
```

---

## Tests implementados — `test/sprint1_tem_test.dart`

### Estrategia de testing

Los tests cubren exclusivamente código **puro / estático / sin Firebase**:

- `StimulusRepository`, `SessionManager`, `RecordingService` y `TemSessionViewModel` usan `FirebaseFirestore.instance` y `FirebaseStorage.instance` en sus constructores → requieren emuladores Firebase para tests de integración (Sprint 2+).
- Los métodos estáticos y constructores pures se prueban en la suite actual.

### Grupos y resultados

| Grupo | Tests | Estado |
|-------|-------|--------|
| `SessionManager.applyTonalAntiPerseveration` | 7 | ✅ PASS |
| `RhythmEngine` (hapticPatternMs, events, dispose) | 5 | ✅ PASS |
| `RecordingService.kAudioConfig` (WAV constants) | 4 | ✅ PASS |
| `TemSessionViewModel` constants | 2 | ✅ PASS |
| `TemSessionSummaryScreen` widget | 6 | ✅ PASS |
| **TOTAL Sprint 1** | **25** | **✅ 25/25** |
| Sprint 0 (regresión) | 11 | ✅ PASS |
| **TOTAL General** | **36** | **✅ 36/36** |

### Casos de prueba destacados

**Algoritmo anti-perseveración:**
- Lista diversa → nunca dos consecutivos con mismo `patron_tonal` Y `num_silabas`
- Caso homogéneo (todos LH/2) → no duplica IDs aunque no pueda satisfacer la regla
- Lista vacía → resultado vacío (no crash)
- `size > len(candidates)` → devuelve todos disponibles
- Estímulos sin `patron_tonal` → no lanzan excepción

**RhythmEngine:**
- `hapticPatternMs` ≡ copia de `timeline.onsetsMs`
- Mutación de la copia devuelta NO afecta al engine (aislamiento)
- `events` es stream broadcast (acepta múltiples listeners)
- `dispose()` es idempotente (no lanza excepción)

**RecordingService:**
- `kAudioConfig.encoder == AudioEncoder.wav`
- `kAudioConfig.sampleRate == 16000`
- `kAudioConfig.numChannels == 1`
- `kAudioConfig.bitRate == 256000`

**TemSessionSummaryScreen:**
- Renderiza sin Provider (vía `withArgs`) → AppBar "Resultado de la sesión"
- Disclaimer "Resultado preliminar" presente
- Score numérico visible en pantalla
- Chips de estímulos abandonados se muestran cuando la lista no está vacía

---

## Dependencias añadidas

```yaml
# En pubspec.yaml — añadido en Sprint 1:
path_provider: ^2.1.0   # Para directorio temporal de grabaciones WAV
```

Todas las demás dependencias ya existían desde Sprint 0:
`just_audio`, `record`, `firebase_storage`, `cloud_firestore`, `shared_preferences`, `provider`.

---

## Patrones arquitectónicos establecidos

### Constructor dual para pantallas con router

```dart
// Pantallas que reciben datos tanto vía Provider/navigation como vía ruta nominada:
const TemExerciseScreen({super.key}) : args = const {};          // default
const TemExerciseScreen.withArgs({super.key, required this.args}); // router
```

### ChangeNotifierProvider para sharing de ViewModel entre pantallas

```dart
// Creación en la ruta /tem-home:
ChangeNotifierProvider(create: (_) => TemSessionViewModel(...), child: TemHomeScreen())

// Compartir el mismo ViewModel al navegar a screens hijos:
Navigator.push(ctx, MaterialPageRoute(builder: (_) =>
  ChangeNotifierProvider.value(value: vm, child: TemExerciseScreen())
))
```

### Getter de ViewModel seguro en screens de resumen

```dart
TemSessionViewModel? _tryGetViewModel(BuildContext context) {
  try { return context.read<TemSessionViewModel>(); }
  catch (_) { return null; }
}
```

---

## Colecciones Firestore utilizadas

| Colección | Documento | Campos clave |
|-----------|-----------|--------------|
| `pacientes/{uid}` | Perfil del paciente | `nivel_actual` |
| `stimuli_TEM/{stimulusId}` | Metadatos del estímulo | `texto`, `audio_url`, `patron_tonal`, `num_silabas`, `fallos_consecutivos`, `num_completions` |
| `ejercicios_TEM/{id}` | Ejercicio asignado | `pacienteId`, activo |
| `sesiones_TEM/{sessionId}` | Sesión TEM | `status`, `estimulosSecuencia`, `scoreSesion`, `completedStimuli`, `abandonedStimuli` |
| `sesiones_TEM/{sessionId}/attempts/{attemptId}` | Intento individual | `audioPath`, `status: 'pending_analysis'`, `pending_therapist_review: true` |

---

## Limitaciones conocidas y trabajo futuro

| Ítem | Sprint asignado |
|------|----------------|
| Tests de integración del ViewModel FSM con emuladores Firebase | Sprint 2 |
| Retroceso de paso (`stepBack`) para Niveles 2-3 | Sprint 3 |
| Pantalla de Historial de sesiones | Sprint 2 |
| Pantalla de Calibración de micrófono | Sprint 2 |
| Feedback háptico real (vibración) vía `MetronomeClickEvent` | Sprint 2 |
| RhythmEngine: modo sin audio (solo haptic + lip) | Sprint 3 |
| FSM Niveles 2 y 3 (pasos adicionales, lógica de retroceso) | Sprint 3 |
| Análisis automático de pronóstico vía modelo ML | Sprint 3+ |

---

## Ejecución de los tests

```bash
# Solo Sprint 1
flutter test test/sprint1_tem_test.dart --reporter=expanded

# Suite completa (Sprint 0 + Sprint 1)
flutter test

# Análisis estático
flutter analyze
```

**Resultado esperado:**
```
00:06 +36: All tests passed!
```
