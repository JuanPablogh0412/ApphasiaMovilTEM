#!/usr/bin/env python3
"""
align_stimuli.py — Forced alignment automático para estímulos TEM.

Qué hace:
  1. Carga cada WAV de scripts/wavs/
  2. Usa Whisper (modelo "small") con word_timestamps=True para obtener
     los tiempos exactos de inicio/fin de cada PALABRA en el audio real.
  3. Distribuye esos tiempos a nivel de SÍLABA: dentro de cada palabra,
     las sílabas se espacian proporcionalmente según su posición.
  4. Guarda el resultado en scripts/alignments.json
  5. Actualiza los documentos en Firestore (stimuli_TEM/{id}) con los
     nuevos onsets_ms, durations_ms y audio_duration_ms correctos.

Instalación (solo la primera vez):
  pip install openai-whisper firebase-admin

Cómo correr:
  cd scripts
  python align_stimuli.py

Escalabilidad:
  - Funciona para cualquier estímulo: monosílabos, bisílabas, frases completas.
  - Para Nivel 2/3 simplemente agrega los WAVs a la carpeta wavs/ y
    actualiza STIMULI_CATALOG con las sílabas correspondientes.
  - El modelo "small" (244M) es preciso en español. Si necesitas más
    velocidad usa "tiny"; si necesitas más precisión usa "medium".
"""

import json
import os
import sys
import math

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly
from math import gcd

# ---------------------------------------------------------------------------
# Catálogo de estímulos — sílabas y palabras por estímulo
# Debe mantenerse sincronizado con el catálogo en seed_stimuli.js
# ---------------------------------------------------------------------------
STIMULI_CATALOG = [
    {"id": "ST_TEM_N1_001", "texto": "mamá",    "syllables": ["ma", "má"],        "words": [["ma", "má"]]},
    {"id": "ST_TEM_N1_002", "texto": "papá",    "syllables": ["pa", "pá"],        "words": [["pa", "pá"]]},
    {"id": "ST_TEM_N1_003", "texto": "agua",    "syllables": ["a", "gua"],        "words": [["a", "gua"]]},
    {"id": "ST_TEM_N1_004", "texto": "no sé",   "syllables": ["no", "sé"],        "words": [["no"], ["sé"]]},
    {"id": "ST_TEM_N1_005", "texto": "ayuda",   "syllables": ["a", "yu", "da"],   "words": [["a", "yu", "da"]]},
    {"id": "ST_TEM_N1_006", "texto": "gracias", "syllables": ["gra", "cias"],     "words": [["gra", "cias"]]},
    {"id": "ST_TEM_N1_007", "texto": "casa",    "syllables": ["ca", "sa"],        "words": [["ca", "sa"]]},
    {"id": "ST_TEM_N1_008", "texto": "hambre",  "syllables": ["ham", "bre"],      "words": [["ham", "bre"]]},
    {"id": "ST_TEM_N1_009", "texto": "dolor",   "syllables": ["do", "lor"],       "words": [["do", "lor"]]},
    {"id": "ST_TEM_N1_010", "texto": "bien",    "syllables": ["bien"],            "words": [["bien"]]},
]

WAVS_DIR            = os.path.join(os.path.dirname(__file__), "wavs")
OUTPUT_JSON         = os.path.join(os.path.dirname(__file__), "alignments.json")
SERVICE_ACCOUNT_KEY = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
FIRESTORE_COLLECTION = "stimuli_TEM"
WHISPER_MODEL        = "small"   # tiny | small | medium | large

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_wav_duration_ms(path: str) -> int:
    """Lee la duración exacta del WAV desde el header binario (sin librerías)."""
    with open(path, "rb") as f:
        data = f.read()
    if data[0:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"No es un archivo RIFF/WAVE: {path}")
    offset = 12
    byte_rate = 0
    data_bytes = 0
    while offset < len(data) - 8:
        chunk_id   = data[offset:offset+4].decode("ascii", errors="replace")
        chunk_size = int.from_bytes(data[offset+4:offset+8], "little")
        if chunk_id == "fmt ":
            byte_rate = int.from_bytes(data[offset+16:offset+20], "little")
        elif chunk_id == "data":
            data_bytes = chunk_size
            break
        offset += 8 + chunk_size + (chunk_size % 2)
    if byte_rate == 0 or data_bytes == 0:
        raise ValueError(f"No se pudo leer fmt/data en: {path}")
    return round((data_bytes / byte_rate) * 1000)


def distribute_syllables_in_word(syllables: list, word_start_ms: int, word_end_ms: int) -> list:
    """
    Distribuye N sílabas proporcionalmente dentro del rango [word_start_ms, word_end_ms].
    Devuelve lista de dicts: [{onset_ms, duration_ms}, ...]
    """
    n = len(syllables)
    if n == 0:
        return []
    span = word_end_ms - word_start_ms
    if span <= 0:
        # Caso degenerado: sílabas punt sobre el mismo punto
        return [{"onset_ms": word_start_ms, "duration_ms": 50} for _ in syllables]

    spacing = span / n
    result = []
    for i, _ in enumerate(syllables):
        onset_ms = round(word_start_ms + i * spacing)
        if i < n - 1:
            # Gap de 10ms entre sílabas (transición natural)
            duration_ms = max(30, round(spacing) - 10)
        else:
            # Última sílaba llega hasta el fin de la palabra
            duration_ms = word_end_ms - onset_ms
        result.append({"onset_ms": onset_ms, "duration_ms": max(30, duration_ms)})
    return result


WHISPER_SAMPLE_RATE = 16000  # Hz requeridos por Whisper


def load_audio_for_whisper(path: str) -> np.ndarray:
    """
    Carga un WAV, lo convierte a mono float32 y lo remuestrea a 16 kHz.
    Funciona sin ffmpeg usando solo scipy.
    """
    sample_rate, data = wavfile.read(path)

    # Convertir a float32 normalizado [-1, 1]
    if data.dtype == np.int16:
        audio = data.astype(np.float32) / 32768.0
    elif data.dtype == np.int32:
        audio = data.astype(np.float32) / 2147483648.0
    elif data.dtype == np.uint8:
        audio = (data.astype(np.float32) - 128.0) / 128.0
    else:  # ya es float
        audio = data.astype(np.float32)

    # Convertir estéreo → mono promediando canales
    if audio.ndim == 2:
        audio = audio.mean(axis=1)

    # Remuestrear a 16 kHz si hace falta
    if sample_rate != WHISPER_SAMPLE_RATE:
        common = gcd(sample_rate, WHISPER_SAMPLE_RATE)
        up   = WHISPER_SAMPLE_RATE // common
        down = sample_rate          // common
        audio = resample_poly(audio, up, down).astype(np.float32)

    return audio


def align_stimulus(stim: dict, model, wav_path: str) -> dict:
    """
    Corre Whisper sobre el WAV y alinea las sílabas con los timestamps de palabra.
    Devuelve un dict con: onsets_ms, durations_ms, audio_duration_ms.
    """
    print(f"\n🎙  Alineando {stim['id']} — \"{stim['texto']}\"")

    audio_duration_ms = read_wav_duration_ms(wav_path)
    print(f"   Duración del WAV: {audio_duration_ms} ms")

    # Cargar audio sin ffmpeg y transcribir con word-level timestamps
    audio_array = load_audio_for_whisper(wav_path)
    result = model.transcribe(
        audio_array,
        language="es",
        word_timestamps=True,
        verbose=False,
        condition_on_previous_text=False,
    )

    # Extraer palabras con timestamps
    whisper_words = []
    for seg in result.get("segments", []):
        for w in seg.get("words", []):
            word_text = w.get("word", "").strip().lower()
            if word_text:
                whisper_words.append({
                    "word": word_text,
                    "start_ms": round(w["start"] * 1000),
                    "end_ms":   round(w["end"]   * 1000),
                })

    print(f"   Whisper detectó {len(whisper_words)} palabra(s): "
          f"{[(w['word'], w['start_ms'], w['end_ms']) for w in whisper_words]}")

    # ---------- Mapear palabras → grupos de sílabas ----------
    # Si Whisper devuelve el mismo número de palabras que el catálogo, usamos
    # los timestamps directamente. Si no coincide (ruido, énfasis, etc.),
    # repartimos todo el span detectado proporcionalmente.
    words_catalog = stim["words"]  # ej: [["ma", "má"]] o [["no"], ["sé"]]
    num_catalog_words = len(words_catalog)

    all_syllable_timings = []

    if len(whisper_words) == num_catalog_words:
        # Caso ideal: coincide número de palabras
        for wi, (catalog_word_sylls, whisper_word) in enumerate(
                zip(words_catalog, whisper_words)):
            word_end = whisper_word["end_ms"]
            # Para la última palabra: extender hasta el final real del audio.
            # Whisper trunca el fin de palabras con fricativa/sibilante final
            # (ej. "gracias" → "s") dejando un hueco de silencio en la
            # animación. Solo se aplica si el gap es ≤ 400 ms para no
            # distorsionar silencios intencionales largos.
            if wi == num_catalog_words - 1:
                candidate = audio_duration_ms - 30   # pequeño margen de cola
                if 0 < candidate - word_end:
                    word_end = candidate
                    print(f"   ↑ end_ms extendido a {word_end} ms (cubrir audio completo)")
            timings = distribute_syllables_in_word(
                catalog_word_sylls,
                whisper_word["start_ms"],
                word_end,
            )
            all_syllable_timings.extend(timings)
            print(f"   Palabra '{whisper_word['word']}' "
                  f"[{whisper_word['start_ms']}–{word_end} ms] "
                  f"→ {len(catalog_word_sylls)} sílaba(s)")
    else:
        # Fallback: usar el span total de lo que Whisper detectó y distribuir
        # todas las sílabas dentro de ese span
        print(f"   ⚠ Whisper devolvió {len(whisper_words)} palabra(s), "
              f"catálogo tiene {num_catalog_words}. Usando span total.")

        if whisper_words:
            span_start = whisper_words[0]["start_ms"]
            span_end   = whisper_words[-1]["end_ms"]
            # Igual que en el caso ideal: extender al audio real
            candidate = audio_duration_ms - 30
            if 0 < candidate - span_end:
                span_end = candidate
                print(f"   ↑ span_end extendido a {span_end} ms (cubrir audio completo)")
        else:
            # Whisper no detectó nada — usar la duración completa con margen
            margin = min(80, round(audio_duration_ms * 0.08))
            span_start = margin
            span_end   = audio_duration_ms - margin

        all_sylls = stim["syllables"]
        timings = distribute_syllables_in_word(all_sylls, span_start, span_end)
        all_syllable_timings.extend(timings)

    onsets_ms    = [t["onset_ms"]    for t in all_syllable_timings]
    durations_ms = [t["duration_ms"] for t in all_syllable_timings]

    print(f"   ✅ onsets_ms:    {onsets_ms}")
    print(f"   ✅ durations_ms: {durations_ms}")
    print(f"   ✅ audio_duration_ms: {audio_duration_ms}")

    return {
        "id":                stim["id"],
        "onsets_ms":         onsets_ms,
        "durations_ms":      durations_ms,
        "audio_duration_ms": audio_duration_ms,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    # -- Verificar dependencias --
    try:
        import whisper
    except ImportError:
        print("❌ openai-whisper no está instalado.")
        print("   Instálalo con:  pip install openai-whisper")
        sys.exit(1)

    has_firebase = os.path.exists(SERVICE_ACCOUNT_KEY)
    if has_firebase:
        try:
            import firebase_admin
            from firebase_admin import credentials, firestore
        except ImportError:
            print("⚠  firebase-admin no está instalado. Solo se guardará alignments.json.")
            print("   Para actualizar Firestore: pip install firebase-admin")
            has_firebase = False

    # -- Cargar modelo Whisper --
    print(f"\n📦 Cargando modelo Whisper '{WHISPER_MODEL}' (primera vez puede tardar)...")
    model = whisper.load_model(WHISPER_MODEL)
    print("   ✅ Modelo cargado.")

    # -- Inicializar Firebase si está disponible --
    db = None
    if has_firebase:
        import firebase_admin
        from firebase_admin import credentials, firestore as fs_module
        if not firebase_admin._apps:
            cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
            firebase_admin.initialize_app(cred)
        db = fs_module.client()
        print("✅ Firebase Admin inicializado.")

    # -- Procesar cada estímulo --
    alignments = {}
    skipped = []

    for stim in STIMULI_CATALOG:
        wav_path = os.path.join(WAVS_DIR, f"{stim['id']}.wav")
        if not os.path.exists(wav_path):
            print(f"\n⏭  Saltando {stim['id']} — WAV no encontrado: {wav_path}")
            skipped.append(stim["id"])
            continue

        alignment = align_stimulus(stim, model, wav_path)
        alignments[stim["id"]] = alignment

        # Actualizar Firestore
        if db is not None:
            doc_ref = db.collection(FIRESTORE_COLLECTION).document(stim["id"])
            doc_ref.update({
                "onsets_ms":         alignment["onsets_ms"],
                "durations_ms":      alignment["durations_ms"],
                "audio_duration_ms": alignment["audio_duration_ms"],
            })
            print(f"   🔥 Firestore actualizado: {FIRESTORE_COLLECTION}/{stim['id']}")

    # -- Guardar alignments.json --
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(alignments, f, indent=2, ensure_ascii=False)
    print(f"\n✅ alignments.json guardado en: {OUTPUT_JSON}")

    # -- Resumen --
    print("\n═══════════════════════════════════════")
    print(f"🎉 Completado: {len(alignments)} estímulos alineados")
    if skipped:
        print(f"   Faltantes: {skipped}")
    print("═══════════════════════════════════════\n")


if __name__ == "__main__":
    main()
