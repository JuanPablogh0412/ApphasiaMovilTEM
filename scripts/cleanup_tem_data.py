"""
Cleanup script — Purge obsolete TEM test data from Firestore.
Keeps: stimuli_TEM, pacientes, terapeutas, terapias, contextos, solicitudes,
       ejercicios_SR, ejercicios_VNEST, and non-TEM ejercicios.

Deletes:
  1. sesiones_TEM        (85 docs) + attempts subcollections (690 docs)
  2. ejercicios_TEM      (68 docs)
  3. ejercicios where terapia=='TEM'  (68 docs)
  4. analysis_results_TEM (14 docs)
"""

import firebase_admin
from firebase_admin import credentials, firestore

if not firebase_admin._apps:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)
db = firestore.client()

BATCH_LIMIT = 450  # Firestore batch limit is 500; leave margin


def delete_collection(col_ref, label, delete_subcollections=None):
    """Delete all docs in a collection, optionally deleting subcollections first."""
    deleted = 0
    errors = 0
    batch = db.batch()
    ops = 0

    for doc in col_ref.stream():
        # Delete subcollections first if specified
        if delete_subcollections:
            for sub_name in delete_subcollections:
                sub_ref = col_ref.document(doc.id).collection(sub_name)
                for sub_doc in sub_ref.stream():
                    batch.delete(sub_ref.document(sub_doc.id))
                    ops += 1
                    if ops >= BATCH_LIMIT:
                        batch.commit()
                        batch = db.batch()
                        ops = 0

        batch.delete(col_ref.document(doc.id))
        ops += 1
        deleted += 1

        if ops >= BATCH_LIMIT:
            batch.commit()
            batch = db.batch()
            ops = 0

    if ops > 0:
        try:
            batch.commit()
        except Exception as e:
            errors += 1
            print(f"  ERROR committing final batch for {label}: {e}")

    print(f"  {label}: {deleted} docs deleted, {errors} errors")
    return deleted


def delete_ejercicios_tem():
    """Delete only TEM entries from the shared 'ejercicios' collection."""
    deleted = 0
    batch = db.batch()
    ops = 0

    for doc in db.collection("ejercicios").stream():
        d = doc.to_dict()
        if d.get("terapia") == "TEM":
            batch.delete(db.collection("ejercicios").document(doc.id))
            ops += 1
            deleted += 1
            if ops >= BATCH_LIMIT:
                batch.commit()
                batch = db.batch()
                ops = 0

    if ops > 0:
        batch.commit()

    print(f"  ejercicios (TEM only): {deleted} docs deleted")
    return deleted


# ── Pre-cleanup counts ──────────────────────────────────────────────
print("=== PRE-CLEANUP COUNTS ===")
pre = {}
for name in ["sesiones_TEM", "ejercicios_TEM", "analysis_results_TEM"]:
    pre[name] = sum(1 for _ in db.collection(name).stream())
    print(f"  {name}: {pre[name]}")
ej_tem = sum(1 for d in db.collection("ejercicios").stream() if d.to_dict().get("terapia") == "TEM")
print(f"  ejercicios (TEM): {ej_tem}")

# Count total attempts
total_atts = 0
for doc in db.collection("sesiones_TEM").stream():
    total_atts += sum(1 for _ in db.collection("sesiones_TEM").document(doc.id).collection("attempts").stream())
print(f"  attempts (total subcollection docs): {total_atts}")

# ── Execute cleanup ─────────────────────────────────────────────────
print("\n=== EXECUTING CLEANUP ===")

print("\n1/4 — sesiones_TEM + attempts subcollections")
delete_collection(
    db.collection("sesiones_TEM"),
    "sesiones_TEM",
    delete_subcollections=["attempts"],
)

print("\n2/4 — ejercicios_TEM")
delete_collection(db.collection("ejercicios_TEM"), "ejercicios_TEM")

print("\n3/4 — ejercicios (TEM only)")
delete_ejercicios_tem()

print("\n4/4 — analysis_results_TEM")
delete_collection(db.collection("analysis_results_TEM"), "analysis_results_TEM")

# ── Post-cleanup verification ───────────────────────────────────────
print("\n=== POST-CLEANUP VERIFICATION ===")
for name in ["sesiones_TEM", "ejercicios_TEM", "analysis_results_TEM"]:
    count = sum(1 for _ in db.collection(name).stream())
    print(f"  {name}: {count} docs")
ej_tem_post = sum(1 for d in db.collection("ejercicios").stream() if d.to_dict().get("terapia") == "TEM")
print(f"  ejercicios (TEM): {ej_tem_post}")

# Verify preserved collections
print("\n=== PRESERVED COLLECTIONS (should be unchanged) ===")
for name in ["stimuli_TEM", "pacientes", "terapeutas", "terapias", "ejercicios_SR", "ejercicios_VNEST"]:
    count = sum(1 for _ in db.collection(name).stream())
    print(f"  {name}: {count} docs")
ej_other = sum(1 for d in db.collection("ejercicios").stream() if d.to_dict().get("terapia") != "TEM")
print(f"  ejercicios (non-TEM): {ej_other}")

print("\n✅ Cleanup complete!")
