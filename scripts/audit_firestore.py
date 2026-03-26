"""Audit script — deep inspection of TEM-related Firestore data."""
import firebase_admin
from firebase_admin import credentials, firestore

if not firebase_admin._apps:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

# 1. Attempt doc fields from Python backend
print("=== Attempt doc fields (SES_1773719222771, s2_a4) ===")
a = (
    db.collection("sesiones_TEM")
    .document("SES_1773719222771")
    .collection("attempts")
    .document("ATT_SES_1773719222771_ST_TEM_N1_001_s2_a4")
    .get()
    .to_dict()
)
for k, v in sorted(a.items()):
    val = str(v)
    if len(val) > 120:
        val = val[:120] + "..."
    print(f"  {k}: {val}")

# 2. Old pre-backend session attempts
print("\n=== SES_1773010694675 (completed, 90 attempts) - sample ===")
atts = list(
    db.collection("sesiones_TEM")
    .document("SES_1773010694675")
    .collection("attempts")
    .limit(3)
    .stream()
)
for a_doc in atts:
    ad = a_doc.to_dict()
    print(f"  {a_doc.id}: status={ad.get('status')} | cl_score={ad.get('clinical_score','NONE')}")

# 3. Pacientes - TEM-related fields
print("\n=== pacientes collection - all fields per doc ===")
for doc in db.collection("pacientes").stream():
    d = doc.to_dict()
    print(f"\n  {doc.id}:")
    for k in sorted(d.keys()):
        val = str(d[k])
        if len(val) > 100:
            val = val[:100] + "..."
        print(f"    {k}: {val}")

# 4. Count total attempts across ALL sessions
print("\n=== Attempts count per session (sessions with >0 attempts) ===")
total_atts = 0
ses_with_atts = []
for doc in db.collection("sesiones_TEM").stream():
    atts = list(
        db.collection("sesiones_TEM")
        .document(doc.id)
        .collection("attempts")
        .stream()
    )
    if atts:
        ses_with_atts.append((doc.id, len(atts), doc.to_dict().get("status", "?")))
        total_atts += len(atts)
print(f"  Total sessions con attempts: {len(ses_with_atts)}")
print(f"  Total attempts globales: {total_atts}")
for sid, cnt, st in ses_with_atts:
    print(f"    {sid}: {cnt} attempts, status={st}")

# 5. Which sessions from SES_1773719222771 have the is_intelligible field?
print("\n=== Check is_intelligible in attempt docs ===")
for a_doc in db.collection("sesiones_TEM").document("SES_1773719222771").collection("attempts").stream():
    ad = a_doc.to_dict()
    has_ii = "is_intelligible" in ad
    print(f"  {a_doc.id}: has_is_intelligible={has_ii}, value={ad.get('is_intelligible', 'MISSING')}")
