# Handoff: Integración del Módulo TEM en la Aplicación Web

> **Destinatario:** Agente de IA encargado del desarrollo de la aplicación web (React 19 + Vite)  
> **Proyecto:** RehabilitIA — Plataforma de rehabilitación para pacientes con afasia  
> **Módulo:** TEM (Terapia de Entonación Melódica)  
> **Firebase Project:** `apphasia-7a930`  
> **Fecha:** Junio 2025

---

## 1. Contexto General

RehabilitIA es una plataforma de rehabilitación del habla para pacientes con afasia. La plataforma tiene tres componentes:

| Componente | Tecnología | Responsable |
|---|---|---|
| **App móvil** (paciente) | Flutter + Firebase | Ya implementado |
| **App web** (terapeuta) | React 19 + Vite + Firebase | **Tu responsabilidad** |
| **Backend de análisis** | Python (FastAPI) en Cloud Run + Cloud Functions | Ya desplegado |

La app web ya soporta dos terapias: **VNEST** (Verb Network Strengthening Treatment) y **SR** (Sentence Reading). Ahora necesita integrar **TEM** (Terapia de Entonación Melódica).

### ¿Qué es TEM?

TEM es una terapia del habla basada en el protocolo MIT (Melodic Intonation Therapy) de Helm-Estabrooks. El paciente practica frases melódicas siguiendo 5 pasos clínicos. Cada intento de habla es grabado como WAV, subido a Firebase Storage, y analizado automáticamente por un backend Python que produce una puntuación clínica.

**Lo que ya existe en el móvil para TEM:**
- Pantalla de inicio con progreso del paciente
- Calibración de voz (4 fases: vocales a/i/u + glissando)
- Ejercicios con 5 pasos clínicos del protocolo MIT Nivel 1
- Grabación y upload de audio WAV 16kHz mono
- Evaluación automática vía backend Python (pitch, ritmo, inteligibilidad)
- Pantalla de resumen post-sesión
- Algoritmo anti-perseveración (selección inteligente de estímulos)

---

## 2. ¿Qué Debe Hacer el Módulo Web de TEM?

El terapeuta debe poder, desde la web:

### 2.1 Vista por paciente — Revisión de ejercicios TEM

1. **Listar sesiones TEM del paciente** — Mostrar todas las sesiones (fecha, nivel, estado, score, estímulos completados/abandonados)
2. **Ver detalle de una sesión** — Mostrar cada estímulo practicado y cada paso/intento dentro de ese estímulo
3. **Escuchar grabaciones** — Reproducir los audios WAV de cada intento del paciente
4. **Ver evaluación automática** — Mostrar los resultados del análisis del backend Python: puntuación clínica, métricas acústicas, análisis por sílaba, advertencias
5. **Sobreescribir/modificar evaluación** — El terapeuta tiene la última palabra: puede cambiar el `clinical_score` y marcar el ejercicio como revisado (`revisado: true`)

### 2.2 Vista de "biblioteca" de ejercicios TEM (solo lectura por ahora)

- Listar los estímulos TEM disponibles (colección `stimuli_TEM`)
- Ver detalles: frase, sílabas, patrón tonal, nivel, audio de referencia

### 2.3 Futuro (NO implementar ahora, solo tener en cuenta en la arquitectura)

- Crear nuevos ejercicios/estímulos TEM desde la web
- Asignar ejercicios TEM a pacientes específicos

---

## 3. Modelo de Datos Firestore — Colecciones TEM

### 3.1 `stimuli_TEM/{stimulusId}` — Estímulos de referencia (seed, solo lectura)

Son los 9 estímulos del Nivel 1. Los crea el equipo de desarrollo, no el terapeuta.

```jsonc
{
  "stimulusId": "ST_TEM_N1_001",       // ID del estímulo
  "texto": "mamá",                      // Frase a practicar
  "syllables": ["ma", "má"],            // Lista de sílabas
  "onsets_ms": [0, 500],                // Inicio de cada sílaba (ms)
  "durations_ms": [450, 450],           // Duración de cada sílaba (ms)
  "audio_duration_ms": 950,             // Duración total del audio (ms)
  "audio_url": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N1_001_v1.wav",
  "f0_template_hz": [180.0, 175.0],     // F0 esperado por sílaba (Hz)
  "nivel_clinico": 1,                    // Nivel clínico (1, 2 o 3)
  "patron_tonal": "LH",                 // Patrón tonal (LH, HL, LHL, etc.)
  "num_silabas": 2,                      // Número de sílabas
  "categoria": "familia",               // Categoría semántica
  "pregunta_texto": "¿Quién te cuida?", // Pregunta para el paso 5
  "imagen_url": "gs://...ST_TEM_N1_001.jpg"  // Imagen ilustrativa (opcional)
}
```

### 3.2 `ejercicios/{ejercicioId}` — Metadatos generales del ejercicio

Colección compartida con VNEST y SR. Se filtra por `terapia: "TEM"`.

```jsonc
{
  "id": "E0A1B2",                      // ID del ejercicio (6 hex)
  "id_paciente": "UID123",             // UID del paciente
  "terapia": "TEM",                    // ← Filtrar por este campo
  "tipo": "privado",                   // "privado" (generado por IA para el paciente)
  "creado_por": "IA",                  // Quién lo creó
  "fecha_creacion": Timestamp,         // Cuándo se creó
  "revisado": false                    // ← El terapeuta marca true al revisar
}
```

> **Clave para la web:** El campo `revisado` es el que el terapeuta modifica. Cuando `revisado: false`, el ejercicio está **pendiente de revisión**.

### 3.3 `ejercicios_TEM/{ejercicioId}` — Detalle específico TEM

Enlazado 1:1 con `ejercicios/{ejercicioId}`.

```jsonc
{
  "id_ejercicio_general": "E0A1B2",                    // FK → ejercicios/{id}
  "sesion_tem_id": "SES_1719000000000",                // FK → sesiones_TEM/{id}
  "nivel": 1,                                           // Nivel del ejercicio
  "estimulosSecuencia": ["ST_TEM_N1_006", "ST_TEM_N1_001", ...],  // Estímulos asignados
  "status": "completed" | "in_progress" | "abandoned",  // Estado
  "startedAt": Timestamp,
  "completedAt": Timestamp | null,
  "scoreSesion": 28 | null                               // Puntuación final
}
```

### 3.4 `sesiones_TEM/{sessionId}` — Sesión clínica completa

Cada vez que el paciente inicia una sesión de TEM se crea este documento.

```jsonc
{
  "sessionId": "SES_1719000000000",                    // ID de la sesión
  "ejercicio_tem_id": "E0A1B2",                       // FK → ejercicios_TEM/{id}
  "pacienteId": "UID123",                              // UID del paciente
  "nivel": 1,                                          // Nivel clínico
  "estimulosSecuencia": ["ST_TEM_N1_006", "ST_TEM_N1_001", ...],
  "estimuloActualIndex": 5,                            // Progreso actual
  "startedAt": Timestamp,
  "completedAt": Timestamp | null,
  "scoreSesion": 28 | null,                            // Score final de la sesión
  "status": "completed" | "in_progress",
  "completedStimuli": ["ST_TEM_N1_006", "ST_TEM_N1_001", ...],   // Estímulos exitosos
  "abandonedStimuli": ["ST_TEM_N1_003"]                           // Estímulos fallidos (4 fallos)
}
```

### 3.5 `sesiones_TEM/{sessionId}/attempts/{attemptId}` — Intentos individuales ⭐

**Esta es la subcolección más importante para la web.** Cada intento de grabación del paciente.

```jsonc
{
  "attemptId": "ATT_SES_1719000000000_ST_TEM_N1_001_s2_a1",
  "stimulusId": "ST_TEM_N1_001",         // FK → stimuli_TEM/{id}
  "paso": 2,                              // Paso clínico (1-5)
  "stepName": "unisono",                  // Nombre del paso
  "attemptNumber": 1,                     // Número de intento (1-4)
  "status": "pending_analysis" | "analyzed",  // Estado del análisis
  "audioUrl": "https://firebasestorage.googleapis.com/...",  // URL pública del WAV
  "storagePath": "attempts/UID123/SES_.../ATT_..._s2_a1.wav",
  "pacienteId": "UID123",
  "pending_therapist_review": true,       // ← Pendiente revisión terapeuta
  "createdAt": Timestamp,

  // --- Campos agregados por el backend Python (tras análisis) ---
  "analysisId": "AN_ATT_...",            // FK → analysis_results_TEM/{id}
  "clinical_score": 1,                   // Puntuación clínica (0 o 1)
  "is_intelligible": true,               // ¿Fue inteligible?
  "analyzed_at": Timestamp
}
```

**Nombres de pasos (`stepName`):**

| `paso` | `stepName` | Descripción | ¿Graba? | Intentos |
|--------|-----------|-------------|---------|----------|
| 1 | `escucha` | Solo escucha el estímulo (2 veces) | NO | 0 |
| 2 | `unisono` | Repite junto con el audio | SÍ | Hasta 4 |
| 3 | `completion` | Audio se corta a la mitad, paciente completa | SÍ | Hasta 4 |
| 4 | `repeticion` | Repite sin audio, solo con metrónomo | SÍ | 1 |
| 5 | `pregunta` | Responde una pregunta hablando | SÍ | 1 |

### 3.6 `analysis_results_TEM/{analysisId}` — Resultados del análisis acústico ⭐⭐

**Escritos por el backend Python.** Contienen el análisis detallado de cada intento.

```jsonc
{
  "analysisId": "AN_ATT_SES_1719000000000_ST_TEM_N1_001_s2_a1",
  "attemptId": "ATT_SES_1719000000000_ST_TEM_N1_001_s2_a1",  // FK → attempts
  "sessionId": "SES_1719000000000",
  "stimulusId": "ST_TEM_N1_001",
  "pacienteId": "UID123",
  "paso": 2,
  "stepName": "unisono",
  "attemptNumber": 1,
  "nivel": 1,

  // ══════════════════════════════════════════════════════════
  // PUNTUACIÓN CLÍNICA — Lo más importante para el terapeuta
  // ══════════════════════════════════════════════════════════

  "clinical_score": 1,                // 0 ó 1 (Nivel 1) ; 0, 1 ó 2 (Niveles 2-3)

  "intelligibility_decision": {
    "is_intelligible": true,
    "rationale": "voiced_ratio=0.85, rhythm_ok=true, pitch_approx=true",
    "needs_fallback": false            // true si el análisis no fue concluyente
  },

  // ══════════════════════════════════════════════════════════
  // MÉTRICAS ACÚSTICAS — Para vista detallada del terapeuta
  // ══════════════════════════════════════════════════════════

  "acoustic_metrics": {
    "voiced_ratio_global": 0.85,       // % de tiempo con voz detectada (0.0–1.0)
    "pitch_proximity": 0.72,           // Cercanía tonal al template (0.0–1.0)
    "rhythm_regularity": 0.78,         // Regularidad rítmica (0.0–1.0)
    "legato": 0.65                     // Continuidad de F0 entre sílabas (0.0–1.0)
  },

  // ══════════════════════════════════════════════════════════
  // ANÁLISIS POR SÍLABA — Vista granular para el terapeuta
  // ══════════════════════════════════════════════════════════

  "per_syllable": [
    {
      "syllable": "ma",               // Texto de la sílaba
      "syllable_index": 0,
      "f0_measured_hz": 173.0,         // F0 detectado en la grabación (Hz)
      "f0_template_hz": 180.0,         // F0 esperado (Hz)
      "f0_error_cents": -69.2,         // Error tonal en cents
      "voiced_ratio": 0.91,            // Porcentaje de voz en esta sílaba
      "onset_detected_ms": 12,         // Inicio detectado (ms)
      "onset_expected_ms": 0,          // Inicio esperado (ms)
      "timing_error_ms": 12,           // Error de timing (ms)
      "duration_measured_ms": 430,     // Duración medida (ms)
      "duration_expected_ms": 450      // Duración esperada (ms)
    },
    {
      "syllable": "má",
      "syllable_index": 1,
      "f0_measured_hz": 178.0,
      "f0_template_hz": 175.0,
      "f0_error_cents": 29.3,
      "voiced_ratio": 0.88,
      "onset_detected_ms": 510,
      "onset_expected_ms": 500,
      "timing_error_ms": 10,
      "duration_measured_ms": 440,
      "duration_expected_ms": 450
    }
  ],

  // ══════════════════════════════════════════════════════════
  // ADVERTENCIAS Y METADATA
  // ══════════════════════════════════════════════════════════

  "warnings": [                        // Array de strings, posibles valores:
    "low_voicing_syllable_0",          // Poca voz detectada en sílaba X
    "timing_late_onset_1",             // Inicio tardío en sílaba X
    "pitch_out_of_range_syllable_0",   // F0 fuera de rango en sílaba X
    "short_audio",                     // Audio muy corto
    "no_voice_detected"                // No se detectó voz
  ],

  "confidence": 0.83,                  // Confianza del análisis (0.0–1.0)
  "analysis_version": "praat_cloud_run_v2.0",
  "analyzed_at": Timestamp,
  "processing_time_ms": 1200           // Tiempo de procesamiento (ms)
}
```

### 3.7 `pacientes/{uid}` — Datos del paciente (campos relevantes para TEM)

```jsonc
{
  // ... campos generales del paciente (nombre, email, etc.) ...

  "nivel_actual": 1,                    // Nivel TEM actual del paciente

  "calibracion": {                      // Mapa de calibración vocal
    "f0_min": 120,                      // Hz — rango mínimo de F0
    "f0_max": 210,                      // Hz — rango máximo de F0
    "f0_comfort": 155,                  // Hz — F0 de confort (mediana)
    "avg_syllable_duration_ms": 720,    // Duración promedio de sílaba
    "last_calibrated_at": Timestamp,    // Última calibración
    "calibration_version": "hybrid_v1.0"
  }
}
```

---

## 4. Firebase Storage — Rutas de Audio

```
gs://apphasia-7a930.firebasestorage.app/
│
├── tem/audio/                                   ← Audios de estímulos de referencia
│   └── ST_TEM_N1_001.wav
│
├── tem/timelines/                               ← JSONs con timing de sílabas
│   └── ST_TEM_N1_001.json
│
├── stimuli/audio/                               ← Audios alternativos de estímulos
│   └── ST_TEM_N1_001_v1.wav
│
├── attempts/{pacienteId}/{sessionId}/           ← Grabaciones del paciente ⭐
│   └── ATT_SES_xxx_ST_TEM_N1_001_s2_a1.wav
│
└── calibration/{pacienteId}/                    ← Audios de calibración vocal
    ├── vowel_a_{timestamp}.wav
    ├── vowel_i_{timestamp}.wav
    ├── vowel_u_{timestamp}.wav
    └── glide_{timestamp}.wav
```

> **Para la web:** Los audios de intentos (campo `audioUrl` en los attempts) ya tienen URL HTTPS pública. Puedes usarla directamente con un `<audio>` HTML para reproducción.

---

## 5. Pipeline de Evaluación (Backend Python)

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────────┐
│   Flutter     │     │  Cloud Function   │     │  Cloud Run (Python)   │
│  (paciente)   │     │  on_attempt_      │     │  backend-tem          │
│               │     │  created (Gen1)   │     │                       │
│  Graba WAV    │     │                   │     │  1. Descarga WAV      │
│  → Storage    │────▶│  Trigger al crear │────▶│  2. Analiza pitch     │
│  → Firestore  │     │  attempt doc      │     │  3. Analiza ritmo     │
│  (attempts/)  │     │                   │     │  4. Calcula score     │
└──────────────┘     └──────────────────┘     │  5. Escribe resultado │
                                                │     → analysis_results │
                                                │     → update attempt  │
                                                └──────────────────────┘
```

**Cloud Run URL:** `https://backend-tem-835895355070.us-central1.run.app`

**Cloud Functions:**
- `on_attempt_created` (Gen1) — Se dispara al crear doc en `sesiones_TEM/{sessionId}/attempts/{attemptId}`. Llama al Cloud Run.
- `on_calibration_finalized` (Gen2) — Se dispara al subir el último audio de calibración (`is_last: "true"`). Procesa la calibración vocal.

**Flujo completo:**
1. Flutter crea attempt doc con `status: "pending_analysis"`
2. Cloud Function detecta el nuevo doc (trigger `onCreate`)
3. Cloud Function llama al Cloud Run con los IDs
4. Cloud Run descarga WAV, lo analiza con Parselmouth/Praat
5. Cloud Run escribe resultado en `analysis_results_TEM/{analysisId}`
6. Cloud Run actualiza attempt doc: `status: "analyzed"`, `clinical_score`, `is_intelligible`
7. Flutter detecta el cambio via Firestore listener y muestra resultado al paciente

---

## 6. Qué Construir en la Web — Especificación de Pantallas

### 6.1 Tab "TEM" en `PacienteDetail.jsx`

Agregar una nueva pestaña TEM junto a las existentes VNEST y SR. Al seleccionarla, renderizar `PacienteTEM.jsx`.

### 6.2 `PacienteTEM.jsx` — Lista de sesiones TEM del paciente

**Query Firestore:**
```javascript
// Opción A: Desde ejercicios (igual que VNEST/SR)
db.collection('ejercicios')
  .where('id_paciente', '==', pacienteId)
  .where('terapia', '==', 'TEM')
  .orderBy('fecha_creacion', 'desc')

// Opción B: Directamente desde sesiones_TEM
db.collection('sesiones_TEM')
  .where('pacienteId', '==', pacienteId)
  .orderBy('startedAt', 'desc')
```

**Columnas de la tabla:**

| Columna | Campo | Notas |
|---------|-------|-------|
| Fecha | `startedAt` | Formatear como fecha legible |
| Nivel | `nivel` | 1, 2 ó 3 |
| Estado | `status` | Badge: "completed" verde, "in_progress" amarillo |
| Score | `scoreSesion` | Numérico, puede ser `null` |
| Completados | `completedStimuli.length` / `estimulosSecuencia.length` | Ej: "7/10" |
| Abandonados | `abandonedStimuli.length` | Número |
| Revisado | `revisado` (de `ejercicios/{id}`) | Checkbox o badge ✅/⏳ |
| Acciones | — | Botón "Ver detalle" |

### 6.3 `TemSessionDetail.jsx` — Detalle de una sesión

Al hacer clic en "Ver detalle" de una sesión, mostrar:

**Encabezado:**
- ID sesión, fecha, nivel, score total, estado
- Botón "Marcar como revisado" (actualiza `ejercicios/{id}.revisado = true`)

**Estímulos de la sesión** (iterar `estimulosSecuencia`):
Para cada estímulo, mostrar:
- Texto de la frase (leer de `stimuli_TEM/{stimulusId}`)
- Estado: completado ✅ / abandonado ❌
- Audio de referencia (reproducible)

**Intentos del estímulo** (subcolección `attempts`):

```javascript
// Query para obtener intentos de un estímulo en una sesión
db.collection('sesiones_TEM').doc(sessionId)
  .collection('attempts')
  .where('stimulusId', '==', stimulusId)
  .orderBy('paso')
  .orderBy('attemptNumber')
```

Para cada intento, mostrar:

| Elemento | Campo | UI sugerida |
|----------|-------|-------------|
| Paso | `paso` + `stepName` | Badge: "Paso 2 — Unísono" |
| Intento # | `attemptNumber` | "Intento 1/4" |
| Audio paciente | `audioUrl` | `<audio>` player ⭐ |
| Estado análisis | `status` | "analyzed" verde / "pending" gris |
| Score clínico | `clinical_score` | 0 rojo / 1 verde |
| Inteligible | `is_intelligible` | Sí ✅ / No ❌ |
| Ver análisis | — | Botón "Ver análisis detallado" |

### 6.4 `TemAnalysisDetail.jsx` — Análisis detallado de un intento

Al hacer clic en "Ver análisis detallado", leer el doc `analysis_results_TEM/{analysisId}` y mostrar:

**Sección 1 — Puntuación clínica:**
- `clinical_score`: badge grande (0 rojo / 1 verde)
- `intelligibility_decision.is_intelligible`: Sí/No
- `intelligibility_decision.rationale`: texto explicativo
- `confidence`: barra de progreso 0–100%

**Sección 2 — Métricas acústicas:**

| Métrica | Campo | Visualización sugerida |
|---------|-------|----------------------|
| Ratio de voz | `acoustic_metrics.voiced_ratio_global` | Barra de progreso |
| Proximidad tonal | `acoustic_metrics.pitch_proximity` | Barra de progreso |
| Regularidad rítmica | `acoustic_metrics.rhythm_regularity` | Barra de progreso |
| Legato | `acoustic_metrics.legato` | Barra de progreso |

**Sección 3 — Análisis por sílaba (tabla):**

| Sílaba | F0 medido | F0 esperado | Error (cents) | Voiced % | Timing error | Duración |
|--------|-----------|-------------|---------------|----------|--------------|----------|
| ma | 173 Hz | 180 Hz | -69.2 | 91% | +12 ms | 430/450 ms |
| má | 178 Hz | 175 Hz | +29.3 | 88% | +10 ms | 440/450 ms |

**Sección 4 — Advertencias:**
- Lista de `warnings[]` como badges amarillos

**Sección 5 — Sobreescritura del terapeuta:** ⭐⭐

```
┌─────────────────────────────────────────────┐
│  Evaluación del terapeuta                    │
│                                              │
│  Score clínico: [dropdown: 0 / 1]           │
│  ¿Inteligible?:  [toggle: Sí / No]         │
│  Comentario:     [textarea]                 │
│                                              │
│  [Guardar evaluación]                        │
└─────────────────────────────────────────────┘
```

**Al guardar:**
1. Actualizar `analysis_results_TEM/{analysisId}`:
   ```javascript
   {
     clinical_score: nuevoScore,                    // Sobreescribir
     therapist_override: true,                       // Marcar como sobreescrito
     therapist_score: nuevoScore,                    // Score del terapeuta
     therapist_intelligible: booleano,               // Evaluación del terapeuta
     therapist_comment: "texto libre",               // Comentario
     therapist_reviewed_at: serverTimestamp(),        // Fecha de revisión
     therapist_id: auth.currentUser.uid              // Quién revisó
   }
   ```
2. Actualizar `sesiones_TEM/{sessionId}/attempts/{attemptId}`:
   ```javascript
   {
     clinical_score: nuevoScore,                     // Sobreescribir
     is_intelligible: booleano,
     pending_therapist_review: false                  // Marcar como revisado
   }
   ```
3. Si todos los attempts de la sesión tienen `pending_therapist_review: false`, actualizar `ejercicios/{id}.revisado = true`

### 6.5 Tab "TEM" en `EjerciciosTerapeuta.jsx` — Biblioteca de estímulos

Agregar pestaña TEM en la vista de biblioteca de ejercicios. Mostrar una tabla con los estímulos disponibles.

**Query:**
```javascript
db.collection('stimuli_TEM').orderBy('nivel_clinico').orderBy('num_silabas')
```

**Columnas:**

| Columna | Campo |
|---------|-------|
| ID | `stimulusId` |
| Frase | `texto` |
| Sílabas | `syllables.join(' - ')` |
| Patrón tonal | `patron_tonal` |
| Nivel | `nivel_clinico` |
| # Sílabas | `num_silabas` |
| Categoría | `categoria` |
| Audio | `audio_url` → player |

---

## 7. Servicios Web a Crear

### 7.1 `temService.js` — Nuevo servicio

```javascript
// Funciones necesarias:

// Listar sesiones TEM de un paciente
getPatientTEMSessions(pacienteId, callback)

// Obtener detalle de una sesión
getTEMSessionDetail(sessionId)

// Obtener attempts de una sesión (con filtro opcional por stimulusId)
getTEMSessionAttempts(sessionId, stimulusId?)

// Obtener resultado de análisis
getTEMAnalysisResult(analysisId)

// Sobreescribir evaluación (terapeuta)
overrideTEMEvaluation(analysisId, attemptId, sessionId, {
  clinical_score, is_intelligible, comment
})

// Marcar ejercicio como revisado
markTEMExerciseReviewed(ejercicioId)

// Listar estímulos TEM
getTEMStimuli()

// Obtener estímulo específico
getTEMStimulus(stimulusId)

// Obtener calibración del paciente
getPatientCalibration(pacienteId)
```

### 7.2 Modificaciones a servicios existentes

**`exercisesService.js`:**
- Actualizar `getExerciseDetails()` para soportar `terapia === "TEM"` → leer de `ejercicios_TEM`

**`patientService.js`:**
- Si existe función de "obtener ejercicios de paciente", agregar filtro para TEM

---

## 8. Archivos a Crear/Modificar en la Web

### Nuevos archivos:

| Archivo | Propósito |
|---------|-----------|
| `src/services/temService.js` | Servicio Firestore para TEM |
| `src/components/patients/PacienteTEM.jsx` | Lista de sesiones TEM del paciente |
| `src/components/patients/TemSessionDetail.jsx` | Detalle de sesión con intentos |
| `src/components/patients/TemAnalysisDetail.jsx` | Análisis detallado + override |
| `src/components/exercises/TEMTable.jsx` | Tabla de estímulos TEM |
| `src/components/exercises/TEMStimulusModal.jsx` | Modal detalle de estímulo |

### Archivos a modificar:

| Archivo | Cambio |
|---------|--------|
| `src/components/patients/PacienteDetail.jsx` | Agregar tab "TEM" → render `PacienteTEM` |
| `src/components/exercises/EjerciciosTerapeuta.jsx` | Agregar tab "TEM" → render `TEMTable` |
| `src/App.jsx` | Agregar rutas si se necesitan pantallas independientes |
| `src/services/exercisesService.js` | Soportar `terapia === "TEM"` en funciones existentes |

---

## 9. Patrones a Seguir

La web ya implementa VNEST y SR. **Sigue el patrón de SR** (el más simple):

1. **Tabla con filtros** → `SRTable.jsx` como referencia para `TEMTable.jsx`
2. **Modal de detalle** → `SRExerciseModal.jsx` como referencia para `TEMStimulusModal.jsx`
3. **Vista por paciente** → `PacienteSR.jsx` como referencia para `PacienteTEM.jsx`
4. **Servicio** → `exercisesService.js` como referencia para `temService.js`

### Diferencias clave de TEM vs VNEST/SR:

| Aspecto | VNEST/SR | TEM |
|---------|----------|-----|
| Quién crea ejercicios | Terapeuta web | App móvil (automático) |
| Estructura | Plana (exercicio → respuestas) | Jerárquica (sesión → estímulos → pasos → intentos) |
| Audio | No hay | Hay grabaciones que reproducir |
| Evaluación automática | No hay | Backend Python genera análisis |
| Override del terapeuta | Marcar revisado | Cambiar score + revisado |
| Colecciones | 2 (ejercicios + ejercicios_X) | 4+ (ejercicios, ejercicios_TEM, sesiones_TEM, attempts, analysis_results_TEM) |

---

## 10. Diagrama de Relaciones Firestore

```
pacientes/{uid}
  ├── nivel_actual: 1
  └── calibracion: { f0_min, f0_max, f0_comfort, ... }

ejercicios/{ejercicioId}
  ├── terapia: "TEM"
  ├── id_paciente → pacientes/{uid}
  └── revisado: false ← TERAPEUTA MODIFICA ESTO

ejercicios_TEM/{ejercicioId}                    1:1 con ejercicios/{id}
  ├── id_ejercicio_general → ejercicios/{id}
  ├── sesion_tem_id → sesiones_TEM/{id}
  └── estimulosSecuencia: [...]

sesiones_TEM/{sessionId}                        1:1 con ejercicios_TEM/{id}
  ├── ejercicio_tem_id → ejercicios_TEM/{id}
  ├── pacienteId → pacientes/{uid}
  ├── completedStimuli: [...]
  ├── abandonedStimuli: [...]
  └── /attempts/{attemptId}                     N intentos por sesión
        ├── stimulusId → stimuli_TEM/{id}
        ├── audioUrl → Firebase Storage
        ├── analysisId → analysis_results_TEM/{id}
        ├── clinical_score
        └── pending_therapist_review: true

analysis_results_TEM/{analysisId}               1:1 con attempt
  ├── attemptId → attempts/{id}
  ├── clinical_score ← TERAPEUTA PUEDE SOBREESCRIBIR
  ├── acoustic_metrics: { ... }
  ├── per_syllable: [ ... ]
  └── warnings: [ ... ]

stimuli_TEM/{stimulusId}                        Seed data (solo lectura)
  ├── texto, syllables, onsets_ms, ...
  └── audio_url → Firebase Storage
```

---

## 11. Consideraciones Técnicas

### Audio
- Los audios están en formato **WAV 16kHz mono**
- El campo `audioUrl` en los attempts ya contiene una URL HTTPS descargable
- Usa `<audio src={audioUrl} controls />` para reproducción
- Los audios de referencia (estímulos) usan URLs `gs://` — necesitan conversión. Usa `getDownloadURL()` de Firebase Storage SDK

### Seguridad
- Solo terapeutas autenticados pueden ver datos de sus pacientes
- Verificar que el paciente pertenece al terapeuta antes de mostrar datos
- Las operaciones de override deben registrar `therapist_id`

### Performance
- Las sesiones pueden tener muchos attempts (hasta ~40 por sesión: ~10 estímulos × ~4 intentos)
- Paginar si es necesario
- Cachear estímulos (`stimuli_TEM` cambia raramente)

### Campos opcionales
- `imagen_url` en stimuli puede ser `null`
- `scoreSesion` es `null` mientras la sesión está en progreso
- `completedAt` es `null` mientras la sesión está en progreso
- `analysisId` en attempts es `null` mientras `status === "pending_analysis"`

---

## 12. Futuro (No Implementar Ahora)

Tener en cuenta en la arquitectura para no tener que refactorizar después:

1. **Creación de ejercicios TEM desde la web** — El terapeuta podrá crear estímulos personalizados (subir audio, definir sílabas, etc.)
2. **Asignación de ejercicios TEM a pacientes** — Similar a como se asignan VNEST/SR
3. **Niveles 2 y 3** — Más pasos clínicos y scoring 0/1/2
4. **Dashboard de progreso TEM** — Gráficas de evolución del paciente a lo largo del tiempo
5. **Comparación de audios** — Reproducir lado a lado el estímulo y el intento del paciente

---

## 13. Resumen Ejecutivo

| Qué | Dónde | Para qué |
|-----|-------|----------|
| Sesiones TEM | `sesiones_TEM` | Listar sesiones del paciente |
| Intentos de habla | `sesiones_TEM/{id}/attempts` | Ver cada intento, reproducir audio |
| Evaluación Python | `analysis_results_TEM` | Ver métricas, score, análisis por sílaba |
| Override terapeuta | `analysis_results_TEM` + `attempts` | Sobreescribir score, marcar revisado |
| Estímulos biblioteca | `stimuli_TEM` | Ver catálogo de frases disponibles |
| Calibración | `pacientes/{uid}.calibracion` | Ver parámetros vocales del paciente |
| Estado de revisión | `ejercicios/{id}.revisado` | Saber qué ejercicios faltan por revisar |
