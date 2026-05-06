#!/usr/bin/env python3
"""
Migración Firestore: stimuli_TEM
  1. Renombra `pregunta_texto` → `pregunta`  (bug-fix)
  2. Genera TTS MP3 para cada pregunta y sube a Storage
  3. Escribe `pregunta_tts_url` en el documento

Requisitos:
  pip install firebase-admin google-cloud-texttospeech

Uso:
  # Con credenciales de servicio
  export GOOGLE_APPLICATION_CREDENTIALS=path/to/sa.json
  python migrate_stimuli_tts.py

  # Solo renombrar campo (sin TTS)
  python migrate_stimuli_tts.py --rename-only

  # Dry-run (solo imprime, no escribe)
  python migrate_stimuli_tts.py --dry-run
"""
import argparse
import os
import tempfile

import firebase_admin
from firebase_admin import credentials, firestore, storage

BUCKET = "apphasia-7a930.firebasestorage.app"
COLLECTION = "stimuli_TEM"
VOICE_FEMALE = "es-US-Wavenet-A"
VOICE_MALE = "es-US-Wavenet-B"
SPEAKING_RATE = 0.85


def init_firebase():
    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if cred_path:
        cred = credentials.Certificate(cred_path)
    else:
        cred = credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred, {"storageBucket": BUCKET})
    return firestore.client(), storage.bucket()


def rename_field(db, dry_run: bool):
    """Rename pregunta_texto → pregunta in all stimuli docs."""
    docs = db.collection(COLLECTION).stream()
    count = 0
    for doc in docs:
        data = doc.to_dict()
        if "pregunta_texto" in data and "pregunta" not in data:
            if dry_run:
                print(f"  [dry-run] {doc.id}: pregunta_texto → pregunta")
            else:
                doc.reference.update(
                    {
                        "pregunta": data["pregunta_texto"],
                        "pregunta_texto": firestore.DELETE_FIELD,
                    }
                )
                print(f"  ✅ {doc.id}: renamed")
            count += 1
    print(f"  Total renamed: {count}")


def generate_question_tts(db, bucket, dry_run: bool):
    """Generate TTS for each stimulus question and write URL to doc."""
    from google.cloud import texttospeech

    client = texttospeech.TextToSpeechClient()

    docs = list(db.collection(COLLECTION).stream())
    for doc in docs:
        data = doc.to_dict()
        pregunta = data.get("pregunta") or data.get("pregunta_texto")
        if not pregunta:
            print(f"  ⚠ {doc.id}: no pregunta field, skipping")
            continue

        for voice_name, folder in [
            (VOICE_FEMALE, "female"),
            (VOICE_MALE, "male"),
        ]:
            blob_path = f"tts/{folder}/q_{doc.id}.mp3"

            if dry_run:
                print(f"  [dry-run] {doc.id} → {blob_path}")
                continue

            synthesis_input = texttospeech.SynthesisInput(text=pregunta)
            voice = texttospeech.VoiceSelectionParams(
                language_code="es-US",
                name=voice_name,
            )
            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.MP3,
                speaking_rate=SPEAKING_RATE,
            )
            response = client.synthesize_speech(
                input=synthesis_input, voice=voice, audio_config=audio_config
            )

            blob = bucket.blob(blob_path)
            with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
                f.write(response.audio_content)
                tmp = f.name
            blob.upload_from_filename(tmp)
            blob.make_public()
            os.unlink(tmp)
            print(f"  ✅ {doc.id} → {blob_path}")

        if not dry_run:
            doc.reference.update({"pregunta_tts_key": f"q_{doc.id}"})


def main():
    parser = argparse.ArgumentParser(description="Migrate stimuli_TEM")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--rename-only", action="store_true")
    args = parser.parse_args()

    db, bucket = init_firebase()

    print("1) Renaming pregunta_texto → pregunta …")
    rename_field(db, args.dry_run)

    if not args.rename_only:
        print("2) Generating question TTS …")
        generate_question_tts(db, bucket, args.dry_run)

    print("Done.")


if __name__ == "__main__":
    main()
