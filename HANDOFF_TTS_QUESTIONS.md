# TTS Handoff — RehabilitIA

## Resumen

Se añadió narración TTS (Text-to-Speech) a todas las pantallas TEM para
pacientes con afasia. Los audios se pre-generan como MP3 con Google Cloud
WaveNet y se almacenan en Firebase Storage.

---

## Pasos para activar TTS

### 1. Requisitos

```bash
pip install google-cloud-texttospeech firebase-admin
```

Tener una service account con permisos de **Cloud Text-to-Speech** y
**Firebase Storage Admin**.

```bash
export GOOGLE_APPLICATION_CREDENTIALS=path/to/sa.json
```

### 2. Generar audios estáticos (pantallas)

```bash
cd scripts/
python generate_tts.py
```

Esto genera ~86 MP3s (43 textos × 2 voces) y los sube a
`gs://apphasia-7a930.firebasestorage.app/tts/{female|male}/{key}.mp3`.

Para generar solo en local sin subir:

```bash
python generate_tts.py --local-only
```

### 3. Migrar estímulos existentes en Firestore

```bash
python migrate_stimuli_tts.py
```

Esto hace:
1. Renombra `pregunta_texto` → `pregunta` (bug-fix del seed)
2. Genera TTS para cada pregunta de estímulo
3. Escribe `pregunta_tts_key` en cada documento

Dry-run primero:
```bash
python migrate_stimuli_tts.py --dry-run
```

### 4. Verificar en la app

1. Abrir la app → TEM → activar el toggle de narración
2. Los audios deben reproducirse automáticamente al navegar entre pantallas
3. El selector Femenina/Masculina cambia la voz

---

## Arquitectura

```
Firebase Storage
└── tts/
    ├── female/
    │   ├── home_bienvenida.mp3
    │   ├── calib_intro.mp3
    │   ├── q_stim_001.mp3     ← preguntas por estímulo
    │   └── ...
    └── male/
        └── ... (mismo set)

Firestore
└── pacientes/{uid}
    ├── tts_enabled: bool
    └── tts_voice: "female" | "male"
└── stimuli_TEM/{id}
    ├── pregunta: "¿Eso que dijiste fue 'mamá'?"
    └── pregunta_tts_key: "q_stim_001"
```

### NarrationService (Flutter)

- Ubicación: `lib/services/tem/narration_service.dart`
- Usa `just_audio` con AudioPlayer independiente
- API: `speak(key)`, `speakAndWait(key)`, `speakUrl(url)`, `stop()`
- Cachea URLs de Storage para evitar lookups repetidos
- Preferencia de voz persistida en Firestore

---

## Catálogo de claves TTS

Ver `scripts/tts_texts.json` para el listado completo de ~43 textos.

Prefijos:
| Prefijo | Pantalla |
|---------|----------|
| `home_` | TEM Home |
| `pre_session_` | Pre-sesión |
| `tutorial_` | Tutorial carousel |
| `calib_` | Calibración |
| `exercise_` | Ejercicios N1 |
| `n2_` | Ejercicios N2 |
| `summary_` | Resumen |

---

## Bug corregido

`scripts/seed_stimuli.js` escribía el campo `pregunta_texto` en Firestore,
pero la app Flutter leía `pregunta`. Corregido: ahora el seed escribe
`pregunta`. La migración renombra documentos existentes.

---

## Costos

Google Cloud TTS WaveNet: **4 millones de caracteres gratis/mes**.
Los ~43 textos × 2 voces consumen ~6,000 caracteres (muy por debajo).
Las preguntas de estímulos son ~50 chars cada una.
