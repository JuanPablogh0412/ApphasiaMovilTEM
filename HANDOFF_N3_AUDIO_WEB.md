# Handoff: Triple Audio para Estímulos de Nivel 3 (TEM)

> **Destinatario:** Agente de IA encargado del desarrollo de la aplicación web (React 19 + Vite)
> **Proyecto:** RehabilitIA — Plataforma de rehabilitación para pacientes con afasia
> **Módulo:** TEM (Terapia de Entonación Melódica) — Nivel Clínico 3
> **Firebase Project:** `apphasia-7a930`

---

## 1. Contexto Clínico — Por Qué Tres Audios

El protocolo MIT (Melodic Intonation Therapy) en su Nivel 3 introduce la transición progresiva desde el canto melódico hasta el habla espontánea. Cada fase del ejercicio utiliza un tipo de audio distinto como modelo para el paciente:

| Paso clínico | Nombre | Audio que escucha el paciente | Campo Firestore |
|---|---|---|---|
| P1 — Repetición diferida | `repeticion_diferida` | Melodía exagerada idéntica a N1/N2 | `audio_url` |
| P2 — Introducción sprechgesang | `sprechgesang_intro` | Melodía reducida ("cantado hablado") × 2 | `audio_url_sprechgesang` |
| P3 — Sprechgesang con apagado | `sprechgesang_fade` | Melodía reducida con fade al 50% | `audio_url_sprechgesang` |
| P4 — Repetición hablada | `repeticion_hablada` | Habla natural (sin melodía) como referencia | `audio_url_habla_normal` |
| P5 — Pregunta habla normal | `pregunta_n3` | Solo narración TTS de la pregunta | _(sin audio de estímulo)_ |

Sin los tres audios, los pasos P2, P3 y P4 no tienen modelo de referencia para el paciente, lo que invalida el protocolo clínico.

---

## 2. Cambio en el Modelo de Datos Firestore

### Colección `stimuli_TEM/{stimulusId}`

**Esquema actual** (niveles 1 y 2 — no modificar):

```jsonc
{
  "stimulusId": "ST_TEM_N1_001",
  "texto": "mamá",
  "syllables": ["ma", "má"],
  "onsets_ms": [0, 500],
  "durations_ms": [450, 450],
  "audio_duration_ms": 950,
  "audio_url": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N1_001_entonado.wav",
  "f0_template_hz": [180.0, 175.0],
  "nivel_clinico": 1,
  "patron_tonal": "LH",
  "num_silabas": 2,
  "categoria": "familia",
  "pregunta": "¿Quién te cuida?",
  "imagen_url": "gs://..."
}
```

**Esquema nuevo para `nivel_clinico: 3`** (añadir los dos campos marcados con ⭐):

```jsonc
{
  "stimulusId": "ST_TEM_N3_001",
  "texto": "mamá",
  "syllables": ["ma", "má"],
  "onsets_ms": [0, 500],
  "durations_ms": [450, 450],
  "audio_duration_ms": 950,                // ← Duración del audio ENTONADO (audio_url)

  "audio_url":              "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N3_001_entonado.wav",
  "audio_url_sprechgesang": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N3_001_sprechgesang.wav",  // ⭐ NUEVO
  "audio_url_habla_normal": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N3_001_habla.wav",         // ⭐ NUEVO

  "f0_template_hz": [180.0, 175.0],
  "nivel_clinico": 3,
  "patron_tonal": "LH",
  "num_silabas": 2,
  "categoria": "familia",
  "pregunta": "¿Quién te cuida?",
  "imagen_url": "gs://..."
}
```

> **Regla:** `audio_url_sprechgesang` y `audio_url_habla_normal` **solo existen en documentos con `nivel_clinico: 3`**. Los documentos N1 y N2 existentes **no se modifican**.

---

## 3. Firebase Storage — Convención de Nombres

Subir los tres archivos de audio WAV a la ruta:

```
gs://apphasia-7a930.firebasestorage.app/stimuli/audio/
```

| Audio | Sufijo de archivo | Ejemplo |
|---|---|---|
| Entonado | `_entonado.wav` | `ST_TEM_N3_001_entonado.wav` |
| Sprechgesang | `_sprechgesang.wav` | `ST_TEM_N3_001_sprechgesang.wav` |
| Habla normal | `_habla.wav` | `ST_TEM_N3_001_habla.wav` |

El `stimulusId` para estímulos N3 debe seguir el patrón `ST_TEM_N3_XXX` (ejemplo: `ST_TEM_N3_001`, `ST_TEM_N3_002`, ...).

**Formato de audio requerido:** WAV, 16 kHz, mono, 16-bit PCM (igual que N1/N2).

---

## 4. Cambios en el Formulario Web de Creación de Estímulos

### Comportamiento actual (N1/N2)

El formulario ya permite grabar un audio para `audio_url`. No cambiar nada para N1/N2.

### Nuevo comportamiento para N3

Cuando el usuario seleccione `nivel_clinico = 3`, mostrar tres slots de grabación **en orden secuencial**:

---

#### Slot 1 — Audio Entonado (`audio_url`)

**Etiqueta:** `Audio entonado (melodía completa)`

**Descripción visible al terapeuta:**
> "Pronuncia la frase con la melodía exagerada, igual que en los niveles 1 y 2. Este audio se usa en el Paso 1 del ejercicio."

**Obligatorio:** Sí

---

#### Slot 2 — Audio Sprechgesang (`audio_url_sprechgesang`)

**Etiqueta:** `Audio sprechgesang (melodía reducida)`

**Descripción visible al terapeuta:**
> "Pronuncia la frase con una melodía suavizada — como si cantaras de forma natural y relajada, sin la exageración del paso anterior. Este audio se usa en los Pasos 2 y 3."

**Obligatorio:** Sí

---

#### Slot 3 — Audio Habla Normal (`audio_url_habla_normal`)

**Etiqueta:** `Audio habla normal`

**Descripción visible al terapeuta:**
> "Pronuncia la frase con voz completamente natural, como en una conversación normal. Sin ninguna melodía. Este audio se usa en el Paso 4."

**Obligatorio:** Sí

---

### Validación antes de guardar

Para `nivel_clinico = 3`, los tres campos son **obligatorios**. Si alguno falta, mostrar error:
```
"Para estímulos de Nivel 3 son necesarios los tres audios: entonado, sprechgesang y habla normal."
```

Para `nivel_clinico = 1` o `2`, solo `audio_url` es obligatorio (comportamiento actual).

---

## 5. Flujo de Guardado — Lógica Paso a Paso

```
1. Terapeuta rellena el formulario y graba los 3 audios
2. Al hacer clic en "Guardar":
   a. Generar stimulusId: "ST_TEM_N3_" + secuencial con padding (ej: "ST_TEM_N3_001")
   b. Subir audio_url          → storage: stimuli/audio/{stimulusId}_entonado.wav
   c. Subir audio_url_sprechgesang → storage: stimuli/audio/{stimulusId}_sprechgesang.wav
   d. Subir audio_url_habla_normal → storage: stimuli/audio/{stimulusId}_habla.wav
   e. Escribir documento Firestore en stimuli_TEM/{stimulusId} con los campos del esquema
3. Mostrar confirmación al terapeuta
```

**Nota:** Para obtener el próximo número secuencial, consultar cuántos documentos existen con `nivel_clinico == 3` en `stimuli_TEM` y usar `count + 1` con padding de 3 dígitos.

---

## 6. Verificación — Checklist Post-Implementación

Después de implementar y grabar los estímulos, verificar en Firestore Console:

- [ ] Existe al menos un documento `stimuli_TEM/ST_TEM_N3_001`
- [ ] El documento tiene los campos `audio_url`, `audio_url_sprechgesang`, `audio_url_habla_normal` — ninguno vacío o `null`
- [ ] Los tres campos comienzan con `gs://apphasia-7a930.firebasestorage.app/`
- [ ] En Firebase Storage, existen los tres archivos `.wav` correspondientes
- [ ] El campo `nivel_clinico` del documento es `3`
- [ ] El campo `audio_duration_ms` refleja la duración del audio entonado

---

## 7. Referencia — Campos Completos del Documento N3

```jsonc
{
  // ── Identificación ────────────────────────────────────────────
  "stimulusId":    "ST_TEM_N3_001",         // String — ID único

  // ── Texto y sílabas ───────────────────────────────────────────
  "texto":         "mamá",                   // String — frase a practicar
  "syllables":     ["ma", "má"],             // Array<String>
  "onsets_ms":     [0, 500],                 // Array<int> — inicio de c/sílaba
  "durations_ms":  [450, 450],               // Array<int> — duración de c/sílaba
  "num_silabas":   2,                        // int

  // ── Temporización ─────────────────────────────────────────────
  "audio_duration_ms": 950,                  // int — duración del audio ENTONADO

  // ── Audios (⭐ los tres son obligatorios para N3) ─────────────
  "audio_url":              "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N3_001_entonado.wav",
  "audio_url_sprechgesang": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N3_001_sprechgesang.wav",
  "audio_url_habla_normal": "gs://apphasia-7a930.firebasestorage.app/stimuli/audio/ST_TEM_N3_001_habla.wav",

  // ── Pitch ─────────────────────────────────────────────────────
  "f0_template_hz": [180.0, 175.0],          // Array<double> — F0 esperado p/sílaba
  "patron_tonal":   "LH",                    // String — patrón tonal

  // ── Metadatos clínicos ────────────────────────────────────────
  "nivel_clinico":  3,                        // int — SIEMPRE 3 para estos docs
  "categoria":      "familia",               // String — categoría semántica

  // ── Pregunta (Paso 5) ─────────────────────────────────────────
  "pregunta": "¿Quién te cuida?",            // String — pregunta hablada en P5

  // ── Imagen (opcional) ─────────────────────────────────────────
  "imagen_url": ""                           // String — gs:// o vacío
}
```

---

## 8. Notas Adicionales

- **`audio_duration_ms`** siempre hace referencia a la duración del audio **entonado** (`audio_url`), que es la referencia temporal para el metrónomo del Paso 1.
- **El Paso 5** no usa ninguno de los tres audios del estímulo — solo reproduce la narración TTS de la `pregunta`. No hay campo `audio_url_pregunta`.
- **Los estímulos N1/N2 existentes no se migran** — la app móvil lee `audio_url_sprechgesang` y `audio_url_habla_normal` solo cuando `nivelActual == 3`.
- El campo `pregunta_tts_key` (clave TTS de la pregunta) se genera automáticamente por el script `scripts/migrate_stimuli_tts.py` — ejecutarlo después de crear los estímulos N3 si se necesita narración de la pregunta.
