# Firestore Seed — Módulo TEM

Datos mock para desarrollo del Sprint 1.  
Subir manualmente desde la **Consola de Firebase → Firestore → Add document**.

> **Nota:** No se incluye `viseme_timeline` ni `haptic_pattern_ms`.  
> Flutter los calcula internamente con `syllabify()` + `generateTimeline()`.

---

## Colección: `stimuli_TEM`

Subir 5 documentos con Document ID = stimulusId (p. ej. `ST_TEM_MOCK_001`).

```json
ST_TEM_MOCK_001
{
  "stimulusId":   "ST_TEM_MOCK_001",
  "texto":        "mama",
  "syllables":    ["ma", "ma"],
  "onsets_ms":    [0, 500],
  "durations_ms": [450, 450],
  "audio_url":    "",
  "f0_template_hz": [180.0, 175.0],
  "nivel_clinico": 1,
  "fase":         "union_ritmica",
  "imageUrl":     ""
}

ST_TEM_MOCK_002
{
  "stimulusId":   "ST_TEM_MOCK_002",
  "texto":        "papa",
  "syllables":    ["pa", "pa"],
  "onsets_ms":    [0, 500],
  "durations_ms": [450, 450],
  "audio_url":    "",
  "f0_template_hz": [175.0, 170.0],
  "nivel_clinico": 1,
  "fase":         "union_ritmica",
  "imageUrl":     ""
}

ST_TEM_MOCK_003
{
  "stimulusId":   "ST_TEM_MOCK_003",
  "texto":        "carro",
  "syllables":    ["ca", "rro"],
  "onsets_ms":    [0, 420],
  "durations_ms": [380, 600],
  "audio_url":    "",
  "f0_template_hz": [185.0, 160.0],
  "nivel_clinico": 2,
  "fase":         "union_ritmica",
  "imageUrl":     ""
}

ST_TEM_MOCK_004
{
  "stimulusId":   "ST_TEM_MOCK_004",
  "texto":        "casa",
  "syllables":    ["ca", "sa"],
  "onsets_ms":    [0, 400],
  "durations_ms": [360, 360],
  "audio_url":    "",
  "f0_template_hz": [185.0, 165.0],
  "nivel_clinico": 1,
  "fase":         "union_ritmica",
  "imageUrl":     ""
}

ST_TEM_MOCK_005
{
  "stimulusId":   "ST_TEM_MOCK_005",
  "texto":        "agua",
  "syllables":    ["a", "gua"],
  "onsets_ms":    [0, 350],
  "durations_ms": [300, 600],
  "audio_url":    "",
  "f0_template_hz": [170.0, 155.0],
  "nivel_clinico": 1,
  "fase":         "union_ritmica",
  "imageUrl":     ""
}
```

---

## Colección: `ejercicios_TEM`

Un documento por cada estímulo.  
Document ID sugerido: `E_TEM_MOCK_001` … `E_TEM_MOCK_005`.

```json
E_TEM_MOCK_001
{
  "ejercicioId":  "E_TEM_MOCK_001",
  "stimulusId":   "ST_TEM_MOCK_001",
  "terapia":      "TEM",
  "nivel_clinico": 1,
  "fase":         "union_ritmica",
  "pasos_completados": 0,
  "estado":       "pendiente",
  "personalizado": false
}
```
Repetir para MOCK_002 … MOCK_005 cambiando los IDs y estimulusId correspondientes.

---

## Colección: `pacientes/{pacienteId}/ejercicios_asignados`

Asignar los 5 ejercicios al paciente de prueba.  
Reemplazar `{pacienteId}` con el UID real del paciente de prueba en Firebase Auth.

```json
{
  "ejercicioId": "E_TEM_MOCK_001",
  "stimulusId":  "ST_TEM_MOCK_001",
  "terapia":     "TEM",
  "estado":      "pendiente",
  "nivel_clinico": 1
}
```
Repetir para los 5 ejercicios.

---

## Documento: `pacientes/{pacienteId}/calibracion`

Valores de calibración por defecto (antes de realizar la calibración real en Sprint 3):

```json
{
  "f0_min":    100,
  "f0_max":    300,
  "f0_comfort": 180,
  "avg_syllable_duration_ms": 450,
  "offset_ms": 0,
  "last_calibrated_at": null
}
```

---

## Invariante a respetar siempre

```
syllables.length == onsets_ms.length == durations_ms.length
```

Si no se cumple → `LipTimeline.fromStimulusJson()` lanza `ArgumentError`.
