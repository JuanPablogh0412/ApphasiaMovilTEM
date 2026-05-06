#!/usr/bin/env python3
"""
generate_tts.py — Genera audios TTS con Google Cloud WaveNet.

Lee scripts/tts_texts.json, genera MP3 para cada entrada con 2 voces
(femenina / masculina) y sube los archivos a Firebase Storage.

Requisitos:
  pip install google-cloud-texttospeech google-cloud-storage

Uso:
  # Generar todos los audios y subirlos a Storage:
  python scripts/generate_tts.py

  # Solo generar localmente (sin subir):
  python scripts/generate_tts.py --local-only

  # Regenerar una clave específica:
  python scripts/generate_tts.py --key home_bienvenida
"""

import argparse
import json
import os
import sys
from pathlib import Path

from google.cloud import texttospeech
from google.cloud import storage

# ── Configuración ──────────────────────────────────────────────────────────

BUCKET_NAME = "apphasia-7a930.firebasestorage.app"
VOICES = {
    "female": "es-US-Wavenet-A",
    "male": "es-US-Wavenet-B",
}
STORAGE_PREFIX = "tts"          # tts/{female|male}/{key}.mp3
LOCAL_OUTPUT_DIR = Path(__file__).parent / "tts_output"
TEXTS_FILE = Path(__file__).parent / "tts_texts.json"

# ── Helpers ────────────────────────────────────────────────────────────────


def load_texts(path: Path, key_filter: str | None = None) -> dict[str, str]:
    """Lee el JSON maestro, ignora claves que empiezan con '_'."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    texts = {k: v for k, v in data.items() if not k.startswith("_")}
    if key_filter:
        if key_filter not in texts:
            print(f"ERROR: clave '{key_filter}' no encontrada en {path.name}")
            sys.exit(1)
        texts = {key_filter: texts[key_filter]}
    return texts


def synthesize(client: texttospeech.TextToSpeechClient,
               text: str,
               voice_name: str) -> bytes:
    """Llama a Google Cloud TTS y devuelve bytes MP3."""
    synthesis_input = texttospeech.SynthesisInput(text=text)
    voice = texttospeech.VoiceSelectionParams(
        language_code="es-US",
        name=voice_name,
    )
    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.MP3,
        speaking_rate=0.85,       # ligeramente más lento para afasia
        pitch=0.0,
    )
    response = client.synthesize_speech(
        input=synthesis_input, voice=voice, audio_config=audio_config
    )
    return response.audio_content


def upload_to_storage(bucket, local_path: Path, storage_path: str) -> str:
    """Sube archivo a Firebase Storage y devuelve URL pública."""
    blob = bucket.blob(storage_path)
    blob.upload_from_filename(str(local_path), content_type="audio/mpeg")
    blob.make_public()
    return blob.public_url


# ── Main ──────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(description="Genera audios TTS WaveNet")
    parser.add_argument("--local-only", action="store_true",
                        help="Solo genera archivos locales, no sube a Storage")
    parser.add_argument("--key", type=str, default=None,
                        help="Genera solo una clave específica")
    args = parser.parse_args()

    texts = load_texts(TEXTS_FILE, args.key)
    print(f"Textos a procesar: {len(texts)}")

    # Crear cliente TTS
    tts_client = texttospeech.TextToSpeechClient()

    # Cliente de Storage (solo si vamos a subir)
    bucket = None
    if not args.local_only:
        storage_client = storage.Client()
        bucket = storage_client.bucket(BUCKET_NAME)

    # Crear directorio de salida local
    LOCAL_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    total = len(texts) * len(VOICES)
    done = 0

    for key, text in texts.items():
        for voice_label, voice_name in VOICES.items():
            done += 1
            filename = f"{key}.mp3"
            local_dir = LOCAL_OUTPUT_DIR / voice_label
            local_dir.mkdir(parents=True, exist_ok=True)
            local_path = local_dir / filename

            # Generar audio
            print(f"[{done}/{total}] {voice_label}/{filename}: \"{text[:50]}...\"")
            audio_bytes = synthesize(tts_client, text, voice_name)
            local_path.write_bytes(audio_bytes)

            # Subir a Storage
            if bucket:
                storage_path = f"{STORAGE_PREFIX}/{voice_label}/{filename}"
                url = upload_to_storage(bucket, local_path, storage_path)
                print(f"  → {url}")

    print(f"\n✅ {done} audios generados.")
    if args.local_only:
        print(f"   Archivos en: {LOCAL_OUTPUT_DIR}")
    else:
        print(f"   Subidos a gs://{BUCKET_NAME}/{STORAGE_PREFIX}/")


if __name__ == "__main__":
    main()
