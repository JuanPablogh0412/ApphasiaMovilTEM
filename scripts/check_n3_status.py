"""
check_n3_status.py
------------------
Revisa todos los documentos N3 en Firestore y reporta cuáles tienen
los campos de onset ya escritos y cuáles les faltan.
"""

import firebase_admin
from firebase_admin import credentials, firestore

REQUIRED_FIELDS = [
    "onsets_ms_sprechgesang",
    "durations_ms_sprechgesang",
    "audio_duration_ms_sprechgesang",
    "onsets_ms_habla_normal",
    "durations_ms_habla_normal",
    "audio_duration_ms_habla_normal",
]

cred = credentials.Certificate("scripts/serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

docs = list(db.collection("stimuli_TEM").where("nivel_clinico", "==", 3).stream())
print(f"Total documentos N3: {len(docs)}\n")

ok = []
faltantes = []

for d in docs:
    data = d.to_dict()
    missing = [f for f in REQUIRED_FIELDS if not data.get(f)]
    if missing:
        faltantes.append((d.id, data.get("texto", "?"), missing))
    else:
        ok.append((d.id, data.get("texto", "?"), data.get("onsets_ms_sprechgesang")))

print(f"✅ Completos ({len(ok)}):")
for doc_id, texto, onsets in ok:
    print(f"  {doc_id}  '{texto}'  onsets={onsets}")

print()
print(f"❌ Incompletos ({len(faltantes)}):")
if faltantes:
    for doc_id, texto, missing in faltantes:
        print(f"  {doc_id}  '{texto}'")
        print(f"    Faltan: {missing}")
else:
    print("  Ninguno — todos tienen los campos.")
