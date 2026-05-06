#!/usr/bin/env python3
"""
backfill_n3_pregunta_tts.py
----------------------------
Para cada doc N3 que tiene campo 'pregunta' pero no 'pregunta_tts_key':
  1. Genera audio TTS (female + male) con Google Cloud WaveNet.
  2. Sube los MP3 a Firebase Storage bajo tts/{voice}/q_{doc_id}.mp3.
  3. Escribe pregunta_tts_key = "q_{doc_id}" en el doc Firestore.

Uso:
  python scripts/backfill_n3_pregunta_tts.py --dry-run   # solo imprime
  python scripts/backfill_n3_pregunta_tts.py             # ejecuta
  python scripts/backfill_n3_pregunta_tts.py --force     # sobreescribir si ya tiene key
"""

import argparse
import sys
import tempfile
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore, storage as fb_storage
from google.cloud import texttospeech
from google.cloud import storage as gcs_storage

# ── Configuración ──────────────────────────────────────────────────────────

SERVICE_ACCOUNT_PATH = "scripts/serviceAccountKey.json"
COLLECTION = "stimuli_TEM"
BUCKET_NAME = "apphasia-7a930.firebasestorage.app"
VOICES = {
    "female": "es-US-Wavenet-A",
    "male":   "es-US-Wavenet-B",
}


# ── Helpers ────────────────────────────────────────────────────────────────

def synthesize(client: texttospeech.TextToSpeechClient, text: str, voice_name: str) -> bytes:
    """Genera audio MP3 desde texto con Google Cloud TTS."""
    synthesis_input = texttospeech.SynthesisInput(text=text)
    voice = texttospeech.VoiceSelectionParams(
        language_code="es-US",
        name=voice_name,
    )
    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.MP3,
        speaking_rate=0.85,
        pitch=0.0,
    )
    response = client.synthesize_speech(
        input=synthesis_input, voice=voice, audio_config=audio_config
    )
    return response.audio_content


def upload_bytes(bucket, mp3_bytes: bytes, storage_path: str) -> str:
    """Sube bytes MP3 a Firebase Storage y devuelve URL pública."""
    blob = bucket.blob(storage_path)
    blob.upload_from_string(mp3_bytes, content_type="audio/mpeg")
    blob.make_public()
    return blob.public_url


# ── Main ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Genera TTS para preguntas N3")
    parser.add_argument("--dry-run", action="store_true", help="Solo imprime, no escribe")
    parser.add_argument("--force",   action="store_true", help="Sobreescribir si ya tiene pregunta_tts_key")
    args = parser.parse_args()

    # Firebase Admin
    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred, {"storageBucket": BUCKET_NAME})
    db  = firestore.client()

    # Google Cloud TTS + Storage
    tts_client     = texttospeech.TextToSpeechClient()
    storage_client = gcs_storage.Client()
    bucket         = storage_client.bucket(BUCKET_NAME)

    # Obtener docs N3
    docs = list(db.collection(COLLECTION).where("nivel_clinico", "==", 3).stream())
    print(f"Documentos N3 encontrados: {len(docs)}\n")

    procesados = 0
    omitidos   = 0

    for doc in docs:
        data    = doc.to_dict()
        doc_id  = doc.id
        texto   = data.get("texto", "")
        pregunta = data.get("pregunta", "").strip()
        existing_key = data.get("pregunta_tts_key")

        if not pregunta:
            print(f"[SKIP] {doc_id}: sin campo 'pregunta'")
            omitidos += 1
            continue

        if existing_key and not args.force:
            print(f"[SKIP] {doc_id}: ya tiene pregunta_tts_key='{existing_key}' (usa --force para sobreescribir)")
            omitidos += 1
            continue

        tts_key = f"q_{doc_id}"
        print(f"Procesando: {doc_id}")
        print(f"  texto:    '{texto}'")
        print(f"  pregunta: '{pregunta}'")
        print(f"  tts_key:  '{tts_key}'")

        if args.dry_run:
            print(f"  [DRY-RUN] Generaría tts/female/{tts_key}.mp3 y tts/male/{tts_key}.mp3")
            print(f"  [DRY-RUN] Escribiría pregunta_tts_key='{tts_key}' en Firestore")
            print()
            procesados += 1
            continue

        # Generar y subir para cada voz
        for voice_label, voice_name in VOICES.items():
            mp3_bytes    = synthesize(tts_client, pregunta, voice_name)
            storage_path = f"tts/{voice_label}/{tts_key}.mp3"
            url = upload_bytes(bucket, mp3_bytes, storage_path)
            print(f"  [{voice_label}] → {url}")

        # Escribir key en Firestore
        doc.reference.update({"pregunta_tts_key": tts_key})
        print(f"  -> [OK] Firestore actualizado con pregunta_tts_key='{tts_key}'")
        print()
        procesados += 1

    print(f"Resumen: {procesados} procesados, {omitidos} omitidos.")


if __name__ == "__main__":
    main()
