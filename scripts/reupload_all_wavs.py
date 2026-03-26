#!/usr/bin/env python3
"""
reupload_all_wavs.py — Re-sube todos los WAVs recortados a Firebase Storage
y actualiza Firestore con los nuevos tiempos de alineación Whisper.

Qué hace:
  1. Para cada WAV en scripts/wavs/ que esté en el catálogo:
     a. Corre Whisper para obtener timestamps de palabras.
     b. Distribuye los tiempos a nivel de sílaba.
     c. Sube el WAV a gs://.../tem/audio/{id}.wav (sobreescribe el anterior).
     d. Actualiza stimuli_TEM/{id} en Firestore con los nuevos
        onsets_ms, durations_ms, audio_duration_ms y audio_url.

Cómo correr:
  cd scripts
  python reupload_all_wavs.py
"""

import os
import sys

_here = os.path.dirname(__file__)
sys.path.insert(0, _here)

from align_stimuli import (
    STIMULI_CATALOG,
    WAVS_DIR,
    WHISPER_MODEL,
    SERVICE_ACCOUNT_KEY,
    read_wav_duration_ms,
    load_audio_for_whisper,
    distribute_syllables_in_word,
)

PROJECT_ID   = "apphasia-7a930"
BUCKET_NEW   = f"{PROJECT_ID}.firebasestorage.app"
BUCKET_OLD   = f"{PROJECT_ID}.appspot.com"
STORAGE_DIR  = "tem/audio"
FIRESTORE_COLLECTION = "stimuli_TEM"


# ---------------------------------------------------------------------------
# Alineación (igual que align_stimulus pero con extensión sin cap de 400ms)
# ---------------------------------------------------------------------------

def align_and_upload(stim: dict, model, bucket, bucket_name: str, db):
    wav_path = os.path.join(WAVS_DIR, f"{stim['id']}.wav")
    if not os.path.exists(wav_path):
        print(f"  ⏭  {stim['id']} — WAV no encontrado, saltando.")
        return None

    print(f"\n📦 {stim['id']}  \"{stim['texto']}\"")

    # ── Duración real del WAV ──────────────────────────────────────────────
    audio_duration_ms = read_wav_duration_ms(wav_path)
    print(f"   Duración WAV: {audio_duration_ms} ms")

    # ── Whisper ───────────────────────────────────────────────────────────
    audio_array = load_audio_for_whisper(wav_path)
    result = model.transcribe(
        audio_array,
        language="es",
        word_timestamps=True,
        verbose=False,
        condition_on_previous_text=False,
    )
    whisper_words = []
    for seg in result.get("segments", []):
        for w in seg.get("words", []):
            word_text = w.get("word", "").strip().lower()
            if word_text:
                whisper_words.append({
                    "word":     word_text,
                    "start_ms": round(w["start"] * 1000),
                    "end_ms":   round(w["end"]   * 1000),
                })
    print(f"   Whisper: {[(w['word'], w['start_ms'], w['end_ms']) for w in whisper_words]}")

    # ── Distribución de sílabas ───────────────────────────────────────────
    words_catalog      = stim["words"]
    num_catalog_words  = len(words_catalog)
    all_timings        = []

    if len(whisper_words) == num_catalog_words:
        for wi, (sylls, ww) in enumerate(zip(words_catalog, whisper_words)):
            word_end = ww["end_ms"]
            # Última palabra: extender siempre hasta el final del WAV
            if wi == num_catalog_words - 1:
                candidate = audio_duration_ms - 30
                if candidate > word_end:
                    word_end = candidate
            all_timings.extend(
                distribute_syllables_in_word(sylls, ww["start_ms"], word_end)
            )
            print(f"   '{ww['word']}' [{ww['start_ms']}–{word_end} ms] → {len(sylls)} sílaba(s)")
    else:
        print(f"   ⚠ Whisper={len(whisper_words)} palabras vs catálogo={num_catalog_words}. Usando span total.")
        if whisper_words:
            span_s = whisper_words[0]["start_ms"]
            span_e = whisper_words[-1]["end_ms"]
            candidate = audio_duration_ms - 30
            if candidate > span_e:
                span_e = candidate
        else:
            margin = min(80, round(audio_duration_ms * 0.08))
            span_s = margin
            span_e = audio_duration_ms - margin
        all_timings.extend(
            distribute_syllables_in_word(stim["syllables"], span_s, span_e)
        )

    onsets_ms    = [t["onset_ms"]    for t in all_timings]
    durations_ms = [t["duration_ms"] for t in all_timings]
    print(f"   onsets_ms:    {onsets_ms}")
    print(f"   durations_ms: {durations_ms}")

    # ── Subir WAV a Storage ───────────────────────────────────────────────
    storage_path = f"{STORAGE_DIR}/{stim['id']}.wav"
    blob = bucket.blob(storage_path)
    blob.upload_from_filename(wav_path, content_type="audio/wav")
    audio_url = f"gs://{bucket_name}/{storage_path}"
    print(f"   ✅ Storage → {audio_url}")

    # ── Actualizar Firestore ──────────────────────────────────────────────
    db.collection(FIRESTORE_COLLECTION).document(stim["id"]).update({
        "onsets_ms":         onsets_ms,
        "durations_ms":      durations_ms,
        "audio_duration_ms": audio_duration_ms,
        "audio_url":         audio_url,
    })
    print(f"   🔥 Firestore → {FIRESTORE_COLLECTION}/{stim['id']}")
    return stim["id"]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    # -- Dependencias --
    try:
        import whisper
    except ImportError:
        print("❌ openai-whisper no instalado.  pip install openai-whisper")
        sys.exit(1)

    if not os.path.exists(SERVICE_ACCOUNT_KEY):
        print("❌ No se encontró serviceAccountKey.json en scripts/")
        sys.exit(1)

    import firebase_admin
    from firebase_admin import credentials, firestore, storage as fb_storage

    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
        firebase_admin.initialize_app(cred, {"storageBucket": BUCKET_NEW})
    db = firestore.client()

    # -- Auto-detectar bucket --
    bucket = bucket_name = None
    for name in (BUCKET_NEW, BUCKET_OLD):
        try:
            b = fb_storage.bucket(name)
            b.reload()
            bucket, bucket_name = b, name
            print(f"✅ Bucket: {name}")
            break
        except Exception:
            pass
    if bucket is None:
        print("❌ No se pudo conectar a Firebase Storage.")
        sys.exit(1)

    # -- Cargar Whisper --
    print(f"\n📦 Cargando modelo Whisper '{WHISPER_MODEL}'...")
    model = whisper.load_model(WHISPER_MODEL)
    print("   ✅ Listo.\n")

    # -- Procesar todos los estímulos --
    ok, skipped = [], []
    for stim in STIMULI_CATALOG:
        result = align_and_upload(stim, model, bucket, bucket_name, db)
        (ok if result else skipped).append(stim["id"])

    # -- Resumen --
    print("\n═══════════════════════════════════════")
    print(f"🎉 {len(ok)} estímulos re-subidos: {ok}")
    if skipped:
        print(f"   Faltantes (sin WAV): {skipped}")
    print("═══════════════════════════════════════\n")


if __name__ == "__main__":
    main()
