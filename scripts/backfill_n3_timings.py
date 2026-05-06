"""
backfill_n3_timings.py
----------------------
Calcula y escribe los campos de temporización para los estímulos N3 existentes
en Firestore que aún no los tienen, y cambia su estado a "aprobado".

Esquema real del documento (verificado en Firestore):
  nivel_clinico            : int  (3 para N3)
  texto                    : str
  syllables                : List[str]
  f0_template_hz           : List[float]
  audio_url_sprechgesang   : str  (gs://...)
  audio_url_habla_normal   : str  (gs://...)
  estado                   : str  ("pendiente_revision" -> "aprobado")

Campos escritos por este script:
  onsets_ms_sprechgesang        : List[int]
  durations_ms_sprechgesang     : List[int]
  audio_duration_ms_sprechgesang: int
  f0_template_hz_sprechgesang   : List[float]  (copia de f0_template_hz)

  onsets_ms_habla_normal        : List[int]
  durations_ms_habla_normal     : List[int]
  audio_duration_ms_habla_normal: int
  f0_template_hz_habla_normal   : List[float]  (todo ceros)

  estado                        : "aprobado"

Algoritmo de temporización:
  - Sprechgesang: detección de onsets por energía espectral (librosa).
    Fallback proporcional si librosa no puede detectar.
  - Habla normal: proporcional (el tempo regular lo hace predecible).

Algoritmo onset detection (sprechgesang):
  1. Decodificar WebM a float32 mono (PyAV + numpy).
  2. librosa.onset.onset_detect con backtrack=True.
  3. Filtrar onsets < 40 ms (ruido de micrófono).
  4. Ajustar cantidad al n_syllables:
     - Si coincide: usar directamente.
     - Si sobran: fusionar los más cercanos.
     - Si faltan: interpolar los gaps más grandes.
     - Si 0: fallback proporcional.

Algoritmo proporcional (fallback / habla_normal):
  silence_start = min(round(dur_ms * 0.08), 80)
  silence_end   = min(round(dur_ms * 0.05), 50)
  span          = dur_ms - silence_start - silence_end
  spacing       = span / n_syllables
  onset[i]      = silence_start + round(i * spacing)
  duration[i]   = round(spacing) - 20   (ultima: dur_ms - silence_end - onset[-1])

Requisitos:
  pip install firebase-admin av librosa

Uso:
  python scripts/backfill_n3_timings.py --dry-run          # solo imprime
  python scripts/backfill_n3_timings.py                    # escribe en Firestore
  python scripts/backfill_n3_timings.py --id ST_TEM_N3_XXX # un solo estimulo
  python scripts/backfill_n3_timings.py --force            # sobreescribir campos existentes
"""

import argparse
import math
import re
import sys
import tempfile
from typing import Optional

import firebase_admin
from firebase_admin import credentials, firestore, storage
import av
import numpy as np


# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------

SERVICE_ACCOUNT_PATH = "scripts/serviceAccountKey.json"
COLLECTION = "stimuli_TEM"


# ---------------------------------------------------------------------------
# Helpers Firebase Storage  (gs:// -> bytes)
# ---------------------------------------------------------------------------

def _parse_gs_url(gs_url: str) -> tuple[str, str]:
    """Extrae (bucket, blob_path) de una URL gs://bucket/path."""
    m = re.match(r"gs://([^/]+)/(.+)", gs_url)
    if not m:
        raise ValueError(f"URL gs:// invalida: {gs_url}")
    return m.group(1), m.group(2)


def download_gs_bytes(gs_url: str) -> bytes:
    """Descarga un objeto de Firebase Storage como bytes usando Admin SDK."""
    bucket_name, blob_path = _parse_gs_url(gs_url)
    bucket_obj = storage.bucket(bucket_name)
    blob = bucket_obj.blob(blob_path)
    return blob.download_as_bytes()


# ---------------------------------------------------------------------------
# Lectura de duracion WebM con PyAV (FFmpeg)
# ---------------------------------------------------------------------------

def get_webm_duration_ms(gs_url: str) -> Optional[int]:
    """Descarga el WebM desde Firebase Storage y devuelve su duracion en ms.

    Los archivos WebM grabados con MediaRecorder del browser no tienen el
    campo de duracion en el header (container.duration == None). Se escanean
    todos los paquetes para encontrar el ultimo timestamp + duracion.
    """
    import os
    filename = gs_url.split("/")[-1]
    tmp_path = None
    try:
        print(f"    Descargando {filename} ...", end=" ", flush=True)
        data = download_gs_bytes(gs_url)
        with tempfile.NamedTemporaryFile(suffix=".webm", delete=False) as tmp:
            tmp.write(data)
            tmp_path = tmp.name

        container = av.open(tmp_path)

        # Intento 1: campo de duracion del contenedor (microsegundos)
        if container.duration and container.duration > 0:
            dur_ms = int(math.ceil(container.duration / 1000))
            container.close()
            print(f"{dur_ms} ms")
            return dur_ms

        # Intento 2: campo de duracion del stream
        for stream in container.streams:
            if stream.type in ("audio", "video") and stream.duration:
                tb = float(stream.time_base)
                dur_ms = int(math.ceil(stream.duration * tb * 1000))
                if dur_ms > 0:
                    container.close()
                    print(f"{dur_ms} ms (stream)")
                    return dur_ms

        # Intento 3: escanear todos los paquetes y calcular max(pts + duration)
        # Necesario para WebM de MediaRecorder que omiten duracion en el header
        last_ms = 0.0
        for packet in container.demux():
            if packet.stream.type not in ("audio", "video"):
                continue
            if packet.pts is None:
                continue
            tb = float(packet.stream.time_base)
            end_ms = (packet.pts + (packet.duration or 0)) * tb * 1000
            if end_ms > last_ms:
                last_ms = end_ms

        container.close()

        if last_ms <= 0:
            print("ERROR (PyAV: duracion no disponible)")
            return None

        dur_ms = int(math.ceil(last_ms))
        print(f"{dur_ms} ms (scan)")
        return dur_ms

    except Exception as exc:
        print(f"ERROR: {exc}")
        return None
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


# ---------------------------------------------------------------------------
# Algoritmo proporcional (para habla_normal y fallback)
# ---------------------------------------------------------------------------

def compute_timings_proportional(dur_ms: int, n: int) -> tuple[list[int], list[int]]:
    """Devuelve (onsets_ms, durations_ms) con distribución uniforme."""
    if n <= 0:
        return [], []
    silence_start = min(round(dur_ms * 0.08), 80)
    silence_end   = min(round(dur_ms * 0.05), 50)
    span          = dur_ms - silence_start - silence_end
    spacing       = span / n

    onsets    = [silence_start + round(i * spacing) for i in range(n)]
    durations = [round(spacing) - 20] * n
    durations[-1] = dur_ms - silence_end - onsets[-1]
    durations = [max(1, d) for d in durations]

    return onsets, durations


# ---------------------------------------------------------------------------
# Algoritmo onset detection con librosa (para sprechgesang)
# ---------------------------------------------------------------------------

def _merge_closest(onsets: list[int], n: int) -> list[int]:
    """Fusiona los dos onsets más cercanos hasta tener n."""
    while len(onsets) > n:
        gaps = [onsets[i + 1] - onsets[i] for i in range(len(onsets) - 1)]
        idx = gaps.index(min(gaps))
        merged = (onsets[idx] + onsets[idx + 1]) // 2
        onsets = onsets[:idx] + [merged] + onsets[idx + 2:]
    return onsets


def _interpolate_missing(onsets: list[int], n: int, dur_ms: int) -> list[int]:
    """Añade onsets interpolados en los gaps más grandes hasta tener n."""
    while len(onsets) < n:
        if len(onsets) < 2:
            break
        gaps = [onsets[i + 1] - onsets[i] for i in range(len(onsets) - 1)]
        idx = gaps.index(max(gaps))
        new_onset = (onsets[idx] + onsets[idx + 1]) // 2
        onsets = onsets[:idx + 1] + [new_onset] + onsets[idx + 1:]
    return onsets


def decode_webm_to_float32(tmp_path: str, sr_target: int = 22050) -> tuple[np.ndarray, int]:
    """Decodifica un WebM a numpy float32 mono usando PyAV."""
    container = av.open(tmp_path)
    audio_stream = next((s for s in container.streams if s.type == "audio"), None)
    if audio_stream is None:
        container.close()
        raise ValueError("No audio stream found in WebM")

    samples = []
    for frame in container.decode(audio_stream):
        arr = frame.to_ndarray()  # shape: (channels, samples) o (samples,)
        if arr.ndim == 2:
            arr = arr.mean(axis=0)  # mezclar a mono
        samples.append(arr)
    container.close()

    if not samples:
        raise ValueError("No audio samples decoded")

    y = np.concatenate(samples).astype(np.float32)
    # Normalizar a rango [-1, 1]
    max_val = np.abs(y).max()
    if max_val > 0:
        y = y / max_val

    # Calcular sr real desde el stream
    sr_real = int(audio_stream.sample_rate) if audio_stream.sample_rate else sr_target

    # Resamplear a sr_target si es necesario
    if sr_real != sr_target:
        try:
            import librosa
            y = librosa.resample(y, orig_sr=sr_real, target_sr=sr_target)
        except Exception:
            pass  # mantener sr_real si resample falla
        else:
            sr_real = sr_target

    return y, sr_real


def compute_timings_onset(tmp_path: str, dur_ms: int, n: int) -> tuple[list[int], list[int]]:
    """
    Detecta onsets reales de sílabas usando librosa sobre el archivo WebM.
    Ajusta la cantidad al número de sílabas y calcula duraciones.
    Retorna (onsets_ms, durations_ms).
    """
    try:
        import librosa
    except ImportError:
        print("    [onset] librosa no disponible → fallback proporcional")
        return compute_timings_proportional(dur_ms, n)

    try:
        y, sr = decode_webm_to_float32(tmp_path)
    except Exception as e:
        print(f"    [onset] ERROR decodificando audio: {e} → fallback proporcional")
        return compute_timings_proportional(dur_ms, n)

    try:
        onset_frames = librosa.onset.onset_detect(
            y=y,
            sr=sr,
            hop_length=256,      # ~11 ms de resolución a 22 kHz
            backtrack=True,      # retroceder al mínimo local = inicio real
            delta=0.05,          # sensibilidad: bajar si detecta pocas sílabas
            units="samples",
        )
        onset_ms_raw = sorted(set(int(round(f / sr * 1000)) for f in onset_frames))
    except Exception as e:
        print(f"    [onset] ERROR librosa: {e} → fallback proporcional")
        return compute_timings_proportional(dur_ms, n)

    # Filtrar onsets < 40 ms (ruido de activación del micrófono)
    onset_ms = [o for o in onset_ms_raw if o >= 40]
    print(f"    [onset] librosa detectó {len(onset_ms_raw)} onsets raw → {len(onset_ms)} tras filtro 40ms: {onset_ms}")

    if len(onset_ms) == 0:
        print("    [onset] sin onsets → fallback proporcional")
        return compute_timings_proportional(dur_ms, n)

    # Ajustar cantidad al número de sílabas
    if len(onset_ms) > n:
        onset_ms = _merge_closest(onset_ms, n)
        print(f"    [onset] fusionados → {onset_ms}")
    elif len(onset_ms) < n:
        onset_ms = _interpolate_missing(onset_ms, n, dur_ms)
        print(f"    [onset] interpolados → {onset_ms}")

    # Calcular duraciones: onset[i+1] - onset[i] - margen
    silence_end = min(round(dur_ms * 0.05), 50)
    durations = []
    for i in range(len(onset_ms) - 1):
        durations.append(max(1, onset_ms[i + 1] - onset_ms[i] - 20))
    durations.append(max(1, dur_ms - silence_end - onset_ms[-1]))

    return onset_ms, durations


# ---------------------------------------------------------------------------
# Procesar un estimulo
# ---------------------------------------------------------------------------

def process_stimulus(doc_id: str, data: dict, dry_run: bool, db) -> bool:
    print(f"\n{'[DRY-RUN] ' if dry_run else ''}Procesando: {doc_id}")
    print(f"  texto: {data.get('texto', '?')!r}  syllables: {data.get('syllables', [])}")

    syllables  = data.get("syllables", [])
    n          = len(syllables)
    f0_base    = data.get("f0_template_hz", [])
    url_sprech = data.get("audio_url_sprechgesang")
    url_habla  = data.get("audio_url_habla_normal")

    if not syllables:
        print("  [SKIP] Sin campo 'syllables'.")
        return False
    if not url_sprech or not url_habla:
        print("  [SKIP] Faltan audio_url_sprechgesang o audio_url_habla_normal.")
        return False

    # Sprechgesang — onset detection con librosa
    print("  [sprechgesang]")
    tmp_path_sprech = None
    try:
        filename_s = url_sprech.split("/")[-1]
        print(f"    Descargando {filename_s} ...", end=" ", flush=True)
        data_bytes = download_gs_bytes(url_sprech)
        import os
        with tempfile.NamedTemporaryFile(suffix=".webm", delete=False) as tmp:
            tmp.write(data_bytes)
            tmp_path_sprech = tmp.name

        dur_sprech = _get_duration_from_tmp(tmp_path_sprech)
        if dur_sprech is None:
            print("  [SKIP] No se pudo obtener duracion sprechgesang.")
            return False

        print(f"    Duración: {dur_sprech} ms")
        onsets_s, durs_s = compute_timings_onset(tmp_path_sprech, dur_sprech, n)
    finally:
        if tmp_path_sprech and os.path.exists(tmp_path_sprech):
            try:
                os.unlink(tmp_path_sprech)
            except OSError:
                pass

    f0_sprech = list(f0_base) if f0_base else [0.0] * n
    print(f"    onsets   = {onsets_s}")
    print(f"    durs     = {durs_s}")

    # Habla normal — proporcional (ritmo regular)
    print("  [habla_normal]")
    dur_habla = get_webm_duration_ms(url_habla)
    if dur_habla is None:
        print("  [SKIP] No se pudo obtener duracion habla normal.")
        return False

    onsets_h, durs_h = compute_timings_proportional(dur_habla, n)
    f0_habla = [0.0] * n
    print(f"    onsets   = {onsets_h}")
    print(f"    durs     = {durs_h}")

    # Escritura
    update = {
        "onsets_ms_sprechgesang":         onsets_s,
        "durations_ms_sprechgesang":      durs_s,
        "audio_duration_ms_sprechgesang": dur_sprech,
        "f0_template_hz_sprechgesang":    f0_sprech,
        "onsets_ms_habla_normal":         onsets_h,
        "durations_ms_habla_normal":      durs_h,
        "audio_duration_ms_habla_normal": dur_habla,
        "f0_template_hz_habla_normal":    f0_habla,
        "estado":                         "aprobado",
    }

    if dry_run:
        print("  -> [DRY-RUN] No se escribe en Firestore.")
    else:
        db.collection(COLLECTION).document(doc_id).update(update)
        print("  -> [OK] Firestore actualizado.")

    return True


def _get_duration_from_tmp(tmp_path: str) -> Optional[int]:
    """Extrae duración en ms de un WebM ya guardado en disco."""
    import os
    try:
        container = av.open(tmp_path)

        if container.duration and container.duration > 0:
            dur_ms = int(math.ceil(container.duration / 1000))
            container.close()
            return dur_ms

        for stream in container.streams:
            if stream.type in ("audio", "video") and stream.duration:
                tb = float(stream.time_base)
                dur_ms = int(math.ceil(stream.duration * tb * 1000))
                if dur_ms > 0:
                    container.close()
                    return dur_ms

        last_ms = 0.0
        for packet in container.demux():
            if packet.stream.type not in ("audio", "video"):
                continue
            if packet.pts is None:
                continue
            tb = float(packet.stream.time_base)
            end_ms = (packet.pts + (packet.duration or 0)) * tb * 1000
            if end_ms > last_ms:
                last_ms = end_ms

        container.close()
        return int(math.ceil(last_ms)) if last_ms > 0 else None

    except Exception as exc:
        print(f"ERROR leyendo duración: {exc}")
        return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Backfill N3 timing fields in Firestore")
    parser.add_argument("--dry-run", action="store_true", help="Calcular sin escribir en Firestore")
    parser.add_argument("--id", metavar="DOC_ID", help="Procesar solo este documento")
    parser.add_argument("--force", action="store_true",
                        help="Sobreescribir aunque ya existan los campos")
    args = parser.parse_args()

    # Inicializar Firebase Admin
    try:
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)
    except ValueError:
        pass  # ya inicializado

    db = firestore.client()

    # Obtener documentos N3
    if args.id:
        raw = db.collection(COLLECTION).document(args.id).get()
        if not raw.exists:
            print(f"Documento {args.id} no encontrado.", file=sys.stderr)
            sys.exit(1)
        docs = [raw]
    else:
        query = db.collection(COLLECTION).where(
            filter=firestore.FieldFilter("nivel_clinico", "==", 3)
        )
        docs = list(query.stream())

    print(f"Documentos N3 encontrados: {len(docs)}")

    processed = skipped = 0
    for doc in docs:
        data = doc.to_dict()
        if not args.force and "onsets_ms_sprechgesang" in data:
            print(f"  [SKIP] {doc.id} - ya tiene onsets_ms_sprechgesang (--force para sobreescribir)")
            skipped += 1
            continue
        ok = process_stimulus(doc.id, data, args.dry_run, db)
        processed += ok
        skipped   += not ok

    print(f"\n{'[DRY-RUN] ' if args.dry_run else ''}Resumen: {processed} procesados, {skipped} omitidos.")


if __name__ == "__main__":
    main()
