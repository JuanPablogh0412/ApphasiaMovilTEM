"""Audit script 2 — cross references and data quality."""
import firebase_admin
from firebase_admin import credentials, firestore

if not firebase_admin._apps:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

# 1. analysis_results_TEM sessions
print("=== analysis_results_TEM - sessions referenced ===")
ar_sessions = set()
for doc in db.collection("analysis_results_TEM").stream():
    d = doc.to_dict()
    ar_sessions.add(d.get("sessionId", "?"))
for s in sorted(ar_sessions):
    print(f"  {s}")

# 2. pacientes with nivel_actual or calibracion
print("\n=== pacientes with nivel_actual / calibracion ===")
for doc in db.collection("pacientes").stream():
    d = doc.to_dict()
    na = d.get("nivel_actual")
    cal = d.get("calibracion")
    if na is not None or cal is not None:
        print(f"  {doc.id}:")
        if na is not None:
            print(f"    nivel_actual: {na}")
        if cal is not None:
            if isinstance(cal, dict):
                print(f"    calibracion keys: {sorted(cal.keys())}")
                for ck, cv in sorted(cal.items()):
                    print(f"      {ck}: {cv}")
            else:
                print(f"    calibracion: {cal}")

# 3. Sessions where ALL attempts are pending_analysis vs analyzed
print("\n=== Attempt status breakdown per session (only sessions with attempts) ===")
for doc in db.collection("sesiones_TEM").stream():
    atts = list(
        db.collection("sesiones_TEM")
        .document(doc.id)
        .collection("attempts")
        .stream()
    )
    if not atts:
        continue
    statuses = {}
    for a in atts:
        st = a.to_dict().get("status", "NONE")
        statuses[st] = statuses.get(st, 0) + 1
    print(f"  {doc.id}: {len(atts)} attempts → {statuses}")
