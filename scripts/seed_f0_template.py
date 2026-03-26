#!/usr/bin/env python3
"""
seed_f0_template.py — Agrega el campo `f0_template_hz` a cada estímulo
en la colección `stimuli_TEM` de Firestore.

El campo se DERIVA del `patron_tonal` ya existente usando el mapeo MIT estándar:
    L → 200.0 Hz  (nota baja del terapeuta)
    H → 237.8 Hz  (tercera menor: 200 × 2^(3/12) ≈ 237.84)

El script primero LEE cada documento, obtiene `patron_tonal` y `syllables`,
valida que las longitudes coincidan y calcula el array. Esto es más seguro
que usar un mapa estático porque se valida contra el estado real de Firestore.

Cómo correr:
  cd scripts
  python seed_f0_template.py
"""

import os
import sys
import firebase_admin
from firebase_admin import credentials, firestore

# ---------------------------------------------------------------------------
# Constantes MIT (Terapia de Entonación Melódica)
# ---------------------------------------------------------------------------
# Frecuencia base del terapeuta: 200 Hz (convención clínica MIT).
# Intervalo L→H: tercera menor = 3 semitonos = factor 2^(3/12).
F0_LOW = 200.0
F0_HIGH = round(200.0 * (2 ** (3 / 12)), 1)   # ≈ 237.8

TONE_MAP = {
    "L": F0_LOW,
    "H": F0_HIGH,
}

# ---------------------------------------------------------------------------
# Inicializar Firebase
# ---------------------------------------------------------------------------
SERVICE_ACCOUNT_KEY = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
COLLECTION = "stimuli_TEM"

if not firebase_admin._apps:
    cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# ---------------------------------------------------------------------------
# Lógica principal
# ---------------------------------------------------------------------------

def patron_to_f0(patron_tonal: str) -> list[float]:
    """Convierte un patron_tonal ('LHL') en array de Hz ([200.0, 237.8, 200.0])."""
    result = []
    for ch in patron_tonal.upper():
        if ch not in TONE_MAP:
            raise ValueError(
                f"Carácter '{ch}' desconocido en patron_tonal '{patron_tonal}'. "
                f"Solo se aceptan: {list(TONE_MAP.keys())}"
            )
        result.append(TONE_MAP[ch])
    return result


def main():
    print(f"🎵  Generando f0_template_hz para colección '{COLLECTION}'")
    print(f"    L = {F0_LOW} Hz, H = {F0_HIGH} Hz  (tercera menor, 3 semitonos)\n")

    docs = db.collection(COLLECTION).stream()
    ok = 0
    errors = 0

    for doc in docs:
        doc_id = doc.id
        data = doc.to_dict()

        patron = data.get("patron_tonal")
        syllables = data.get("syllables", [])

        # --- Validaciones ---
        if not patron:
            print(f"  ⚠️  {doc_id}: sin campo patron_tonal — saltando")
            errors += 1
            continue

        f0_template = patron_to_f0(patron)

        if len(f0_template) != len(syllables):
            print(
                f"  ❌  {doc_id}: patron_tonal='{patron}' ({len(f0_template)}) "
                f"vs syllables ({len(syllables)}) — ¡LONGITUDES NO COINCIDEN!"
            )
            errors += 1
            continue

        # --- Actualizar Firestore ---
        try:
            db.collection(COLLECTION).document(doc_id).update({
                "f0_template_hz": f0_template,
            })
            syl_str = ", ".join(syllables)
            f0_str = ", ".join(str(v) for v in f0_template)
            print(f"  ✅  {doc_id}: [{syl_str}] → [{f0_str}]")
            ok += 1
        except Exception as e:
            print(f"  ❌  {doc_id}: error al actualizar — {e}")
            errors += 1

    print(f"\n{'✔' if errors == 0 else '⚠️'}  {ok} actualizados, {errors} errores.")
    if errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
