import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate("scripts/serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

print("=== N1 ===")
for d in db.collection("stimuli_TEM").where("nivel_clinico", "==", 1).stream():
    data = d.to_dict()
    print(f"  id={d.id}")
    print(f"    texto={data.get('texto')}")
    print(f"    pregunta_tts_key={data.get('pregunta_tts_key')}")
    print(f"    pregunta={data.get('pregunta')}")

print()
print("=== N2 ===")
for d in db.collection("stimuli_TEM").where("nivel_clinico", "==", 2).stream():
    data = d.to_dict()
    print(f"  id={d.id}")
    print(f"    texto={data.get('texto')}")
    print(f"    pregunta_tts_key={data.get('pregunta_tts_key')}")
    print(f"    pregunta={data.get('pregunta')}")

print()
print("=== N3 ===")
for d in db.collection("stimuli_TEM").where("nivel_clinico", "==", 3).stream():
    data = d.to_dict()
    print(f"  id={d.id}")
    print(f"    texto={data.get('texto')}")
    print(f"    pregunta_tts_key={data.get('pregunta_tts_key')}")
    print(f"    pregunta={data.get('pregunta')}")
