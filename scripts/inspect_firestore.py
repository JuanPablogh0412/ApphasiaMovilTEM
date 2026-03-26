#!/usr/bin/env python3
"""
inspect_firestore.py — Muestra la estructura de las colecciones existentes
para entender el esquema antes de adaptar TEM.

Imprime todos los documentos de:
  - terapias          (colección de nivel superior)
  - ejercicios        (primeros 3, para ver campos)
  - ejercicios_SR     (primeros 2, para ver campos)

Cómo correr:
  cd scripts
  python inspect_firestore.py
"""

import json, os
import firebase_admin
from firebase_admin import credentials, firestore

SERVICE_ACCOUNT_KEY = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")

if not firebase_admin._apps:
    cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
    firebase_admin.initialize_app(cred)

db = firestore.client()

def dump_collection(name, limit=3):
    print(f"\n{'='*60}")
    print(f"  Colección: {name}  (máx {limit} docs)")
    print(f"{'='*60}")
    docs = list(db.collection(name).limit(limit).stream())
    if not docs:
        print("  (vacía o no existe)")
        return
    for doc in docs:
        data = doc.to_dict()
        # Convertir timestamps a string para poder serializar
        safe = {}
        for k, v in data.items():
            try:
                json.dumps(v)
                safe[k] = v
            except Exception:
                safe[k] = str(v)
        print(f"\n  Doc ID: {doc.id}")
        print(json.dumps(safe, indent=4, ensure_ascii=False))

dump_collection("terapias", limit=10)
dump_collection("ejercicios", limit=3)
dump_collection("ejercicios_SR", limit=2)
