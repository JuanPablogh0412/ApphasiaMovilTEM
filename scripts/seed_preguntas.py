#!/usr/bin/env python3
"""
seed_preguntas.py — Agrega el campo `pregunta` a cada documento de stimuli_TEM.

La pregunta del paso 5 debe EVOCAR la palabra estímulo como respuesta natural,
sin revelarla. El paciente, al escucharla, debe producir la palabra practicada.

Cómo correr:
  cd scripts
  python seed_preguntas.py
"""

import os
import firebase_admin
from firebase_admin import credentials, firestore

# ---------------------------------------------------------------------------
# Mapa estímulo → pregunta evocadora
# ---------------------------------------------------------------------------
PREGUNTAS = {
    "ST_TEM_N1_001": "¿A quién llamas cuando necesitas cariño?",           # mamá
    "ST_TEM_N1_002": "¿Cómo llaman los hijos al padre?",                   # papá
    "ST_TEM_N1_003": "¿Qué toman cuando tienen sed?",                      # agua
    "ST_TEM_N1_004": "¿Qué dices cuando no conoces la respuesta?",         # no sé
    "ST_TEM_N1_005": "¿Qué pides cuando no puedes hacer algo solo?",       # ayuda
    "ST_TEM_N1_006": "¿Qué dices cuando alguien te hace un favor?",        # gracias
    "ST_TEM_N1_007": "¿En qué lugar vive una familia?",                    # casa
    "ST_TEM_N1_008": "¿Qué sientes cuando no has comido?",                 # hambre
    "ST_TEM_N1_009": "¿Qué sientes cuando algo te hace daño?",             # dolor
    "ST_TEM_N1_010": "¿Cómo te sientes cuando estás contento?",            # bien
}

# ---------------------------------------------------------------------------
# Inicializar Firebase
# ---------------------------------------------------------------------------
SERVICE_ACCOUNT_KEY = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
FIRESTORE_COLLECTION = "stimuli_TEM"

if not firebase_admin._apps:
    cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# ---------------------------------------------------------------------------
# Actualizar documentos
# ---------------------------------------------------------------------------
def main():
    print("🔤  Sembrando campo 'pregunta' en Firestore...\n")
    ok = 0
    for doc_id, pregunta in PREGUNTAS.items():
        try:
            ref = db.collection(FIRESTORE_COLLECTION).document(doc_id)
            ref.update({"pregunta": pregunta})
            print(f"  ✅  {doc_id} → \"{pregunta}\"")
            ok += 1
        except Exception as e:
            print(f"  ❌  {doc_id} — error: {e}")

    print(f"\n✔  {ok}/{len(PREGUNTAS)} documentos actualizados.")

if __name__ == "__main__":
    main()
