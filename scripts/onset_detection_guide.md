# Guía de Onset Detection para Timings de Sílabas (N3 Sprechgesang)

## Contexto

Cuando el agente web crea un ejercicio TEM nivel 3, necesita calcular los campos:

- `onsets_ms_sprechgesang`: lista de ints con el tiempo (ms) donde empieza cada sílaba en el audio sprechgesang.
- `durations_ms_sprechgesang`: lista de ints con cuántos ms dura el destaque de cada sílaba.

Estos campos controlan la animación de sílabas en la app móvil (Flutter). Si los timings son incorrectos, las sílabas se resaltan en el momento equivocado respecto al audio.

---

## Dos algoritmos disponibles

### 1. Onset Detection con librosa (recomendado para sprechgesang)

El audio de sprechgesang tiene sílabas claramente marcadas porque es un canto hablado con ritmo variable. La detección de onsets por energía espectral captura los momentos exactos en que el locutor emite cada sílaba.

**Cuándo usarlo:** Siempre para `audio_url_sprechgesang`.

### 2. Proporcional (para habla_normal y fallback)

Distribuye las sílabas uniformemente a lo largo de la duración del audio, con un margen de silencio al inicio y al final. Funciona bien para `audio_url_habla_normal` porque el tempo es más regular.

**Cuándo usarlo:** Para `audio_url_habla_normal`, y como fallback si librosa falla.

---

## Requisitos

```bash
pip install av librosa numpy
```

- **av** (PyAV): decodifica el WebM a array de audio.
- **librosa**: detecta onsets por energía espectral.
- **numpy**: operaciones de array.

---

## Algoritmo onset detection paso a paso

### Paso 1: Descargar el WebM desde Firebase Storage

El campo `audio_url_sprechgesang` en Firestore es una URL `gs://...`. Descárgala como bytes y escríbelos a un archivo temporal:

```python
import re
import tempfile
import os
from firebase_admin import storage

def download_gs_bytes(gs_url: str) -> bytes:
    """Descarga un objeto de Firebase Storage como bytes usando Admin SDK."""
    m = re.match(r"gs://([^/]+)/(.+)", gs_url)
    if not m:
        raise ValueError(f"URL gs:// inválida: {gs_url}")
    bucket_name, blob_path = m.group(1), m.group(2)
    bucket = storage.bucket(bucket_name)
    blob = bucket.blob(blob_path)
    return blob.download_as_bytes()

def download_gs_to_tmp(gs_url: str) -> str:
    """Descarga gs://bucket/path al sistema de archivos local. Retorna la ruta del archivo temporal."""
    data = download_gs_bytes(gs_url)
    with tempfile.NamedTemporaryFile(suffix=".webm", delete=False) as tmp:
        tmp.write(data)
        return tmp.name
```

### Paso 2: Obtener la duración del WebM en milisegundos

> ⚠️ **Crítico:** Los WebM grabados desde el browser con `MediaRecorder` **no tienen la duración en el header** del contenedor. `container.duration` devuelve `None`. Se necesita un fallback de 3 pasos que termina escaneando todos los paquetes.

```python
import math
import av

def get_duration_ms(tmp_path: str) -> int | None:
    """
    Extrae la duración en ms de un WebM ya guardado en disco.
    Implementa 3 fallbacks porque los WebM de MediaRecorder no tienen
    duración en el header del contenedor.
    """
    try:
        container = av.open(tmp_path)

        # Intento 1: campo de duración del contenedor (en microsegundos)
        if container.duration and container.duration > 0:
            dur_ms = int(math.ceil(container.duration / 1000))
            container.close()
            return dur_ms

        # Intento 2: campo de duración del stream
        for stream in container.streams:
            if stream.type in ("audio", "video") and stream.duration:
                tb = float(stream.time_base)
                dur_ms = int(math.ceil(stream.duration * tb * 1000))
                if dur_ms > 0:
                    container.close()
                    return dur_ms

        # Intento 3: escanear todos los paquetes y calcular max(pts + duration)
        # Necesario para WebM de MediaRecorder que omiten duración en el header
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
```

### Paso 3: Decodificar WebM a numpy float32 mono

```python
import av
import numpy as np
import librosa

def decode_webm_to_float32(tmp_path: str, sr_target: int = 22050) -> tuple[np.ndarray, int]:
    container = av.open(tmp_path)
    audio_stream = next((s for s in container.streams if s.type == "audio"), None)
    if audio_stream is None:
        container.close()
        raise ValueError("No audio stream found in WebM")

    samples = []
    for frame in container.decode(audio_stream):
        arr = frame.to_ndarray()
        if arr.ndim == 2:
            arr = arr.mean(axis=0)   # stereo → mono
        samples.append(arr)
    container.close()

    y = np.concatenate(samples).astype(np.float32)
    max_val = np.abs(y).max()
    if max_val > 0:
        y = y / max_val   # normalizar [-1, 1]

    sr_real = int(audio_stream.sample_rate)
    if sr_real != sr_target:
        y = librosa.resample(y, orig_sr=sr_real, target_sr=sr_target)
        sr_real = sr_target

    return y, sr_real
```

### Paso 4: Detectar onsets con librosa

```python
def detect_onsets_ms(y: np.ndarray, sr: int) -> list[int]:
    onset_frames = librosa.onset.onset_detect(
        y=y,
        sr=sr,
        hop_length=256,      # resolución ~11 ms a 22 kHz
        backtrack=True,      # retroceder al mínimo local → inicio real de la sílaba
        delta=0.05,          # sensibilidad (bajar si detecta pocas sílabas)
        units="samples",
    )
    onset_ms = sorted(set(int(round(f / sr * 1000)) for f in onset_frames))
    # Filtrar ruido de activación de micrófono (primeros 40 ms)
    return [o for o in onset_ms if o >= 40]
```

### Paso 5: Ajustar la cantidad de onsets al número de sílabas

El detector puede encontrar más o menos onsets que el número de sílabas. Hay que ajustar:

```python
def merge_closest(onsets: list[int], n: int) -> list[int]:
    """Fusiona los dos onsets más cercanos hasta tener n."""
    while len(onsets) > n:
        gaps = [onsets[i + 1] - onsets[i] for i in range(len(onsets) - 1)]
        idx = gaps.index(min(gaps))
        merged = (onsets[idx] + onsets[idx + 1]) // 2
        onsets = onsets[:idx] + [merged] + onsets[idx + 2:]
    return onsets

def interpolate_missing(onsets: list[int], n: int) -> list[int]:
    """Añade onsets interpolados en los gaps más grandes hasta tener n."""
    while len(onsets) < n:
        if len(onsets) < 2:
            break
        gaps = [onsets[i + 1] - onsets[i] for i in range(len(onsets) - 1)]
        idx = gaps.index(max(gaps))
        new_onset = (onsets[idx] + onsets[idx + 1]) // 2
        onsets = onsets[:idx + 1] + [new_onset] + onsets[idx + 1:]
    return onsets
```

### Paso 6: Calcular duraciones

Cada sílaba dura desde su onset hasta el onset siguiente, menos un margen de 20 ms (pausa entre sílabas). La última sílaba dura hasta el final del audio menos un margen de silencio final:

```python
def compute_durations(onsets: list[int], dur_ms: int) -> list[int]:
    silence_end = min(round(dur_ms * 0.05), 50)  # máx 50 ms de silencio al final
    durations = []
    for i in range(len(onsets) - 1):
        durations.append(max(1, onsets[i + 1] - onsets[i] - 20))
    durations.append(max(1, dur_ms - silence_end - onsets[-1]))
    return durations
```

### Función completa

```python
import os

def compute_sprechgesang_timings(gs_url: str, n_syllables: int) -> tuple[list[int], list[int], int]:
    """
    Retorna (onsets_ms, durations_ms, audio_duration_ms) para el audio sprechgesang.

    Args:
        gs_url: URL gs://... del audio WebM en Firebase Storage.
        n_syllables: número de sílabas del texto (len(syllables)).

    Returns:
        onsets_ms: lista de n_syllables ints.
        durations_ms: lista de n_syllables ints.
        audio_duration_ms: duración total del audio en ms.
    """
    tmp_path = download_gs_to_tmp(gs_url)
    try:
        # Paso 2: obtener duración con fallback de 3 pasos
        dur_ms = get_duration_ms(tmp_path)
        if dur_ms is None:
            raise ValueError("No se pudo obtener la duración del audio")

        # Paso 3: decodificar a float32
        y, sr = decode_webm_to_float32(tmp_path)

        # Paso 4: detectar onsets
        onsets = detect_onsets_ms(y, sr)

        if len(onsets) == 0:
            # Fallback proporcional
            onsets, durations = compute_timings_proportional(dur_ms, n_syllables)
            return onsets, durations, dur_ms

        # Paso 5: ajustar cantidad
        if len(onsets) > n_syllables:
            onsets = merge_closest(onsets, n_syllables)
        elif len(onsets) < n_syllables:
            onsets = interpolate_missing(onsets, n_syllables)

        # Paso 6: calcular duraciones
        durations = compute_durations(onsets, dur_ms)
        return onsets, durations, dur_ms

    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
```

---

## Algoritmo proporcional (habla_normal y fallback)

```python
def compute_timings_proportional(dur_ms: int, n: int) -> tuple[list[int], list[int]]:
    """Distribución uniforme de sílabas."""
    silence_start = min(round(dur_ms * 0.08), 80)  # máx 80 ms al inicio
    silence_end   = min(round(dur_ms * 0.05), 50)  # máx 50 ms al final
    span          = dur_ms - silence_start - silence_end
    spacing       = span / n

    onsets    = [silence_start + round(i * spacing) for i in range(n)]
    durations = [round(spacing) - 20] * n
    durations[-1] = dur_ms - silence_end - onsets[-1]
    durations = [max(1, d) for d in durations]
    return onsets, durations
```

---

## Campos que se deben escribir en Firestore

Al crear un ejercicio N3, escribe estos campos en el documento de `stimuli_TEM`:

```json
{
  "onsets_ms_sprechgesang":         [546, 1129, 1991, 2525, 3076, 3448, 3820],
  "durations_ms_sprechgesang":      [563, 842, 514, 531, 352, 352, 1410],
  "audio_duration_ms_sprechgesang": 5280,
  "f0_template_hz_sprechgesang":    [<copia de f0_template_hz del documento>],

  "onsets_ms_habla_normal":         [80, 653, 1225, 1798, 2371, 2944, 3516],
  "durations_ms_habla_normal":      [553, 553, 553, 553, 553, 553, 573],
  "audio_duration_ms_habla_normal": 4139,
  "f0_template_hz_habla_normal":    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],

  "estado": "aprobado"
}
```

- `f0_template_hz_sprechgesang`: copia el campo `f0_template_hz` que ya está en el documento.
- `f0_template_hz_habla_normal`: lista de ceros, una por sílaba.

---

## Notas de implementación

- El campo `audio_url_sprechgesang` y `audio_url_habla_normal` usan el bucket `apphasia-7a930.firebasestorage.app`.
- Los WebM pueden tener distintas tasas de muestreo; el resample a 22050 Hz es necesario para librosa.
- Si `av.open` falla (archivo corrupto o vacío), usar proporcional como fallback.
- El parámetro `delta=0.05` en `onset_detect` es sensible al volumen. Si el audio está grabado en silencio relativo y la función detecta 0 onsets, bajar `delta` a `0.03`.
- El parámetro `backtrack=True` es esencial: sin él, librosa reporta el pico de energía (medio de la sílaba) en lugar del inicio real.

---

## Ejemplo de resultado

Para el texto "tengo mucho sueño hoy" con sílabas `["ten", "go", "mu", "cho", "sue", "ño", "hoy"]`:

| Sílaba | Onset (ms) | Duración (ms) |
|--------|-----------|---------------|
| ten    | 546       | 563           |
| go     | 1129      | 842           |
| mu     | 1991      | 514           |
| cho    | 2525      | 531           |
| sue    | 3076      | 352           |
| ño     | 3448      | 352           |
| hoy    | 3820      | 1410          |
