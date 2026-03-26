# Sprint 2 — Especificación Completa del Módulo Python de Análisis Acústico

**Proyecto:** RehabilitIA — Módulo TEM (Terapia de Entonación Melódica)  
**Objetivo:** Implementar el backend Python que analiza las grabaciones WAV de los pacientes con afasia de Broca, determina si la producción es **clínicamente inteligible** según el protocolo MIT (Helm-Estabrooks, Nicholas & Morgan, 1989) y asigna puntuaciones clínicas discretas (0/1 para Nivel 1; 0/1/2 para Niveles 2-3). Los resultados se escriben en Firebase Firestore para que la app Flutter los consuma en tiempo real.  
**Audiencia de este documento:** Agente de IA o desarrollador encargado de implementar el módulo completo desde cero.  
**Referencia clínica:** Helm-Estabrooks, N., Nicholas, M. & Morgan, A. (1989). *Manual de la Afasia y de la Terapia de la Afasia* — Capítulo: Terapia de Entonación Melódica (TEM/MIT).  
**Versión:** 2.0 — Junio 2025

---

## Tabla de Contenido

1. [Contexto Clínico y Sistema de Puntuación del Manual](#1-contexto-clínico-y-sistema-de-puntuación-del-manual)
2. [Arquitectura General](#2-arquitectura-general)
3. [Estructura de Archivos del Módulo](#3-estructura-de-archivos-del-módulo)
4. [Firebase — Colecciones y Esquemas](#4-firebase--colecciones-y-esquemas)
5. [Firebase Storage — Rutas](#5-firebase-storage--rutas)
6. [Especificación de Audio](#6-especificación-de-audio)
7. [Endpoint POST /analyze — Análisis de Intento](#7-endpoint-post-analyze--análisis-de-intento)
8. [Endpoint POST /calibrate — Calibración Vocal](#8-endpoint-post-calibrate--calibración-vocal)
9. [Módulo analyzer/ — Pipeline de Análisis Acústico](#9-módulo-analyzer--pipeline-de-análisis-acústico)
10. [Sistema de Puntuación Clínica (según manual MIT)](#10-sistema-de-puntuación-clínica-según-manual-mit)
11. [Puntuación de Sesión y Criterios de Avance](#11-puntuación-de-sesión-y-criterios-de-avance)
12. [Cloud Function Trigger (Proxy)](#12-cloud-function-trigger-proxy)
13. [Docker y Despliegue en Cloud Run](#13-docker-y-despliegue-en-cloud-run)
14. [Integración con Flutter (cómo la app consumirá los resultados)](#14-integración-con-flutter)
15. [Flujo Completo de Datos (End-to-End)](#15-flujo-completo-de-datos-end-to-end)
16. [Variables de Entorno y Configuración](#16-variables-de-entorno-y-configuración)
17. [Tests](#17-tests)
18. [Criterios de Éxito](#18-criterios-de-éxito)
19. [Reglas No Negociables](#19-reglas-no-negociables)
20. [Apéndice A — Catálogo de Estímulos Nivel 1](#apéndice-a--catálogo-de-estímulos-nivel-1)
21. [Apéndice B — Diagrama de Secuencia](#apéndice-b--diagrama-de-secuencia)

---

## 1. Contexto Clínico y Sistema de Puntuación del Manual

La **Terapia de Entonación Melódica (TEM / MIT)** es una terapia de rehabilitación del lenguaje para pacientes con afasia de Broca, descrita por Helm-Estabrooks, Nicholas & Morgan (1989). El paciente canta frases cortas con un patrón melódico definido (tono alto/bajo por sílaba) y un ritmo marcado por un metrónomo.

### 1.1 Protocolo por Nivel

El programa MIT consta de **3 niveles** progresivos. Cada nivel tiene pasos específicos con reglas de puntuación propias.

#### Nivel 1 — 5 pasos por estímulo (implementado actualmente en la app)

| Paso | Nombre | Graba | Metrónomo | Se puntúa | Puntuación | Descripción |
|------|--------|-------|-----------|-----------|------------|-------------|
| 1 | Escucha (tarareo) | NO | SÍ | NO | — | La app reproduce el audio 2 veces. El paciente solo escucha/tararea. |
| 2 | Unísono | SÍ (hasta 4 intentos) | SÍ | SÍ | 0 ó 1 | El paciente canta junto con el audio de la app. |
| 3 | Completar (unísono con desvanecimiento) | SÍ (hasta 4 intentos) | SÍ | SÍ | 0 ó 1 | La app baja el volumen a mitad; el paciente completa. |
| 4 | Repetición inmediata | SÍ (1 intento) | SÍ | SÍ | 0 ó 1 | El paciente repite solo (sin audio de referencia, solo metrónomo). |
| 5 | Pregunta (respuesta a prueba) | SÍ (1 intento) | NO | SÍ | 0 ó 1 | Se muestra una pregunta de texto; el paciente responde hablando. |

- **Máximo por estímulo:** 4 puntos (pasos 2+3+4+5)
- Si el paciente falla 4 intentos en el mismo paso → se asigna 0 y se abandona el estímulo.

#### Nivel 2 — 4 pasos (futuro)

| Paso | Nombre | Se puntúa | Puntuación | Descripción |
|------|--------|-----------|------------|-------------|
| 1 | Introducción del estímulo | NO | — | Terapeuta presenta el estímulo. |
| 2 | Unísono con desvanecimiento | SÍ | 0 ó 1 | Cantan juntos, luego el terapeuta baja. |
| 3 | Repetición con pausa (6s) | SÍ | 0, 1 ó 2 | 2=éxito directo; 1=éxito con retroceso al paso anterior. |
| 4 | Respuesta a pregunta | SÍ | 0, 1 ó 2 | 2=éxito directo; 1=éxito con retroceso. |

- **Máximo por estímulo:** 6 puntos.
- **Retroceso (fallback):** Si el paciente falla un paso con puntuación máxima 2, se vuelve al paso anterior para reforzar. Si luego tiene éxito → obtiene 1 punto (no 2). Si falla de nuevo → 0.

#### Nivel 3 — 5 pasos (futuro)

| Paso | Nombre | Se puntúa | Puntuación | Descripción |
|------|--------|-----------|------------|-------------|
| 1 | Repetición retrasada | SÍ | 0, 1 ó 2 | Transición de entonación hacia habla normal. |
| 2 | Introducción de sprechgesang | NO | — | Se introduce la prosodia hablada (sprechgesang). |
| 3 | Sprechgesang con desvanecimiento | SÍ | 0, 1 ó 2 | El terapeuta se desvanece, paciente continúa con prosodia. |
| 4 | Repetición hablada retrasada | SÍ | 0, 1 ó 2 | El paciente repite el estímulo HABLANDO (sin entonación). |
| 5 | Respuesta a pregunta | SÍ | 0, 1 ó 2 | Respuesta hablada (habla normal, no entonada). |

- **Máximo por estímulo:** 8 puntos.

### 1.2 Criterio de Evaluación: INTELIGIBILIDAD

> **Principio fundamental del manual (Helm-Estabrooks et al.):** La evaluación se basa en si el paciente produce una **versión inteligible** de la respuesta esperada. NO se mide precisión acústica pura (afinación perfecta), sino si la producción del paciente es reconocible como el estímulo objetivo.

Esto significa que el módulo Python debe:
1. Usar el análisis acústico (pitch, ritmo, voicing) como **proxy computacional** para determinar inteligibilidad
2. Producir una **puntuación clínica discreta** (0/1 para Nivel 1; 0/1/2 para Niveles 2-3), NO un score continuo 0-100
3. Priorizar **presencia de voz** (voiced_ratio) y **aproximación rítmica** sobre precisión tonal exacta
4. Mantener umbrales **permisivos** — estos pacientes tienen déficit severo de producción del habla

### 1.3 Regla de Intentos Máximos

- **Pasos 2 y 3 (Nivel 1):** hasta 4 intentos. Si todos fallan → 0 puntos, abandonar estímulo.
- **Pasos 4 y 5 (Nivel 1):** 1 intento. Si falla → 0 puntos.
- **Niveles 2-3:** hasta 4 intentos en pasos con retroceso. Si falla → retroceso al paso anterior → si falla de nuevo → 0.

**El módulo Python debe evaluar las grabaciones de los pasos 2, 3, 4 y 5** comparando el audio del paciente contra los parámetros acústicos de referencia del estímulo (template de F0, timing de sílabas) y determinando si la producción es inteligible.

---

## 2. Arquitectura General

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER APP                                     │
│                                                                              │
│  1. Paciente graba audio (WAV 16kHz mono 16-bit)                            │
│  2. RecordingService sube WAV a Firebase Storage                            │
│  3. RecordingService crea doc en Firestore:                                 │
│       sesiones_TEM/{sessionId}/attempts/{attemptId}                         │
│       status: "pending_analysis"                                            │
│  4. Flutter escucha cambios en attempt.status                               │
│       (StreamBuilder/listener → cuando status == "analyzed")                │
└─────────────┬───────────────────────────────────────────┬───────────────────┘
              │ onCreate (attempt doc)                    │ onFinalize (storage)
              ▼                                           ▼
┌─────────────────────────────────┐   ┌─────────────────────────────────────┐
│   CLOUD FUNCTION (trigger)      │   │   CLOUD FUNCTION (trigger)          │
│   Firestore onCreate             │   │   Storage onFinalize                │
│   → POST /analyze a Cloud Run   │   │   (metadata.type == "calibration")  │
│                                  │   │   → POST /calibrate a Cloud Run    │
└─────────────┬───────────────────┘   └─────────────┬───────────────────────┘
              │                                      │
              ▼                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                   CLOUD RUN — backend_tem (FastAPI)                          │
│                                                                              │
│  POST /analyze                                                               │
│    1. Descarga WAV de Firebase Storage                                       │
│    2. Descarga doc del estímulo de Firestore (template de referencia)        │
│    3. Ejecuta pipeline: pitch_analyzer → rhythm_analyzer → scorer            │
│    4. Escribe analysis_results_TEM/{analysisId} en Firestore                │
│    5. Actualiza attempt.status → "analyzed"                                  │
│                                                                              │
│  POST /calibrate                                                             │
│    1. Descarga WAV de vocal sostenida de Storage                            │
│    2. Mide F0 frame a frame con Parselmouth                                 │
│    3. Calcula f0_min, f0_max, f0_comfort                                    │
│    4. Escribe pacientes/{pacienteId}/calibracion en Firestore              │
│                                                                              │
│  GET /health                                                                 │
│    → { "status": "ok", "version": "..." }                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

**¿Por qué Cloud Run y no Cloud Functions directamente?**  
Parselmouth (wrapper nativo de Praat C++) requiere dependencias del sistema (`libstdc++`, binarios precompilados) que no se instalan en el sandbox de Cloud Functions. Cloud Run usa Docker → control total de dependencias.

---

## 3. Estructura de Archivos del Módulo

```
backend_tem/
├── main.py                       # FastAPI app: endpoints /analyze, /calibrate, /health
├── firebase_client.py            # Inicialización firebase-admin, helpers para Firestore + Storage
├── models.py                     # Pydantic/dataclass schemas para request/response
├── config.py                     # Variables de entorno y constantes
├── analyzer/
│   ├── __init__.py
│   ├── pitch_analyzer.py         # Análisis de F0 por sílaba con Parselmouth
│   ├── rhythm_analyzer.py        # Onset detection y timing con librosa
│   ├── scorer.py                 # Determina inteligibilidad → puntuación clínica discreta (0/1 o 0/1/2)
│   └── syllable_aligner.py       # Alinea audio grabado con template de onsets del estímulo
├── trigger/
│   └── main.py                   # Cloud Function (Gen2) — proxy Firestore/Storage → Cloud Run
├── tests/
│   ├── test_pitch_analyzer.py
│   ├── test_rhythm_analyzer.py
│   ├── test_scorer.py
│   ├── test_syllable_aligner.py
│   ├── test_endpoints.py
│   └── fixtures/                 # WAVs de prueba (voces simuladas)
│       ├── good_attempt.wav
│       ├── poor_attempt.wav
│       └── calibration_vocal.wav
├── requirements.txt
├── Dockerfile
├── .dockerignore
└── README.md
```

---

## 4. Firebase — Colecciones y Esquemas

### 4.1 Colección de entrada: `sesiones_TEM/{sessionId}/attempts/{attemptId}`

**Quién escribe:** Flutter (`RecordingService`)  
**Quién lee:** Backend Python (para obtener la URL del audio y el estímulo de referencia)  
**Trigger:** Cloud Function `onCreate` en esta colección

```jsonc
{
  "attemptId": "ATT_SES_1719000000000_ST_TEM_N1_001_s2_a1",
  "stimulusId": "ST_TEM_N1_001",        // ID del estímulo para buscar el template
  "paso": 2,                             // int 1-5 (paso del protocolo)
  "stepName": "unisono",                 // "escucha" | "unisono" | "completion" | "repeticion" | "pregunta"
  "attemptNumber": 1,                    // int 1-4
  "status": "pending_analysis",          // "pending_analysis" → "analyzed" (actualizado por backend)
  "audioUrl": "https://firebasestorage.googleapis.com/...",  // URL HTTPS de descarga
  "storagePath": "attempts/UID123/SES_1719000000000/ATT_..._s2_a1.wav",
  "pacienteId": "UID123",
  "pending_therapist_review": true,
  "createdAt": "2025-06-01T12:00:00Z"   // Firestore Timestamp (serverTimestamp)
}
```

**Formato del attemptId:**  
`ATT_{sessionId}_{stimulusId}_s{paso}_a{attemptNumber}`

**Formato del sessionId:**  
`SES_{millisecondsSinceEpoch}`

> **IMPORTANTE:** El Paso 1 (escucha) NO genera grabación ni attempt doc. Solo los pasos 2, 3, 4 y 5 generan attempts.

---

### 4.2 Colección de referencia: `stimuli_TEM/{stimulusId}`

**Quién escribe:** Sistema (seed manual o script `align_stimuli.py`)  
**Quién lee:** Backend Python (para obtener el template de referencia) + Flutter (para UI)

```jsonc
{
  "stimulusId": "ST_TEM_N1_001",
  "texto": "mamá",
  "syllables": ["ma", "má"],            // Array de sílabas
  "onsets_ms": [0, 500],                 // Inicio de cada sílaba en ms (desde inicio del audio)
  "durations_ms": [450, 450],            // Duración de cada sílaba en ms
  "audio_duration_ms": 950,              // Duración total del audio de referencia
  "audio_url": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N1_001_v1.wav",
  "f0_template_hz": [180.0, 175.0],     // F0 esperado por sílaba (Hz) — template melódico
  "nivel_clinico": 1,                    // int: 1, 2 o 3
  "patron_tonal": "LH",                 // Patrón tonal: "LH", "HL", "LHL", etc.
  "num_silabas": 2,                      // int: número de sílabas
  "categoria": "familia",
  "pregunta_texto": "¿Quién te cuida?", // Pregunta para Paso 5
  "imagen_url": "gs://apphasia-7a930.firebasestorage.app/stimuli/images/ST_TEM_N1_001.jpg",
  "fase": "union_ritmica",
  "num_completions": 0,                  // Contador de completaciones exitosas
  "fallos_consecutivos": 0               // Contador de fallos consecutivos
}
```

**Invariante CRÍTICO:**  
```
len(syllables) == len(onsets_ms) == len(durations_ms) == len(f0_template_hz)
```

**Campos que el backend Python necesita del estímulo:**
- `syllables` — para saber cuántas sílabas analizar
- `onsets_ms` — tiempos de inicio esperados por sílaba
- `durations_ms` — duraciones esperadas por sílaba
- `audio_duration_ms` — duración total esperada
- `f0_template_hz` — frecuencia fundamental esperada por sílaba (para pitch_accuracy)
- `patron_tonal` — patrón tonal del estímulo (para validación)

---

### 4.3 Colección de salida: `analysis_results_TEM/{analysisId}`

**Quién escribe:** Backend Python (Cloud Run) ← **ESTA COLECCIÓN LA CREA EL BACKEND**  
**Quién lee:** Flutter (listener en tiempo real)

```jsonc
{
  "analysisId": "AN_ATT_SES_1719000000000_ST_TEM_N1_001_s2_a1",
  "attemptId": "ATT_SES_1719000000000_ST_TEM_N1_001_s2_a1",
  "sessionId": "SES_1719000000000",
  "stimulusId": "ST_TEM_N1_001",
  "pacienteId": "UID123",
  "paso": 2,
  "stepName": "unisono",
  "attemptNumber": 1,
  "nivel": 1,                          // Nivel clínico (1, 2 o 3)

  // ═══════════════════════════════════════════════════════════════
  // PUNTUACIÓN CLÍNICA (según manual MIT — Helm-Estabrooks et al.)
  // ═══════════════════════════════════════════════════════════════

  // Puntuación clínica discreta:
  //   Nivel 1: 0 (no inteligible) o 1 (inteligible)
  //   Niveles 2-3: 0, 1 (con retroceso), o 2 (éxito directo)
  "clinical_score": 1,

  // Decisión de inteligibilidad del sistema
  "intelligibility_decision": {
    "is_intelligible": true,            // ¿La producción fue inteligible?
    "rationale": "voiced_ratio=0.85, rhythm_ok=true, pitch_approx=true",
    "needs_fallback": false             // true si se necesita retroceso (Niveles 2-3)
  },

  // ═══════════════════════════════════════════════════════════════
  // MÉTRICAS ACÚSTICAS INTERNAS (proxy computacional, NO son el score)
  // Se almacenan para diagnóstico, debug y futuro ajuste de umbrales.
  // ═══════════════════════════════════════════════════════════════

  "acoustic_metrics": {
    "voiced_ratio_global": 0.85,       // % de tiempo con voz presente (0.0–1.0)
    "pitch_proximity": 0.72,           // Proximidad tonal al template (0.0–1.0)
    "rhythm_regularity": 0.78,         // Regularidad rítmica (0.0–1.0)
    "legato": 0.65                     // Continuidad de F0 entre sílabas (0.0–1.0)
  },

  // Análisis detallado por sílaba (para diagnóstico)
  "per_syllable": [
    {
      "syllable": "ma",
      "syllable_index": 0,
      "f0_measured_hz": 173.0,
      "f0_template_hz": 180.0,
      "f0_error_cents": -69.2,
      "voiced_ratio": 0.91,
      "onset_detected_ms": 12,
      "onset_expected_ms": 0,
      "timing_error_ms": 12,
      "duration_measured_ms": 430,
      "duration_expected_ms": 450
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

  // Advertencias clínicas (array de strings)
  "warnings": [
    // Ejemplos posibles:
    // "low_voicing_syllable_0"        → sílaba 0 tiene voiced_ratio < 0.3
    // "timing_late_onset_1"           → sílaba 1 empezó >300ms tarde
    // "pitch_out_of_range_syllable_0" → F0 fuera del rango de calibración del paciente
    // "short_audio"                   → la grabación dura menos del 50% de audio_duration_ms
    // "no_voice_detected"             → voiced_ratio global < 0.1
  ],

  // Confianza del análisis (0.0–1.0)
  "confidence": 0.83,

  // Metadata
  "analysis_version": "praat_cloud_run_v2.0",
  "analyzed_at": "2025-06-01T12:00:05Z",
  "processing_time_ms": 1200
}
```

**Formato del analysisId:**  
`AN_{attemptId}`  
(Relación 1:1 con el attempt)

---

### 4.4 Documento de calibración: `pacientes/{pacienteId}/calibracion`

**Quién escribe:** Backend Python (Fase 1: métricas vocales) + Flutter (Fase 2: offset_ms)  
**Quién lee:** Backend Python (para ajustar análisis) + Flutter (para RhythmEngine)

> **NOTA:** En Sprint 2 el backend solo escribe los campos de Fase 1. La Fase 2 (offset_ms) se implementa en Sprint 3 desde Flutter.

```jsonc
{
  "f0_min": 120,                    // Percentil p10 de F0 voiced (Hz)
  "f0_max": 210,                    // Percentil p90 de F0 voiced (Hz)
  "f0_comfort": 155,                // Mediana p50 de F0 voiced (Hz)
  "avg_syllable_duration_ms": 720,  // Duración promedio de sílaba (ms)
  "offset_ms": 0,                   // Sprint 3: latencia hardware (Fase 2, Dart local)
  "last_calibrated_at": "2025-06-01T12:00:00Z",  // Firestore Timestamp
  "calibration_version": "hybrid_v1.0"
}
```

**Valores por defecto (antes de calibración real):**
```jsonc
{
  "f0_min": 100,
  "f0_max": 300,
  "f0_comfort": 180,
  "avg_syllable_duration_ms": 450,
  "offset_ms": 0,
  "last_calibrated_at": null
}
```

---

### 4.5 Colección de sesiones: `sesiones_TEM/{sessionId}`

**Quién escribe:** Flutter (`SessionManager`) + Backend Python (campos de puntuación)  
**Quién lee:** Backend Python (para contexto adicional), Flutter (para mostrar progreso)

```jsonc
{
  "sessionId": "SES_1719000000000",
  "ejercicio_tem_id": "EABC12",
  "pacienteId": "UID123",
  "nivel": 1,
  "estimulosSecuencia": ["ST_TEM_N1_006", "ST_TEM_N1_001", ...],  // 10 estímulos
  "estimuloActualIndex": 0,
  "startedAt": "2025-06-01T12:00:00Z",
  "completedAt": null,
  "status": "in_progress",               // "in_progress" | "completed"
  "completedStimuli": [],
  "abandonedStimuli": [],

  // ═══════════════════════════════════════════════════════════
  // PUNTUACIÓN DE SESIÓN (calculada al completarse la sesión)
  // Según manual MIT: sum(obtenidos) / sum(posibles) × 100
  // ═══════════════════════════════════════════════════════════

  // Puntos obtenidos por cada estímulo procesado (array paralelo a estimulosSecuencia)
  "scores_per_stimulus": [
    // Ejemplo para Nivel 1: cada estímulo tiene max 4 pts (pasos 2-5)
    {"stimulusId": "ST_TEM_N1_006", "obtained": 3, "possible": 4, "abandoned": false},
    {"stimulusId": "ST_TEM_N1_001", "obtained": 4, "possible": 4, "abandoned": false},
    // Si se abandona un estímulo:
    {"stimulusId": "ST_TEM_N1_003", "obtained": 0, "possible": 4, "abandoned": true}
  ],

  // Porcentaje de la sesión = sum(obtained) / sum(possible) × 100
  "session_score_pct": null,             // null hasta que se complete, luego ej: 82.5

  // Total puntos obtenidos y posibles
  "total_obtained": null,
  "total_possible": null
}
```

---

### 4.6 Actualización del attempt (acción del backend DESPUÉS del análisis)

El backend debe actualizar el documento del attempt con los siguientes campos:

```python
# En sesiones_TEM/{sessionId}/attempts/{attemptId}
attempt_ref.update({
    "status": "analyzed",                    # OBLIGATORIO: cambiar de "pending_analysis" a "analyzed"
    "analysisId": analysis_id,               # Referencia cruzada al resultado
    "clinical_score": clinical_score,        # int: 0 o 1 (Nivel 1) / 0, 1 o 2 (Niveles 2-3)
    "is_intelligible": is_intelligible,      # bool: ¿producción inteligible?
    "analyzed_at": firestore.SERVER_TIMESTAMP
})
```

---

## 5. Firebase Storage — Rutas

```
gs://apphasia-7a930.firebasestorage.app/
│
├── stimuli/
│   ├── audio/                         # Audio de referencia de cada estímulo
│   │   └── ST_TEM_N1_001_v1.wav       # Formato: {stimulusId}_v{version}.wav
│   └── images/                        # Imágenes semánticas
│       └── ST_TEM_N1_001.jpg
│
├── attempts/                          # Grabaciones del paciente
│   └── {pacienteId}/
│       └── {sessionId}/
│           └── {attemptId}.wav        # WAV 16kHz mono 16-bit
│
├── calibraciones/                     # Audio de calibración vocal
│   └── {pacienteId}/
│       └── vocal_{timestamp}.wav      # Vocal sostenida "aaaaa" (~3s)
│
└── tem/
    └── audio/                         # (legacy: algunos audios de referencia)
```

**El backend necesita descargar:**
1. `attempts/{pacienteId}/{sessionId}/{attemptId}.wav` — para análisis de intento
2. `calibraciones/{pacienteId}/vocal_{timestamp}.wav` — para calibración vocal
3. Opcionalmente: `stimuli/audio/{stimulusId}_v{version}.wav` — si se necesita comparación directa

**Cómo descargar:** Usar `firebase_admin.storage.bucket().blob(path).download_to_filename()` o `.download_as_bytes()`. El campo `storagePath` del attempt doc contiene la ruta relativa exacta dentro del bucket.

---

## 6. Especificación de Audio

**Formato OBLIGATORIO de todas las grabaciones TEM:**

| Parámetro | Valor |
|-----------|-------|
| Formato | WAV (PCM) |
| Bits por muestra | 16-bit (signed integer) |
| Canales | 1 (mono) |
| Sample rate | 16000 Hz |
| Encoder | `AudioEncoder.wav` (Flutter `record` package) |
| Content-Type | `audio/wav` |

**Validación en el backend:**  
Al recibir un archivo, verificar que cumple estas especificaciones. Si no las cumple, marcar el attempt como `"status": "error"` con un mensaje descriptivo en lugar de intentar procesarlo.

```python
import soundfile as sf

data, sr = sf.read(wav_path)
assert sr == 16000, f"Sample rate esperado 16000, recibido {sr}"
assert len(data.shape) == 1, f"Se esperaba mono, recibida forma {data.shape}"
```

---

## 7. Endpoint POST /analyze — Análisis de Intento

### Request

```http
POST /analyze
Content-Type: application/json

{
  "attemptId": "ATT_SES_1719000000000_ST_TEM_N1_001_s2_a1",
  "sessionId": "SES_1719000000000",
  "pacienteId": "UID123"
}
```

### Lógica del endpoint (pseudocódigo)

```python
@app.post("/analyze")
async def analyze(request: AnalyzeRequest):
    # 1. Leer attempt doc de Firestore
    attempt_doc = read_attempt(request.session_id, request.attempt_id)
    
    # 2. Validar que status sea "pending_analysis"
    if attempt_doc["status"] != "pending_analysis":
        raise HTTPException(409, "Attempt ya fue analizado o está en error")
    
    # 3. Leer estímulo de referencia de Firestore
    stimulus_doc = read_stimulus(attempt_doc["stimulusId"])
    
    # 4. Leer calibración del paciente (si existe)
    calibration = read_calibration(request.paciente_id)  # puede ser None
    
    # 5. Descargar WAV de Firebase Storage
    wav_bytes = download_wav(attempt_doc["storagePath"])
    
    # 6. Validar formato de audio
    validate_wav_format(wav_bytes)
    
    # 7. Ejecutar pipeline de análisis
    #    a) syllable_aligner: segmentar la grabación en ventanas por sílaba
    #    b) pitch_analyzer: medir F0 por sílaba con Parselmouth
    #    c) rhythm_analyzer: detectar onsets y medir timing con librosa
    #    d) scorer: determinar inteligibilidad → puntuación clínica discreta (0/1 o 0/1/2)
    alignment = syllable_aligner.align(wav_bytes, stimulus_doc)
    pitch_results = pitch_analyzer.analyze(wav_bytes, alignment, stimulus_doc, calibration)
    rhythm_results = rhythm_analyzer.analyze(wav_bytes, alignment, stimulus_doc)
    
    paso = attempt_doc.get("paso", 2)
    nivel = stimulus_doc.get("nivel_clinico", 1)
    scores = scorer.compute(pitch_results, rhythm_results, stimulus_doc, paso, nivel)
    
    # 8. Construir resultado
    analysis_result = build_analysis_result(
        attempt_doc, stimulus_doc, pitch_results, rhythm_results, scores
    )
    
    # 9. Escribir analysis_results_TEM/{analysisId} en Firestore
    write_analysis_result(analysis_result)
    
    # 10. Actualizar attempt.status → "analyzed"
    update_attempt_status(request.session_id, request.attempt_id, analysis_result)
    
    return {"status": "ok", "analysisId": analysis_result["analysisId"]}
```

### Manejo de errores

| Error | Acción |
|-------|--------|
| WAV no encontrado en Storage | Actualizar attempt.status → "error", escribir attempt.errorMessage |
| WAV con formato inválido | Actualizar attempt.status → "error", escribir attempt.errorMessage |
| No se detecta voz (voiced_ratio global < 0.1) | Escribir resultado con clinical_score = 0, warning "no_voice_detected" |
| Audio muy corto (< 50% de audio_duration_ms) | Escribir resultado con warning "short_audio", clinical_score = 0 |
| Estímulo no encontrado en Firestore | Log error, actualizar attempt.status → "error" |
| Excepción no capturada | Log error, actualizar attempt.status → "error" con stack trace |

**IMPORTANTE:** NUNCA dejar un attempt en `"pending_analysis"` indefinidamente. Todo camino de ejecución debe terminar actualizando el status a `"analyzed"` o `"error"`.

---

## 8. Endpoint POST /calibrate — Calibración Vocal

### Request

```http
POST /calibrate
Content-Type: application/json

{
  "storagePath": "calibraciones/UID123/vocal_1719000000000.wav",
  "pacienteId": "UID123"
}
```

### Lógica del endpoint

```python
@app.post("/calibrate")
async def calibrate(request: CalibrateRequest):
    # 1. Descargar WAV de vocal sostenida de Storage
    wav_bytes = download_wav(request.storage_path)
    
    # 2. Validar formato
    validate_wav_format(wav_bytes)
    
    # 3. Usar Parselmouth para medir F0 frame a frame
    snd = parselmouth.Sound(wav_path)
    pitch = snd.to_pitch(
        time_step=0.01,          # 10ms por frame
        pitch_floor=50.0,        # Pacientes con afasia pueden tener F0 muy bajo
        pitch_ceiling=500.0
    )
    f0_values = pitch.selected_array['frequency']
    voiced_f0 = f0_values[f0_values > 0]  # Solo frames con voz
    
    # 4. Calcular métricas
    if len(voiced_f0) < 10:
        # Voz insuficiente — no se puede calibrar
        return {"status": "error", "message": "Voz insuficiente detectada"}
    
    f0_min = float(np.percentile(voiced_f0, 10))
    f0_max = float(np.percentile(voiced_f0, 90))
    f0_comfort = float(np.median(voiced_f0))
    
    # 5. Medir duración promedio de sílaba (opcional, si el paciente repite "pa-pa-pa")
    # Usar librosa onset detection
    avg_syllable_duration_ms = measure_avg_syllable_duration(wav_bytes)
    
    # 6. Escribir en Firestore: pacientes/{pacienteId}/calibracion
    calibration_data = {
        "f0_min": f0_min,
        "f0_max": f0_max,
        "f0_comfort": f0_comfort,
        "avg_syllable_duration_ms": avg_syllable_duration_ms,
        "offset_ms": 0,  # Se completa en Sprint 3 (Fase 2, Flutter local)
        "last_calibrated_at": firestore.SERVER_TIMESTAMP,
        "calibration_version": "hybrid_v1.0"
    }
    write_calibration(request.paciente_id, calibration_data)
    
    return {"status": "ok", "calibration": calibration_data}
```

**¿Por qué Parselmouth y no FFT manual?**  
- Los pacientes con afasia de Broca frecuentemente tienen voz débil, temblorosa o entrecortada
- Parselmouth/Praat usa algoritmos YIN + autocorrelación robustos para F0 en señal débil
- Librerías genéricas de pitch (tarso, pitch_detector_dart, FFT manual) fallan con señales no periódicas

---

## 9. Módulo analyzer/ — Pipeline de Análisis Acústico

### 9.1 `syllable_aligner.py` — Segmentación temporal

**Propósito:** Mapear cada sílaba del template a una ventana temporal en la grabación del paciente.

**Estrategia:**  
El estímulo tiene `onsets_ms` y `durations_ms` definidos. El paciente puede cantar más lento, más rápido, o con un offset temporal. El aligner debe:

1. **Detectar onsets en la grabación** del paciente con `librosa.onset_detect()`
2. **Alinear** los onsets detectados con los onsets esperados del template usando DTW (Dynamic Time Warping) simplificado o correspondencia por orden
3. **Producir** una lista de ventanas temporales `[(start_ms, end_ms), ...]` — una por sílaba

```python
import librosa
import numpy as np

def align(wav_data: np.ndarray, sr: int, stimulus: dict) -> list[dict]:
    """
    Alinea la grabación del paciente con el template del estímulo.
    
    Args:
        wav_data: Array de samples (float32, mono)
        sr: Sample rate (16000)
        stimulus: Documento del estímulo con onsets_ms, durations_ms, syllables
    
    Returns:
        Lista de dicts con la ventana temporal de cada sílaba:
        [
            {
                "syllable": "ma",
                "syllable_index": 0,
                "window_start_ms": 0,
                "window_end_ms": 480,
                "onset_detected_ms": 12
            },
            ...
        ]
    """
    expected_onsets = stimulus["onsets_ms"]
    expected_durations = stimulus["durations_ms"]
    syllables = stimulus["syllables"]
    
    # 1. Detectar onsets con librosa
    onset_frames = librosa.onset_detect(
        y=wav_data, sr=sr,
        hop_length=160,        # 10ms para 16kHz
        backtrack=True,
        units='frames'
    )
    onset_times_ms = librosa.frames_to_time(
        onset_frames, sr=sr, hop_length=160
    ) * 1000  # convertir a ms
    
    # 2. Correspondencia: asignar el onset detectado más cercano a cada onset esperado
    aligned_windows = []
    audio_duration_ms = len(wav_data) / sr * 1000
    
    for i, (exp_onset, exp_dur, syl) in enumerate(
        zip(expected_onsets, expected_durations, syllables)
    ):
        # Buscar el onset detectado más cercano al esperado
        if len(onset_times_ms) > 0:
            distances = np.abs(onset_times_ms - exp_onset)
            closest_idx = np.argmin(distances)
            detected_onset = float(onset_times_ms[closest_idx])
        else:
            detected_onset = float(exp_onset)  # fallback al template
        
        # Definir ventana: desde el onset detectado hasta el siguiente onset o fin
        if i < len(expected_onsets) - 1:
            window_end = min(
                detected_onset + exp_dur * 1.5,  # margen de 50%
                audio_duration_ms
            )
        else:
            window_end = audio_duration_ms  # última sílaba: hasta el final
        
        aligned_windows.append({
            "syllable": syl,
            "syllable_index": i,
            "window_start_ms": detected_onset,
            "window_end_ms": window_end,
            "onset_detected_ms": detected_onset
        })
    
    return aligned_windows
```

**Caso edge — paciente no emite ningún sonido:**  
Si no se detectan onsets, usar los `onsets_ms` del template como fallback. El scorer asignará score bajo por `voiced_ratio ≈ 0`.

---

### 9.2 `pitch_analyzer.py` — Análisis de F0 por sílaba

**Propósito:** Medir la frecuencia fundamental (F0) en cada ventana de sílaba y compararla con el template.

```python
import parselmouth
import numpy as np

def analyze(
    wav_data: np.ndarray,
    sr: int,
    alignment: list[dict],
    stimulus: dict,
    calibration: dict | None = None
) -> list[dict]:
    """
    Analiza F0 por sílaba usando Parselmouth/Praat.
    
    Returns:
        Lista de dicts por sílaba con métricas de pitch:
        [
            {
                "syllable_index": 0,
                "f0_measured_hz": 173.0,
                "f0_template_hz": 180.0,
                "f0_error_cents": -69.2,
                "voiced_ratio": 0.91,
                "f0_contour": [175.0, 178.0, 172.0, ...]  # F0 frame a frame (para debug)
            },
            ...
        ]
    """
    # Crear objeto Sound de Parselmouth
    snd = parselmouth.Sound(wav_data, sampling_frequency=sr)
    
    # Configurar pitch extraction con parámetros clínicos
    # pitch_floor bajo para voces débiles/afónicas
    pitch_floor = 50.0
    pitch_ceiling = 500.0
    
    # Si hay calibración, usar el rango vocal del paciente con margen
    if calibration and calibration.get("f0_min"):
        pitch_floor = max(40.0, calibration["f0_min"] * 0.7)
        pitch_ceiling = min(600.0, calibration["f0_max"] * 1.5)
    
    pitch = snd.to_pitch_ac(
        time_step=0.01,          # 10ms por frame
        pitch_floor=pitch_floor,
        pitch_ceiling=pitch_ceiling
    )
    
    f0_values = pitch.selected_array['frequency']
    time_step_sec = pitch.time_step
    t0 = pitch.t1  # tiempo del primer frame
    
    f0_template = stimulus["f0_template_hz"]
    syllable_results = []
    
    for window in alignment:
        i = window["syllable_index"]
        start_s = window["window_start_ms"] / 1000.0
        end_s = window["window_end_ms"] / 1000.0
        
        # Extraer frames de F0 en la ventana de esta sílaba
        frame_start = max(0, int((start_s - t0) / time_step_sec))
        frame_end = min(len(f0_values), int((end_s - t0) / time_step_sec))
        
        syllable_f0 = f0_values[frame_start:frame_end]
        voiced_frames = syllable_f0[syllable_f0 > 0]
        total_frames = max(1, len(syllable_f0))
        voiced_ratio = len(voiced_frames) / total_frames
        
        # F0 medido: mediana de frames voiced (robusto ante outliers)
        if len(voiced_frames) > 0:
            f0_measured = float(np.median(voiced_frames))
        else:
            f0_measured = 0.0
        
        # F0 template
        f0_expected = f0_template[i] if i < len(f0_template) else 0.0
        
        # Error en cents (escala logarítmica musical)
        # 100 cents = 1 semitono; ±50 cents es "afinado"
        if f0_measured > 0 and f0_expected > 0:
            f0_error_cents = 1200 * np.log2(f0_measured / f0_expected)
        else:
            f0_error_cents = None  # no se puede calcular
        
        syllable_results.append({
            "syllable_index": i,
            "f0_measured_hz": round(f0_measured, 1),
            "f0_template_hz": f0_expected,
            "f0_error_cents": round(f0_error_cents, 1) if f0_error_cents is not None else None,
            "voiced_ratio": round(voiced_ratio, 3),
            "f0_contour": [round(float(v), 1) for v in syllable_f0.tolist()]
        })
    
    return syllable_results
```

**Parámetros de Parselmouth para voces débiles:**
- `pitch_floor=50.0` Hz — por debajo de la voz normal para capturar voces patológicas
- `pitch_ceiling=500.0` Hz — margen alto para voces femeninas o sobretonos
- `time_step=0.01` — resolución de 10ms (suficiente para sílabas de >300ms)
- Usar `to_pitch_ac()` (autocorrelación) — más robusto que `to_pitch()` para voces no periódicas

---

### 9.3 `rhythm_analyzer.py` — Análisis de timing y ritmo

**Propósito:** Medir la regularidad rítmica del paciente comparando tiempos de onset detectados vs. esperados.

```python
import librosa
import numpy as np

def analyze(
    wav_data: np.ndarray,
    sr: int,
    alignment: list[dict],
    stimulus: dict
) -> dict:
    """
    Analiza el timing y la regularidad rítmica.
    
    Returns:
        {
            "onset_times_ms": [12, 510, ...],       # Onsets detectados
            "ioi_measured_ms": [498, ...],           # Inter-onset intervals medidos
            "ioi_expected_ms": [500, ...],           # IOI esperados del template
            "ioi_cv": 0.15,                          # Coeficiente de variación del IOI
            "global_voicing_ratio": 0.85,            # Voiced ratio de toda la grabación
            "total_duration_ms": 980,                # Duración total donde hay voz
            "per_syllable_timing": [                  # Timing por sílaba
                {
                    "syllable_index": 0,
                    "onset_detected_ms": 12,
                    "onset_expected_ms": 0,
                    "timing_error_ms": 12,
                    "duration_measured_ms": 430,
                    "duration_expected_ms": 450
                },
                ...
            ]
        }
    """
    # Calcular envelope de energía (RMS)
    rms = librosa.feature.rms(y=wav_data, frame_length=320, hop_length=160)[0]
    
    # Detectar onsets
    onset_frames = librosa.onset_detect(
        y=wav_data, sr=sr,
        hop_length=160,
        backtrack=True,
        units='frames'
    )
    onset_times_ms = (librosa.frames_to_time(onset_frames, sr=sr, hop_length=160) * 1000).tolist()
    
    # IOI (Inter-Onset Intervals)
    expected_onsets = stimulus["onsets_ms"]
    expected_durations = stimulus["durations_ms"]
    
    # IOI medidos
    ioi_measured = [onset_times_ms[i+1] - onset_times_ms[i] 
                    for i in range(len(onset_times_ms) - 1)] if len(onset_times_ms) > 1 else []
    
    # IOI esperados del template
    ioi_expected = [expected_onsets[i+1] - expected_onsets[i] 
                    for i in range(len(expected_onsets) - 1)] if len(expected_onsets) > 1 else []
    
    # Coeficiente de variación del IOI (medida de regularidad rítmica)
    # CV bajo = ritmo regular; CV alto = ritmo irregular
    if len(ioi_measured) > 0:
        ioi_cv = float(np.std(ioi_measured) / max(np.mean(ioi_measured), 1))
    else:
        ioi_cv = 1.0  # peor caso
    
    # Voiced ratio global
    # Usar Parselmouth o simplemente contar energía
    voiced_frames = np.sum(rms > np.max(rms) * 0.05)
    global_voicing_ratio = voiced_frames / max(len(rms), 1)
    
    # Timing por sílaba
    per_syllable_timing = []
    for window in alignment:
        i = window["syllable_index"]
        onset_detected = window["onset_detected_ms"]
        onset_expected = expected_onsets[i] if i < len(expected_onsets) else 0
        dur_expected = expected_durations[i] if i < len(expected_durations) else 0
        dur_measured = window["window_end_ms"] - window["window_start_ms"]
        
        per_syllable_timing.append({
            "syllable_index": i,
            "onset_detected_ms": round(onset_detected),
            "onset_expected_ms": onset_expected,
            "timing_error_ms": round(abs(onset_detected - onset_expected)),
            "duration_measured_ms": round(dur_measured),
            "duration_expected_ms": dur_expected
        })
    
    return {
        "onset_times_ms": [round(t) for t in onset_times_ms],
        "ioi_measured_ms": [round(t) for t in ioi_measured],
        "ioi_expected_ms": ioi_expected,
        "ioi_cv": round(ioi_cv, 4),
        "global_voicing_ratio": round(float(global_voicing_ratio), 3),
        "total_duration_ms": round(len(wav_data) / sr * 1000),
        "per_syllable_timing": per_syllable_timing
    }
```

---

### 9.4 `scorer.py` — Sistema de puntuación clínica

**Propósito:** Transformar las métricas acústicas crudas en una **decisión de inteligibilidad** y una **puntuación clínica discreta** (0/1 para Nivel 1; 0/1/2 para Niveles 2-3) según el manual MIT de Helm-Estabrooks.

> **Principio clave:** El análisis acústico (pitch, ritmo, voicing) es un **proxy computacional** para la decisión de inteligibilidad que en clínica hace el terapeuta humano. NO se busca precisión acústica perfecta; se busca determinar si la producción del paciente es **reconocible como el estímulo objetivo**.

```python
import numpy as np

# ══════════════════════════════════════════════════════════════════
# UMBRALES DE INTELIGIBILIDAD
# Estos umbrales determinan si la producción del paciente es "inteligible"
# Son PERMISIVOS — los pacientes con afasia de Broca tienen déficit severo.
# Los pesos reflejan prioridad clínica: voz > ritmo > tono
# ══════════════════════════════════════════════════════════════════

# Umbral mínimo de voiced_ratio global para considerar que hay voz
MIN_VOICED_RATIO = 0.30

# Umbral de voiced_ratio por sílaba — sílabas con menos de esto se consideran "ausentes"
MIN_SYLLABLE_VOICED = 0.20

# Proporción mínima de sílabas que deben tener voz para considerar inteligible
MIN_SYLLABLE_PRESENCE_RATIO = 0.50  # Al menos la mitad de las sílabas deben tener voz

# Error máximo de timing (ms) para considerar ritmo aceptable por sílaba
MAX_TIMING_ERROR_MS = 400  # Permisivo — pacientes son lentos

# Error máximo en cents para considerar aproximación tonal aceptable
MAX_PITCH_ERROR_CENTS = 300  # ~3 semitonos — muy permisivo

# Peso de cada componente en la decisión de inteligibilidad
# voiced_ratio es el más importante (el paciente debe emitir voz)
# pitch es el menos importante (la afinación exacta no es el criterio)
INTELLIGIBILITY_WEIGHTS = {
    "voice_presence": 0.45,      # 45% — ¿el paciente emitió voz? (lo más importante)
    "rhythm_approximation": 0.30, # 30% — ¿siguió el ritmo aproximadamente?
    "pitch_approximation": 0.25   # 25% — ¿se aproximó al contorno tonal?
}

# Umbral de inteligibilidad: score interno ≥ este valor → inteligible
INTELLIGIBILITY_THRESHOLD = 0.40  # Permisivo para Nivel 1


def compute(
    pitch_results: list[dict],
    rhythm_results: dict,
    stimulus: dict,
    paso: int,
    nivel: int = 1
) -> dict:
    """
    Determina inteligibilidad y asigna puntuación clínica según manual MIT.
    
    Args:
        pitch_results: Resultados de pitch_analyzer (F0 por sílaba)
        rhythm_results: Resultados de rhythm_analyzer (timing)
        stimulus: Documento del estímulo de referencia
        paso: Paso del protocolo (2, 3, 4 o 5)
        nivel: Nivel clínico (1, 2 o 3)
    
    Returns:
        {
            "clinical_score": 1,          # int: 0 o 1 (Nivel 1) / 0, 1 o 2 (Niveles 2-3)
            "is_intelligible": True,      # bool
            "intelligibility_score": 0.72, # float interno (0.0–1.0) para diagnóstico
            "acoustic_metrics": {
                "voiced_ratio_global": 0.85,
                "pitch_proximity": 0.72,
                "rhythm_regularity": 0.78,
                "legato": 0.65
            },
            "rationale": "voiced_ratio=0.85, rhythm_ok=true, pitch_approx=true",
            "needs_fallback": False       # Solo relevante en Niveles 2-3
        }
    """
    # ═══ PASO 5: Scoring simplificado ═══
    # En Nivel 1-2: respuesta entonada a pregunta → evaluar si hubo voz
    # En Nivel 3: respuesta HABLADA → solo evaluar voiced_ratio (no pitch/ritmo)
    if paso == 5:
        return _compute_step5(pitch_results, rhythm_results, nivel)
    
    # ═══ PASOS 2-4: Evaluación completa de inteligibilidad ═══
    
    # --- 1. PRESENCIA DE VOZ (voice_presence) ---
    voiced_ratios = [s["voiced_ratio"] for s in pitch_results]
    global_voiced = np.mean(voiced_ratios) if voiced_ratios else 0.0
    
    # Contar sílabas con voz presente
    syllables_with_voice = sum(1 for vr in voiced_ratios if vr >= MIN_SYLLABLE_VOICED)
    total_syllables = max(1, len(voiced_ratios))
    syllable_presence = syllables_with_voice / total_syllables
    
    # Score de presencia de voz (0.0–1.0)
    # Combina ratio global + presencia por sílaba
    voice_score = (global_voiced * 0.4 + syllable_presence * 0.6)
    voice_score = min(1.0, voice_score / 0.8)  # Normalizar: 0.8 → 1.0
    
    # --- 2. APROXIMACIÓN RÍTMICA (rhythm_approximation) ---
    timing_errors = [
        s["timing_error_ms"] 
        for s in rhythm_results["per_syllable_timing"]
    ]
    if timing_errors:
        avg_timing_error = np.mean(timing_errors)
        # Mapeo: 0ms → 1.0, MAX_TIMING_ERROR_MS → 0.0
        rhythm_score = max(0.0, 1.0 - (avg_timing_error / MAX_TIMING_ERROR_MS))
    else:
        rhythm_score = 0.0
    
    # --- 3. APROXIMACIÓN TONAL (pitch_approximation) ---
    cent_errors = [
        abs(s["f0_error_cents"]) 
        for s in pitch_results 
        if s["f0_error_cents"] is not None
    ]
    if cent_errors:
        avg_cent_error = np.mean(cent_errors)
        # Mapeo: 0 cents → 1.0, MAX_PITCH_ERROR_CENTS → 0.0
        pitch_score = max(0.0, 1.0 - (avg_cent_error / MAX_PITCH_ERROR_CENTS))
    else:
        pitch_score = 0.0
    
    # --- 4. LEGATO (continuidad, para diagnóstico) ---
    if len(pitch_results) > 1:
        transition_scores = []
        for i in range(len(pitch_results) - 1):
            curr_voiced = pitch_results[i]["voiced_ratio"]
            next_voiced = pitch_results[i + 1]["voiced_ratio"]
            transition_scores.append(min(curr_voiced, next_voiced))
        legato = float(np.mean(transition_scores))
    else:
        legato = float(pitch_results[0]["voiced_ratio"]) if pitch_results else 0.0
    
    # --- 5. SCORE DE INTELIGIBILIDAD (interno, 0.0–1.0) ---
    intelligibility_score = (
        voice_score * INTELLIGIBILITY_WEIGHTS["voice_presence"] +
        rhythm_score * INTELLIGIBILITY_WEIGHTS["rhythm_approximation"] +
        pitch_score * INTELLIGIBILITY_WEIGHTS["pitch_approximation"]
    )
    
    # --- 6. DECISIÓN DE INTELIGIBILIDAD ---
    is_intelligible = intelligibility_score >= INTELLIGIBILITY_THRESHOLD
    
    # Caso especial: si no hay voz en absoluto → NO inteligible sin importar el score
    if global_voiced < MIN_VOICED_RATIO:
        is_intelligible = False
    
    # Caso especial: si menos de la mitad de las sílabas tienen voz → NO inteligible
    if syllable_presence < MIN_SYLLABLE_PRESENCE_RATIO:
        is_intelligible = False
    
    # --- 7. PUNTUACIÓN CLÍNICA DISCRETA ---
    if nivel == 1:
        # Nivel 1: binario 0 o 1
        clinical_score = 1 if is_intelligible else 0
    else:
        # Niveles 2-3: 0, 1 o 2
        # 2 = éxito directo (inteligible)
        # 1 = se determina después del retroceso (lo maneja Flutter/backend de sesión)
        # 0 = no inteligible
        clinical_score = 2 if is_intelligible else 0
        # NOTA: el valor 1 (éxito con retroceso) se asigna a nivel de sesión,
        # no aquí. El scorer solo decide 0 o 2. Flutter/session manager reduce
        # a 1 si el éxito fue después de un retroceso.
    
    # --- 8. CONSTRUIR RATIONALE ---
    rationale_parts = [
        f"voiced_ratio={global_voiced:.2f}",
        f"syllable_presence={syllable_presence:.2f}",
        f"rhythm_score={rhythm_score:.2f}",
        f"pitch_score={pitch_score:.2f}",
        f"intelligibility={intelligibility_score:.2f}",
        f"threshold={INTELLIGIBILITY_THRESHOLD}"
    ]
    
    return {
        "clinical_score": clinical_score,
        "is_intelligible": is_intelligible,
        "intelligibility_score": round(intelligibility_score, 3),
        "acoustic_metrics": {
            "voiced_ratio_global": round(float(global_voiced), 3),
            "pitch_proximity": round(pitch_score, 3),
            "rhythm_regularity": round(rhythm_score, 3),
            "legato": round(legato, 3)
        },
        "rationale": ", ".join(rationale_parts),
        "needs_fallback": False  # Se determina a nivel de sesión para Niveles 2-3
    }


def _compute_step5(
    pitch_results: list[dict],
    rhythm_results: dict,
    nivel: int
) -> dict:
    """
    Scoring para Paso 5 (respuesta a pregunta).
    
    - Niveles 1-2: respuesta entonada → evaluar voiced_ratio principalmente.
    - Nivel 3: respuesta HABLADA (sin entonación) → solo evaluar que el paciente habló.
    
    El criterio es más simple: ¿el paciente produjo una respuesta vocal?
    Para Nivel 3, NO se evalúa pitch ni ritmo porque es habla normal.
    """
    voiced_ratios = [s["voiced_ratio"] for s in pitch_results]
    global_voiced = float(np.mean(voiced_ratios)) if voiced_ratios else 0.0
    
    # Para Paso 5: el paciente es inteligible si emitió voz suficiente
    is_intelligible = global_voiced >= MIN_VOICED_RATIO
    
    if nivel == 1:
        clinical_score = 1 if is_intelligible else 0
    else:
        clinical_score = 2 if is_intelligible else 0
    
    return {
        "clinical_score": clinical_score,
        "is_intelligible": is_intelligible,
        "intelligibility_score": round(min(1.0, global_voiced / 0.5), 3),
        "acoustic_metrics": {
            "voiced_ratio_global": round(global_voiced, 3),
            "pitch_proximity": None,      # No aplica en Paso 5
            "rhythm_regularity": None,    # No aplica en Paso 5
            "legato": None                # No aplica en Paso 5
        },
        "rationale": f"step5_voiced_ratio={global_voiced:.2f}, threshold={MIN_VOICED_RATIO}",
        "needs_fallback": False
    }
```

**Justificación de los pesos de inteligibilidad:**

| Componente | Peso | Justificación clínica |
|------------|------|----------------------|
| `voice_presence` | 45% | Lo más importante: el paciente debe **emitir voz**. En afasia de Broca, lograr articular es el primer desafío. |
| `rhythm_approximation` | 30% | El ritmo marcado por metrónomo es fundamental en TEM — activa el hemisferio derecho. El paciente debe seguir el tempo aproximadamente. |
| `pitch_approximation` | 25% | La entonación melódica importa pero la **precisión tonal exacta** NO es el criterio clínico. Basta con que el contorno melódico sea aproximado. |

**¿Por qué umbrales permisivos?**
- Los pacientes con afasia de Broca tienen **producción del habla severamente comprometida**
- El manual MIT define éxito como "versión inteligible", no "versión precisa"
- Un umbral `INTELLIGIBILITY_THRESHOLD = 0.40` permite que un paciente que emite voz (45% del score) con ritmo imperfecto pase, que es la realidad clínica
- Estos umbrales son **configurables** vía variables de entorno para ajuste fino con el terapeuta

---

## 10. Sistema de Puntuación Clínica (según manual MIT)

> **Referencia:** Helm-Estabrooks, N., Nicholas, M. & Morgan, A. (1989). *Manual de la Afasia y de la Terapia de la Afasia* — Capítulo TEM/MIT.

### 10.1 Puntuación por paso

#### Nivel 1 — Puntuación binaria (0 ó 1)

| Paso | Nombre | Máx. intentos | Puntuación | Criterio de éxito |
|------|--------|---------------|------------|-------------------|
| 1 | Escucha/Tarareo | — | No se puntúa | — |
| 2 | Unísono | 4 | 0 ó 1 | Producción inteligible (voiced + ritmo + entonación aproximados) |
| 3 | Completar | 4 | 0 ó 1 | Producción inteligible al completar sin referencia |
| 4 | Repetición | 1 | 0 ó 1 | Producción inteligible solo con metrónomo |
| 5 | Pregunta | 1 | 0 ó 1 | Respuesta vocal presente e inteligible |

- **Máximo por estímulo:** 4 puntos
- Si el paciente falla los 4 intentos → 0 puntos en ese paso → abandonar estímulo

#### Nivel 2 — Puntuación con retroceso (0, 1 ó 2)

| Paso | Máx puntuación | Lógica |
|------|----------------|--------|
| 1 (Introducción) | No se puntúa | — |
| 2 (Unísono con desvanecimiento) | 1 | 0 ó 1 (binario, igual que Nivel 1) |
| 3 (Repetición con pausa 6s) | 2 | 2 = éxito directo; 1 = éxito tras retroceso a paso 2; 0 = falla |
| 4 (Respuesta a pregunta) | 2 | 2 = éxito directo; 1 = éxito tras retroceso a paso 3; 0 = falla |

- **Máximo por estímulo:** 6 puntos (1 + 2 + 2 + contribución paso 1)(*)
- **Retroceso:** Si falla paso 3 → volver a paso 2. Si luego tiene éxito en paso 3 → obtiene 1 (no 2). Si falla de nuevo → 0.

#### Nivel 3 — Transición hacia habla normal (0, 1 ó 2)

| Paso | Máx puntuación | Lógica |
|------|----------------|--------|
| 1 (Repetición retrasada) | 2 | 2 = éxito directo; 0 = falla |
| 2 (Introducción sprechgesang) | No se puntúa | — |
| 3 (Sprechgesang con desvanecimiento) | 2 | 2 = éxito directo; 1 = éxito con retroceso; 0 = falla |
| 4 (Repetición hablada) | 2 | 2 = éxito directo; 1 = éxito con retroceso; 0 = falla |
| 5 (Respuesta a pregunta) | 2 | 2 = éxito directo; 1 = éxito con retroceso; 0 = falla |

- **Máximo por estímulo:** 8 puntos
- **IMPORTANTE Nivel 3:** Los pasos 4 y 5 evalúan **habla normal** (no entonada) → el scorer no evalúa pitch ni ritmo, solo presencia de voz.

### 10.2 Cómo el módulo Python asigna la puntuación por paso

```
PIPELINE DE DECISIÓN POR INTENTO:

1. Ejecutar análisis acústico (pitch, ritmo, voicing)
2. Calcular score de inteligibilidad interno (0.0–1.0)
3. Aplicar umbrales de decisión:
   - ¿Hay voz suficiente? (voiced_ratio >= 0.30)
   - ¿Más de la mitad de sílabas tienen voz? (syllable_presence >= 0.50)
   - ¿Score de inteligibilidad >= umbral? (0.40 para Nivel 1)
4. Decisión:
   - Inteligible → clinical_score = 1 (Nivel 1) ó 2 (Niveles 2-3 éxito directo)
   - No inteligible → clinical_score = 0
5. La puntuación 1 en Niveles 2-3 (retroceso exitoso) la determina el
   session manager de Flutter, NO el módulo Python individual.
```

### 10.3 Diferencias de evaluación por paso

| Paso | Contexto acústico | Ajuste del scorer |
|------|-------------------|-------------------|
| 2 (Unísono) | Audio de referencia suena simultáneamente | Scoring estándar. La grabación captura parte del audio de la app — considerar en umbrales (voiced_ratio será alto por la referencia). |
| 3 (Completar) | Audio baja a mitad | Scoring estándar. Menos interferencia del audio de referencia. |
| 4 (Repetición) | Solo metrónomo, sin referencia | Scoring estándar. Grabación más limpia — evaluación más confiable. |
| 5 (Pregunta) | Sin metrónomo ni referencia | **Scoring simplificado**: solo evaluar voiced_ratio (¿habló?). NO evaluar pitch ni ritmo en Niveles 1-2 (respuesta entonada). En Nivel 3, solo evaluar presencia de voz (habla normal). |

---

## 11. Puntuación de Sesión y Criterios de Avance

> **Referencia:** Helm-Estabrooks et al., 1989 — "Puntuación de las sesiones" y "Criterios de entrada y avance"

### 11.1 Puntuación de sesión

Al completar todos los estímulos de una sesión, se calcula:

```
Puntuación de sesión (%) = (Σ puntos obtenidos / Σ puntos posibles) × 100
```

**Ejemplo Nivel 1** (10 estímulos, 4 puntos max cada uno):

| Estímulo | P2 | P3 | P4 | P5 | Obtenido | Posible |
|----------|----|----|----|----|----------|---------|
| mamá | 1 | 1 | 1 | 1 | 4 | 4 |
| papá | 1 | 1 | 0 | 0 | 2 | 4 |
| agua | 1 | 0 | – | – | 1 | 4 |  ← abandonado en paso 3
| no sé | 1 | 1 | 1 | 0 | 3 | 4 |
| ... | ... | ... | ... | ... | ... | ... |
| **Total** | | | | | **25** | **40** |

**Puntuación = 25/40 × 100 = 62.5%**

### 11.2 Puntuación por pasos (desglose)

Además del porcentaje global, se calcula el porcentaje por paso para diagnóstico:

```
% Paso 2 = (Σ puntos paso 2 / Σ posibles paso 2) × 100
% Paso 3 = (Σ puntos paso 3 / Σ posibles paso 3) × 100
...
```

Esto permite identificar en qué paso tiene más dificultad el paciente (útil para el terapeuta).

### 11.3 Criterios de avance de nivel

Según el manual MIT:

| Criterio | Condición | Acción |
|----------|-----------|--------|
| **Avanzar al siguiente nivel** | ≥ 90% en **5 sesiones consecutivas** con estímulos variados | Subir de Nivel 1 → 2, o Nivel 2 → 3 |
| **Permanecer en el programa** | Media de las últimas 3 sesiones > media de las 3 sesiones anteriores | Continuar en el nivel actual |
| **Considerar salida** | Media de las últimas 3 sesiones ≤ media de las 3 anteriores (con estímulos diferentes) | El terapeuta evalúa si continuar o finalizar el programa |

### 11.4 Colección de progreso: `pacientes/{pacienteId}/progreso_TEM`

**Quién escribe:** Backend Python o Flutter (al completar cada sesión)  
**Quién lee:** Flutter (para mostrar progreso) + lógica de avance

```jsonc
{
  "nivel_actual": 1,
  "sesiones_completadas": [
    {
      "sessionId": "SES_1719000000000",
      "fecha": "2025-06-01T12:00:00Z",
      "nivel": 1,
      "session_score_pct": 82.5,
      "total_obtained": 33,
      "total_possible": 40,
      "scores_by_step": {
        "paso_2_pct": 90.0,
        "paso_3_pct": 80.0,
        "paso_4_pct": 70.0,
        "paso_5_pct": 80.0
      }
    }
    // ... historial de sesiones
  ],
  "consecutive_high_sessions": 0,         // Contador de sesiones consecutivas ≥90%
  "last_3_sessions_mean": null,           // Media de las últimas 3 sesiones
  "prev_3_sessions_mean": null,           // Media de las 3 sesiones anteriores
  "ready_to_advance": false,              // true cuando consecutive_high_sessions >= 5
  "updated_at": "2025-06-01T12:00:00Z"
}
```

### 11.5 Lógica de avance (pseudocódigo)

```python
def evaluate_progression(progreso: dict) -> dict:
    """
    Evalúa si el paciente debe avanzar, permanecer o considerar salida.
    Se ejecuta al completar cada sesión.
    """
    sessions = progreso["sesiones_completadas"]
    nivel = progreso["nivel_actual"]
    
    # Filtrar sesiones del nivel actual
    nivel_sessions = [s for s in sessions if s["nivel"] == nivel]
    
    if len(nivel_sessions) < 5:
        return {"action": "continue", "reason": "Menos de 5 sesiones completadas"}
    
    # Últimas 5 sesiones del nivel actual
    last_5 = nivel_sessions[-5:]
    all_above_90 = all(s["session_score_pct"] >= 90.0 for s in last_5)
    
    if all_above_90:
        return {
            "action": "advance",
            "reason": f"≥90% en 5 sesiones consecutivas → avanzar a Nivel {nivel + 1}",
            "new_nivel": nivel + 1
        }
    
    # Criterio de permanencia: últimas 3 > anteriores 3
    if len(nivel_sessions) >= 6:
        last_3_mean = np.mean([s["session_score_pct"] for s in nivel_sessions[-3:]])
        prev_3_mean = np.mean([s["session_score_pct"] for s in nivel_sessions[-6:-3]])
        
        if last_3_mean > prev_3_mean:
            return {
                "action": "continue",
                "reason": f"Progresando: media últimas 3 ({last_3_mean:.1f}%) > anteriores 3 ({prev_3_mean:.1f}%)"
            }
        else:
            return {
                "action": "review",
                "reason": f"Estancado: media últimas 3 ({last_3_mean:.1f}%) ≤ anteriores 3 ({prev_3_mean:.1f}%). Terapeuta debe evaluar."
            }
    
    return {"action": "continue", "reason": "Insuficientes sesiones para evaluar tendencia"}
```

---

## 12. Cloud Function Trigger (Proxy)

**Archivo:** `backend_tem/trigger/main.py`

**Función 1:** Se dispara al crear un attempt doc con `status: "pending_analysis"` y envía un POST al endpoint `/analyze` de Cloud Run.

**Función 2:** Se dispara al subir un archivo a Storage con metadata `type: "calibration"` y envía un POST al endpoint `/calibrate` de Cloud Run.

```python
"""
Cloud Function (Gen2) — Proxy Firestore/Storage → Cloud Run.
Dos funciones:
  1. on_attempt_created: Firestore onCreate en sesiones_TEM/{sessionId}/attempts/{attemptId}
  2. on_calibration_uploaded: Storage onFinalize en calibraciones/

Framework: functions-framework (Gen2 Python)
"""

import os
import requests
from firebase_functions import firestore_fn, storage_fn, options

CLOUD_RUN_URL = os.environ.get("CLOUD_RUN_URL", "https://backend-tem-XXXXXX-uc.a.run.app")

# ---------- Trigger 1: Análisis de intento ----------

@firestore_fn.on_document_created(
    document="sesiones_TEM/{sessionId}/attempts/{attemptId}",
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=60
)
def on_attempt_created(event: firestore_fn.Event[firestore_fn.DocumentSnapshot]):
    """
    Se dispara cuando Flutter crea un attempt doc con status: "pending_analysis".
    Envía POST /analyze a Cloud Run.
    """
    data = event.data.to_dict()
    
    if data.get("status") != "pending_analysis":
        return  # Ignorar si ya fue analizado
    
    session_id = event.params["sessionId"]
    attempt_id = event.params["attemptId"]
    paciente_id = data.get("pacienteId", "")
    
    payload = {
        "attemptId": attempt_id,
        "sessionId": session_id,
        "pacienteId": paciente_id
    }
    
    try:
        resp = requests.post(
            f"{CLOUD_RUN_URL}/analyze",
            json=payload,
            timeout=30
        )
        resp.raise_for_status()
    except Exception as e:
        print(f"Error calling /analyze: {e}")
        # El backend debe manejar reintentos si es necesario


# ---------- Trigger 2: Calibración vocal ----------

@storage_fn.on_object_finalized(
    bucket="apphasia-7a930.firebasestorage.app",
    region="us-central1",
    memory=options.MemoryOption.MB_256,
    timeout_sec=60
)
def on_calibration_uploaded(event: storage_fn.CloudEvent):
    """
    Se dispara cuando se sube un archivo a Storage con metadata type: "calibration".
    Envía POST /calibrate a Cloud Run.
    """
    data = event.data
    
    # Solo procesar archivos de calibración
    metadata = data.get("metadata", {})
    if metadata.get("type") != "calibration":
        return
    
    storage_path = data.get("name", "")
    paciente_id = metadata.get("pacienteId", "")
    
    if not paciente_id:
        print("Error: pacienteId no encontrado en metadata")
        return
    
    payload = {
        "storagePath": storage_path,
        "pacienteId": paciente_id
    }
    
    try:
        resp = requests.post(
            f"{CLOUD_RUN_URL}/calibrate",
            json=payload,
            timeout=30
        )
        resp.raise_for_status()
    except Exception as e:
        print(f"Error calling /calibrate: {e}")
```

**Despliegue:**
```bash
# Desde backend_tem/trigger/
gcloud functions deploy on_attempt_created \
  --gen2 \
  --runtime python311 \
  --trigger-event-filters="type=google.cloud.firestore.document.v1.created" \
  --trigger-event-filters="database=(default)" \
  --trigger-event-filters-path-pattern="document=sesiones_TEM/{sessionId}/attempts/{attemptId}" \
  --region us-central1 \
  --set-env-vars CLOUD_RUN_URL=https://backend-tem-XXXXXX-uc.a.run.app

gcloud functions deploy on_calibration_uploaded \
  --gen2 \
  --runtime python311 \
  --trigger-bucket apphasia-7a930.firebasestorage.app \
  --region us-central1 \
  --set-env-vars CLOUD_RUN_URL=https://backend-tem-XXXXXX-uc.a.run.app
```

---

## 13. Docker y Despliegue en Cloud Run

### Dockerfile

```dockerfile
FROM python:3.11-slim

# Instalar dependencias del sistema para Parselmouth y librosa
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    libffi-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar requirements e instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código fuente
COPY . .

# Puerto que usa Cloud Run
ENV PORT=8080
EXPOSE 8080

# Arrancar FastAPI con uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### requirements.txt

```txt
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
parselmouth>=0.4.3
librosa>=0.10.1
soundfile>=0.12.1
numpy>=1.24.0
firebase-admin>=6.2.0
pydantic>=2.5.0
```

### .dockerignore

```
__pycache__/
*.pyc
.git/
.env
tests/
trigger/
README.md
```

### Despliegue en Cloud Run

```bash
# Desde backend_tem/
# 1. Construir imagen
gcloud builds submit --tag gcr.io/apphasia-7a930/backend-tem

# 2. Desplegar en Cloud Run
gcloud run deploy backend-tem \
  --image gcr.io/apphasia-7a930/backend-tem \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 5 \
  --memory 1Gi \
  --cpu 1 \
  --timeout 60 \
  --set-env-vars "GCP_PROJECT=apphasia-7a930,STORAGE_BUCKET=apphasia-7a930.firebasestorage.app"
```

**Configuración de Cloud Run:**
- `min-instances=0` — escala a cero cuando no hay tráfico (ahorra costos)
- `max-instances=5` — límite para controlar costos
- `memory=1Gi` — Parselmouth necesita memoria para procesamiento FFT
- `cpu=1` — suficiente para análisis de WAV cortos (<5s)
- `timeout=60s` — el análisis debería completarse en <5s, con margen generoso

---

## 14. Integración con Flutter

### Estado actual (stub a reemplazar)

Actualmente en `lib/presentation/screens/tem/tem_exercise_screen.dart` línea ~503:

```dart
/// Stub de evaluación — TODO Sprint 2: enviar al backend Python.
/// Por ahora devuelve siempre éxito para verificar el flujo completo.
Future<bool> _evaluate(List<String> paths) async {
  if (paths.isEmpty) return false;
  return true; // optimistic — reemplazar con llamada real al backend
}
```

### Cómo Flutter consumirá los resultados (NO lo hace el módulo Python, pero es contexto necesario)

**Opción A — Listener en attempt.status (recomendada):**

```dart
// Flutter escucha cambios en el attempt doc
StreamBuilder<DocumentSnapshot>(
  stream: FirebaseFirestore.instance
    .collection('sesiones_TEM')
    .doc(sessionId)
    .collection('attempts')
    .doc(attemptId)
    .snapshots(),
  builder: (context, snapshot) {
    final data = snapshot.data?.data() as Map<String, dynamic>?;
    final status = data?['status'];
    if (status == 'analyzed') {
      final clinicalScore = data?['clinical_score'] as int?;
      final isIntelligible = data?['is_intelligible'] as bool?;
      // Usar la puntuación clínica para decidir si el paso fue exitoso
      // clinical_score: 0 = no inteligible, 1 = inteligible (Nivel 1)
      //                 0 = falla, 1 = con retroceso, 2 = directo (Niveles 2-3)
    } else if (status == 'error') {
      // Mostrar mensaje de error
    }
    // Mientras status == 'pending_analysis' → mostrar spinner
  },
)
```

**Flujo de evaluación actualizado (Sprint 2):**
1. Flutter graba y sube WAV (ya implementado)
2. Flutter crea attempt doc con `status: "pending_analysis"` (ya implementado)
3. Flutter escucha cambios en el attempt doc (NUEVO)
4. Cloud Function detecta el onCreate → POST /analyze a Cloud Run
5. Cloud Run procesa → determina inteligibilidad → asigna clinical_score → escribe resultado → actualiza attempt
6. Flutter listener detecta status "analyzed" → lee `clinical_score` e `is_intelligible`
7. Si `is_intelligible == true` → paso aprobado → avanzar al siguiente paso
8. Si `is_intelligible == false` → reintentar (hasta 4 intentos en pasos 2-3)
9. Al completar todos los estímulos → Flutter calcula `session_score_pct` y actualiza el doc de sesión

**Latencia esperada:** 3–8 segundos desde subida del WAV hasta resultado disponible:
- Upload WAV: ~1-2s
- Cloud Function trigger: ~500ms
- Descarga WAV en Cloud Run: ~500ms
- Análisis acústico: ~1-3s
- Escritura en Firestore: ~200ms
- Listener Firebase: ~200ms

---

## 15. Flujo Completo de Datos (End-to-End)

### Flujo de análisis de un intento (Pasos 2-5)

```
TIEMPO   COMPONENTE              ACCIÓN
──────   ──────────              ──────
t+0s     Flutter                 Paciente termina de cantar
t+0.1s   Flutter                 RecordingService.stopRecording() → WAV local
t+0.2s   Flutter                 _uploadAsync() → fire-and-forget
t+1.0s   Firebase Storage        WAV subido a attempts/{pid}/{sid}/{aid}.wav
t+1.1s   Firestore               Attempt doc creado:
                                   sesiones_TEM/{sid}/attempts/{aid}
                                   { status: "pending_analysis", ... }
t+1.3s   Cloud Function          onCreate trigger detecta nuevo doc
t+1.4s   Cloud Function          POST /analyze → Cloud Run
t+1.5s   Cloud Run               Recibe request, lee attempt doc
t+1.6s   Cloud Run               Lee estímulo de stimuli_TEM/{stimulusId}
t+1.7s   Cloud Run               Lee calibración de pacientes/{pid}/calibracion
t+1.8s   Cloud Run               Descarga WAV de Storage
t+2.0s   Cloud Run               syllable_aligner → alignment
t+2.5s   Cloud Run               pitch_analyzer → F0 por sílaba
t+3.0s   Cloud Run               rhythm_analyzer → timing
t+3.2s   Cloud Run               scorer → inteligibilidad + clinical_score (0/1 o 0/1/2)
t+3.5s   Cloud Run               Escribe analysis_results_TEM/{anId}
t+3.6s   Cloud Run               Actualiza attempt.status → "analyzed", clinical_score, is_intelligible
t+3.8s   Flutter                 StreamBuilder detecta status == "analyzed"
t+3.9s   Flutter                 Lee clinical_score + is_intelligible del attempt doc
t+4.0s   Flutter                 Si is_intelligible → avanzar paso; si no → retry (hasta 4)
```

### Flujo de calibración

```
TIEMPO   COMPONENTE              ACCIÓN
──────   ──────────              ──────
t+0s     Flutter                 Paciente emite vocal "aaaaa" (~3s)
t+3s     Flutter                 Detiene grabación → WAV local
t+3.5s   Flutter                 Sube WAV a calibraciones/{pid}/vocal_{ts}.wav
                                   metadata: { type: "calibration", pacienteId: pid }
t+4s     Cloud Function          onFinalize trigger detecta archivo
t+4.1s   Cloud Function          POST /calibrate → Cloud Run
t+4.2s   Cloud Run               Descarga WAV de Storage
t+4.5s   Cloud Run               Parselmouth: F0 frame a frame
t+5.0s   Cloud Run               Calcula f0_min, f0_max, f0_comfort
t+5.5s   Cloud Run               Escribe pacientes/{pid}/calibracion
t+5.7s   Flutter                 Listener detecta actualización
t+5.8s   Flutter                 Muestra resultado al paciente
```

---

## 16. Variables de Entorno y Configuración

### Cloud Run (`backend_tem/config.py`)

```python
import os

# Proyecto Firebase / GCP
GCP_PROJECT = os.environ.get("GCP_PROJECT", "apphasia-7a930")
STORAGE_BUCKET = os.environ.get("STORAGE_BUCKET", "apphasia-7a930.firebasestorage.app")

# Análisis acústico
PITCH_FLOOR_HZ = float(os.environ.get("PITCH_FLOOR_HZ", "50.0"))
PITCH_CEILING_HZ = float(os.environ.get("PITCH_CEILING_HZ", "500.0"))
PITCH_TIME_STEP = float(os.environ.get("PITCH_TIME_STEP", "0.01"))

# Scoring — Umbrales de inteligibilidad (según manual MIT)
INTELLIGIBILITY_THRESHOLD = float(os.environ.get("INTELLIGIBILITY_THRESHOLD", "0.40"))
MIN_VOICED_RATIO = float(os.environ.get("MIN_VOICED_RATIO", "0.30"))
MIN_SYLLABLE_VOICED = float(os.environ.get("MIN_SYLLABLE_VOICED", "0.20"))
MIN_SYLLABLE_PRESENCE_RATIO = float(os.environ.get("MIN_SYLLABLE_PRESENCE_RATIO", "0.50"))
MAX_TIMING_ERROR_MS = float(os.environ.get("MAX_TIMING_ERROR_MS", "400"))
MAX_PITCH_ERROR_CENTS = float(os.environ.get("MAX_PITCH_ERROR_CENTS", "300"))

# Avance de nivel
ADVANCE_THRESHOLD_PCT = float(os.environ.get("ADVANCE_THRESHOLD_PCT", "90.0"))
ADVANCE_CONSECUTIVE_SESSIONS = int(os.environ.get("ADVANCE_CONSECUTIVE_SESSIONS", "5"))

# Audio
EXPECTED_SAMPLE_RATE = 16000
EXPECTED_CHANNELS = 1

# Versión del análisis (incluida en cada resultado)
ANALYSIS_VERSION = os.environ.get("ANALYSIS_VERSION", "praat_cloud_run_v2.0")
```

### Cloud Function (`trigger/`)

```
CLOUD_RUN_URL=https://backend-tem-XXXXXX-uc.a.run.app
```

### Firebase Admin SDK

**Inicialización sin service account key** (Cloud Run y Cloud Functions autentican automáticamente via metadata del proyecto):

```python
import firebase_admin
from firebase_admin import credentials, firestore, storage

# En Cloud Run / Cloud Functions: usa Application Default Credentials
firebase_admin.initialize_app(options={
    'storageBucket': 'apphasia-7a930.firebasestorage.app'
})

db = firestore.client()
bucket = storage.bucket()
```

**Para desarrollo local:** Usar service account key:
```python
cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'storageBucket': 'apphasia-7a930.firebasestorage.app'
})
```

---

## 17. Tests

### Tests unitarios requeridos

| Test | Qué verifica |
|------|-------------|
| `test_pitch_analyzer.py` | F0 medido correctamente para WAV sintético con tono conocido |
| `test_pitch_analyzer.py` | voiced_ratio = 0 para WAV con silencio |
| `test_pitch_analyzer.py` | Error en cents calculado correctamente |
| `test_rhythm_analyzer.py` | Onsets detectados dentro de ±50ms del esperado |
| `test_rhythm_analyzer.py` | IOI calculado correctamente |
| `test_scorer.py` | Grabación con voz clara y ritmo correcto → `clinical_score = 1`, `is_intelligible = True` |
| `test_scorer.py` | Silencio total → `clinical_score = 0`, `is_intelligible = False` |
| `test_scorer.py` | Voz presente pero ritmo muy desfasado → verificar decisión de inteligibilidad |
| `test_scorer.py` | Voz débil (voiced_ratio < 0.3) → `clinical_score = 0` por regla de mínimo de voz |
| `test_scorer.py` | Paso 5 usa scoring simplificado (solo evalúa voiced_ratio) |
| `test_scorer.py` | Nivel 2: scorer devuelve `clinical_score = 2` (éxito directo) o `0` (falla) |
| `test_syllable_aligner.py` | Alineación con grabación más lenta que template |
| `test_syllable_aligner.py` | Fallback a template cuando no hay onsets |
| `test_endpoints.py` | POST /analyze devuelve 200 y crea resultado con `clinical_score` |
| `test_endpoints.py` | POST /analyze devuelve 409 si attempt ya analizado |
| `test_endpoints.py` | POST /calibrate devuelve resultado con f0 válidos |
| `test_endpoints.py` | GET /health devuelve 200 |
| `test_session_scoring.py` | Cálculo de `session_score_pct` correcto con estímulos completos y abandonados |
| `test_session_scoring.py` | Criterio de avance: ≥90% en 5 consecutivas → `ready_to_advance = True` |
| `test_session_scoring.py` | Criterio de permanencia: media últimas 3 > media anteriores 3 |

### Fixtures de audio para tests

Generar WAVs sintéticos con `numpy` + `soundfile`:

```python
import numpy as np
import soundfile as sf

def generate_sine_wav(frequency_hz=180, duration_s=1.0, sr=16000, filepath="test.wav"):
    """Genera WAV con tono puro para tests."""
    t = np.linspace(0, duration_s, int(sr * duration_s), endpoint=False)
    signal = 0.5 * np.sin(2 * np.pi * frequency_hz * t)
    sf.write(filepath, signal.astype(np.float32), sr)

def generate_two_syllable_wav(f0_1=180, f0_2=175, dur_ms=450, gap_ms=50, sr=16000):
    """Genera WAV con dos sílabas de tono diferente (simula 'mamá')."""
    dur_samples = int(dur_ms / 1000 * sr)
    gap_samples = int(gap_ms / 1000 * sr)
    
    t1 = np.linspace(0, dur_ms/1000, dur_samples, endpoint=False)
    syl1 = 0.5 * np.sin(2 * np.pi * f0_1 * t1)
    
    gap = np.zeros(gap_samples)
    
    t2 = np.linspace(0, dur_ms/1000, dur_samples, endpoint=False)
    syl2 = 0.5 * np.sin(2 * np.pi * f0_2 * t2)
    
    signal = np.concatenate([syl1, gap, syl2])
    return signal.astype(np.float32)
```

---

## 18. Criterios de Éxito

- [ ] Cloud Function se dispara al crear attempt con `status: "pending_analysis"`
- [ ] Backend descarga WAV de Storage sin errores
- [ ] Backend lee estímulo de referencia de `stimuli_TEM/{stimulusId}` correctamente
- [ ] Backend lee calibración del paciente (si existe, sino usa defaults)
- [ ] `analysis_results_TEM/{analysisId}` se escribe con todos los campos del esquema §4.3 (incluyendo `clinical_score`, `intelligibility_decision`, `acoustic_metrics`)
- [ ] `attempt.status` transiciona correctamente `pending_analysis → analyzed`
- [ ] `attempt.clinical_score` contiene puntuación discreta (0/1 para Nivel 1)
- [ ] `attempt.is_intelligible` refleja la decisión de inteligibilidad
- [ ] Grabación con voz clara → `clinical_score = 1` (inteligible)
- [ ] Silencio total → `clinical_score = 0` (no inteligible)
- [ ] Voz parcial con ritmo aproximado → `clinical_score = 1` (umbral permisivo)
- [ ] Paso 5 usa scoring simplificado (solo evalúa que el paciente habla)
- [ ] POST /calibrate calcula f0_min, f0_max, f0_comfort correctamente
- [ ] Calibración se escribe en `pacientes/{pacienteId}/calibracion`
- [ ] GET /health responde con status y versión
- [ ] Docker imagen construye sin errores
- [ ] Despliegue en Cloud Run funciona con `min-instances=0`
- [ ] Latencia end-to-end < 8 segundos (upload → resultado en Firestore)
- [ ] Manejo de errores: attempt nunca queda en `pending_analysis` indefinidamente
- [ ] Tests unitarios pasan para todos los módulos del analyzer
- [ ] Puntuación de sesión calcula correctamente `session_score_pct`
- [ ] Criterios de avance evalúan 5 sesiones consecutivas ≥90%

---

## 19. Reglas No Negociables

1. **Audio WAV PCM 16-bit, mono, 16000 Hz** — sin excepciones. Validar al inicio del pipeline.
2. **Usar `pacienteId`** (no `patientId`) en todo el código — coherente con Firestore existente.
3. **Usar `stimulusId`** como campo para buscar el template en `stimuli_TEM/`.
4. **NUNCA dejar un attempt en `pending_analysis` indefinidamente** — todo camino debe terminar en `analyzed` o `error`.
5. **No generar ni almacenar `viseme_timeline`** — los visemas son responsabilidad exclusiva del cliente Flutter.
6. **Score siempre con disclaimer** — la app muestra "Resultado preliminar — requiere validación del terapeuta antes de avanzar de nivel".
7. **`pending_therapist_review: true`** — mantener este campo en el attempt; el terapeuta lo cambia desde el panel web.
8. **Firebase Admin SDK sin service account key hardcodeada en producción** — usar Application Default Credentials en Cloud Run.
9. **Invariante `len(syllables) == len(onsets_ms) == len(durations_ms) == len(f0_template_hz)`** — validar al leer el estímulo. Si no se cumple, error.
10. **Parselmouth para F0, no FFT manual** — los pacientes con afasia tienen voz débil; Parselmouth/Praat es robusto para señales no periódicas.
11. **Puntuación clínica discreta según manual MIT** — `clinical_score` debe ser 0 o 1 para Nivel 1, y 0/1/2 para Niveles 2-3. NUNCA devolver scores continuos 0-100 como puntuación principal.
12. **Criterio de evaluación = INTELIGIBILIDAD** — NO precisión acústica. Los umbrales deben ser permisivos para pacientes con afasia de Broca severa.
13. **Avance de nivel requiere validación del terapeuta** — aunque el sistema detecte ≥90% en 5 sesiones, `ready_to_advance` es una recomendación, NO una acción automática.

---

## Apéndice A — Catálogo de Estímulos Nivel 1

Estímulos actualmente cargados en `stimuli_TEM/` (producción):

| stimulusId | texto | syllables | f0_template_hz | patron_tonal | num_silabas |
|------------|-------|-----------|----------------|--------------|-------------|
| ST_TEM_N1_001 | mamá | ["ma","má"] | [180.0, 175.0] | LH | 2 |
| ST_TEM_N1_002 | papá | ["pa","pá"] | [175.0, 170.0] | LH | 2 |
| ST_TEM_N1_003 | agua | ["a","gua"] | [170.0, 155.0] | HL | 2 |
| ST_TEM_N1_004 | no sé | ["no","sé"] | [185.0, 165.0] | LH | 2 |
| ST_TEM_N1_005 | ayuda | ["a","yu","da"] | [185.0, 160.0, 155.0] | HLL | 3 |
| ST_TEM_N1_006 | gracias | ["gra","cias"] | [180.0, 160.0] | HL | 2 |
| ST_TEM_N1_007 | casa | ["ca","sa"] | [185.0, 165.0] | HL | 2 |
| ST_TEM_N1_008 | hambre | ["ham","bre"] | [175.0, 160.0] | HL | 2 |
| ST_TEM_N1_009 | dolor | ["do","lor"] | [170.0, 180.0] | LH | 2 |
| ST_TEM_N1_010 | bien | ["bien"] | [175.0] | L | 1 |

> Los `onsets_ms` y `durations_ms` de producción fueron calculados por `scripts/align_stimuli.py` usando Whisper forced alignment sobre los WAVs reales. No copiar los valores mock del seed — están desactualizados.

---

## Apéndice B — Diagrama de Secuencia

```
┌──────────┐    ┌──────────────┐    ┌───────────────┐    ┌───────────────┐
│  Flutter  │    │  Firestore   │    │ Cloud Function │    │  Cloud Run    │
│   App     │    │  + Storage   │    │   (trigger)    │    │ (backend_tem) │
└────┬──────┘    └──────┬───────┘    └───────┬────────┘    └──────┬────────┘
     │                  │                     │                    │
     │ 1. Upload WAV    │                     │                    │
     │ ────────────────>│                     │                    │
     │                  │                     │                    │
     │ 2. Create attempt│                     │                    │
     │    doc (pending)  │                    │                    │
     │ ────────────────>│                     │                    │
     │                  │                     │                    │
     │                  │ 3. onCreate trigger │                    │
     │                  │ ───────────────────>│                    │
     │                  │                     │                    │
     │                  │                     │ 4. POST /analyze   │
     │                  │                     │ ──────────────────>│
     │                  │                     │                    │
     │                  │ 5. Read attempt doc │                    │
     │                  │ <────────────────────────────────────────│
     │                  │                     │                    │
     │                  │ 6. Read stimulus doc│                    │
     │                  │ <────────────────────────────────────────│
     │                  │                     │                    │
     │                  │ 7. Download WAV     │                    │
     │                  │ <────────────────────────────────────────│
     │                  │                     │                    │
     │                  │                     │   8. Analyze:      │
     │                  │                     │   pitch + rhythm   │
     │                  │                     │   + scoring        │
     │                  │                     │                    │
     │                  │ 9. Write result doc │                    │
     │                  │ <────────────────────────────────────────│
     │                  │                     │                    │
     │                  │ 10. Update attempt  │                    │
     │                  │     status="analyzed│"                   │
     │                  │ <────────────────────────────────────────│
     │                  │                     │                    │
     │ 11. Listener     │                     │                    │
     │     detects      │                     │                    │
     │     "analyzed"   │                     │                    │
     │ <────────────────│                     │                    │
     │                  │                     │                    │
     │ 12. Read score   │                     │                    │
     │ ────────────────>│                     │                    │
     │                  │                     │                    │
     ▼                  ▼                     ▼                    ▼
```

---

## Apéndice C — `main.py` (FastAPI) — Estructura base

```python
"""
backend_tem/main.py — FastAPI app para análisis acústico TEM.

Endpoints:
  POST /analyze    — Analiza grabación de un intento
  POST /calibrate  — Calibración vocal del paciente
  GET  /health     — Health check
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import time

from firebase_client import FirebaseClient
from analyzer.syllable_aligner import align
from analyzer.pitch_analyzer import analyze as analyze_pitch
from analyzer.rhythm_analyzer import analyze as analyze_rhythm
from analyzer.scorer import compute as compute_score
from config import ANALYSIS_VERSION, EXPECTED_SAMPLE_RATE

app = FastAPI(title="RehabilitIA — Backend TEM", version="1.0.0")
fb = FirebaseClient()


class AnalyzeRequest(BaseModel):
    attemptId: str
    sessionId: str
    pacienteId: str


class CalibrateRequest(BaseModel):
    storagePath: str
    pacienteId: str


@app.get("/health")
async def health():
    return {"status": "ok", "version": ANALYSIS_VERSION}


@app.post("/analyze")
async def analyze(req: AnalyzeRequest):
    start_time = time.time()
    
    try:
        # 1. Leer attempt doc
        attempt = fb.read_attempt(req.sessionId, req.attemptId)
        if attempt["status"] != "pending_analysis":
            raise HTTPException(409, "Attempt ya procesado")
        
        # 2. Leer estímulo de referencia
        stimulus = fb.read_stimulus(attempt["stimulusId"])
        
        # 3. Leer calibración (opcional)
        calibration = fb.read_calibration(req.pacienteId)
        
        # 4. Descargar WAV
        wav_data, sr = fb.download_wav(attempt["storagePath"])
        assert sr == EXPECTED_SAMPLE_RATE
        
        # 5. Pipeline de análisis
        alignment = align(wav_data, sr, stimulus)
        pitch_results = analyze_pitch(wav_data, sr, alignment, stimulus, calibration)
        rhythm_results = analyze_rhythm(wav_data, sr, alignment, stimulus)
        
        # 6. Scoring (determina inteligibilidad + puntuación clínica)
        paso = attempt.get("paso", 2)
        nivel = stimulus.get("nivel_clinico", 1)
        scores = compute_score(pitch_results, rhythm_results, stimulus, paso, nivel)
        
        # 7. Construir y escribir resultado
        processing_time = int((time.time() - start_time) * 1000)
        analysis_id = f"AN_{req.attemptId}"
        
        result = {
            "analysisId": analysis_id,
            "attemptId": req.attemptId,
            "sessionId": req.sessionId,
            "stimulusId": attempt["stimulusId"],
            "pacienteId": req.pacienteId,
            "paso": paso,
            "stepName": attempt.get("stepName", ""),
            "attemptNumber": attempt.get("attemptNumber", 1),
            "nivel": nivel,
            "clinical_score": scores["clinical_score"],
            "intelligibility_decision": {
                "is_intelligible": scores["is_intelligible"],
                "rationale": scores["rationale"],
                "needs_fallback": scores["needs_fallback"]
            },
            "acoustic_metrics": scores["acoustic_metrics"],
            "per_syllable": build_per_syllable(pitch_results, rhythm_results, stimulus),
            "warnings": generate_warnings(pitch_results, rhythm_results),
            "confidence": compute_confidence(pitch_results, rhythm_results),
            "analysis_version": ANALYSIS_VERSION,
            "processing_time_ms": processing_time
        }
        
        fb.write_analysis_result(analysis_id, result)
        fb.update_attempt_analyzed(
            req.sessionId, req.attemptId, analysis_id,
            scores["clinical_score"], scores["is_intelligible"]
        )
        
        return {"status": "ok", "analysisId": analysis_id}
    
    except HTTPException:
        raise
    except Exception as e:
        # Marcar attempt como error para no dejarlo en pending_analysis
        fb.update_attempt_error(req.sessionId, req.attemptId, str(e))
        raise HTTPException(500, f"Error en análisis: {e}")


@app.post("/calibrate")
async def calibrate(req: CalibrateRequest):
    # ... implementación descrita en §8
    pass
```

---

## Apéndice D — `firebase_client.py` — Estructura base

```python
"""
backend_tem/firebase_client.py — Cliente Firebase (Firestore + Storage).
"""

import io
import numpy as np
import soundfile as sf
import firebase_admin
from firebase_admin import firestore, storage
from config import GCP_PROJECT, STORAGE_BUCKET

# Inicializar Firebase (Application Default Credentials en Cloud Run)
if not firebase_admin._apps:
    firebase_admin.initialize_app(options={"storageBucket": STORAGE_BUCKET})

class FirebaseClient:
    def __init__(self):
        self.db = firestore.client()
        self.bucket = storage.bucket()
    
    def read_attempt(self, session_id: str, attempt_id: str) -> dict:
        doc = self.db.collection("sesiones_TEM").document(session_id) \
                     .collection("attempts").document(attempt_id).get()
        if not doc.exists:
            raise ValueError(f"Attempt {attempt_id} no encontrado")
        return doc.to_dict()
    
    def read_stimulus(self, stimulus_id: str) -> dict:
        doc = self.db.collection("stimuli_TEM").document(stimulus_id).get()
        if not doc.exists:
            raise ValueError(f"Estímulo {stimulus_id} no encontrado")
        data = doc.to_dict()
        # Validar invariante
        n = len(data.get("syllables", []))
        assert len(data.get("onsets_ms", [])) == n
        assert len(data.get("durations_ms", [])) == n
        assert len(data.get("f0_template_hz", [])) == n
        return data
    
    def read_calibration(self, paciente_id: str) -> dict | None:
        """Lee calibración del paciente. Retorna None si no existe."""
        doc = self.db.collection("pacientes").document(paciente_id) \
                     .collection("calibracion").document("calibracion").get()
        if not doc.exists:
            # Intentar como documento directo (ambos formatos soportados)
            doc = self.db.collection("pacientes").document(paciente_id).get()
            data = doc.to_dict() if doc.exists else {}
            cal = data.get("calibracion")
            return cal if isinstance(cal, dict) else None
        return doc.to_dict()
    
    def download_wav(self, storage_path: str) -> tuple[np.ndarray, int]:
        """Descarga WAV de Storage y retorna (samples, sample_rate)."""
        blob = self.bucket.blob(storage_path)
        wav_bytes = blob.download_as_bytes()
        data, sr = sf.read(io.BytesIO(wav_bytes), dtype='float32')
        return data, sr
    
    def write_analysis_result(self, analysis_id: str, result: dict):
        result["analyzed_at"] = firestore.SERVER_TIMESTAMP
        self.db.collection("analysis_results_TEM").document(analysis_id).set(result)
    
    def update_attempt_analyzed(self, session_id: str, attempt_id: str, 
                                 analysis_id: str, clinical_score: int,
                                 is_intelligible: bool):
        self.db.collection("sesiones_TEM").document(session_id) \
               .collection("attempts").document(attempt_id) \
               .update({
                   "status": "analyzed",
                   "analysisId": analysis_id,
                   "clinical_score": clinical_score,
                   "is_intelligible": is_intelligible,
                   "analyzed_at": firestore.SERVER_TIMESTAMP
               })
    
    def update_attempt_error(self, session_id: str, attempt_id: str, error_msg: str):
        self.db.collection("sesiones_TEM").document(session_id) \
               .collection("attempts").document(attempt_id) \
               .update({
                   "status": "error",
                   "errorMessage": error_msg[:500]  # Limitar longitud
               })
    
    def write_calibration(self, paciente_id: str, calibration: dict):
        calibration["last_calibrated_at"] = firestore.SERVER_TIMESTAMP
        self.db.collection("pacientes").document(paciente_id) \
               .set({"calibracion": calibration}, merge=True)
```

---

*Documento generado para Sprint 2 del proyecto RehabilitIA — Módulo TEM*  
*Basado en el código fuente actual del Sprint 1 completado y el documento TEM_SPRINTS.md*
