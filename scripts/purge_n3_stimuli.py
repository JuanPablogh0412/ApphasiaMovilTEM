"""
purge_n3_stimuli.py — Elimina de Firestore todos los estímulos de nivel 3
                       EXCEPTO el estímulo de prueba con triple audio/video.

Qué hace:
  1. Consulta stimuli_TEM donde nivel_clinico == 3
  2. Excluye KEEP_ID (el único con triple grabación, el de prueba)
  3. Muestra la lista de documentos a eliminar (DRY-RUN) y pide confirmación
  4. Elimina los documentos en batches (máx. 450 ops)

IMPORTANTE:
  - Los archivos en Firebase Storage NO se eliminan (quedan huérfanos pero
    sin impacto funcional ni coste relevante).
  - Esta operación es irreversible en Firestore.

Uso:
  cd scripts
  python purge_n3_stimuli.py
"""

import firebase_admin
from firebase_admin import credentials, firestore

# ─────────────────────────────────────────────────────────────────────
# Configuración
# ─────────────────────────────────────────────────────────────────────

KEEP_ID = 'ST_TEM_N3_1777512008117'   # estímulo de prueba — NO borrar
BATCH_LIMIT = 450                      # margen bajo el límite real de 500

# ─────────────────────────────────────────────────────────────────────
# Inicializar Firebase Admin
# ─────────────────────────────────────────────────────────────────────

if not firebase_admin._apps:
    cred = credentials.Certificate('serviceAccountKey.json')
    firebase_admin.initialize_app(cred)
db = firestore.client()

# ─────────────────────────────────────────────────────────────────────
# Paso 1: Obtener candidatos a borrar
# ─────────────────────────────────────────────────────────────────────

print('Consultando stimuli_TEM con nivel_clinico == 3 ...')
docs = list(
    db.collection('stimuli_TEM')
    .where('nivel_clinico', '==', 3)
    .stream()
)

to_delete = [d for d in docs if d.id != KEEP_ID]
kept = [d for d in docs if d.id == KEEP_ID]

print(f'\nTotal N3 encontrados : {len(docs)}')
print(f'  → Se mantiene      : {len(kept)}  ({KEEP_ID})')
print(f'  → A eliminar       : {len(to_delete)}')

if not to_delete:
    print('\nNada que eliminar. Saliendo.')
    exit(0)

# ─────────────────────────────────────────────────────────────────────
# Paso 2: DRY-RUN — listar IDs a borrar
# ─────────────────────────────────────────────────────────────────────

print('\n─── Documentos que serán ELIMINADOS ────────────────────────────')
for d in to_delete:
    data = d.to_dict()
    texto = data.get('texto', '(sin texto)')
    estado = data.get('estado', '?')
    print(f'  {d.id}  |  "{texto}"  |  estado={estado}')
print('─────────────────────────────────────────────────────────────────')

# ─────────────────────────────────────────────────────────────────────
# Paso 3: Confirmación interactiva
# ─────────────────────────────────────────────────────────────────────

print(f'\n⚠️  Esta acción es IRREVERSIBLE en Firestore.')
respuesta = input(f'  ¿Eliminar los {len(to_delete)} documentos? [escribir "si" para confirmar]: ')

if respuesta.strip().lower() != 'si':
    print('Operación cancelada.')
    exit(0)

# ─────────────────────────────────────────────────────────────────────
# Paso 4: Eliminar en batches
# ─────────────────────────────────────────────────────────────────────

print('\nEliminando ...')
batch = db.batch()
ops = 0
deleted = 0
errors = 0

for d in to_delete:
    batch.delete(db.collection('stimuli_TEM').document(d.id))
    ops += 1
    deleted += 1
    if ops >= BATCH_LIMIT:
        try:
            batch.commit()
        except Exception as e:
            errors += 1
            print(f'  ERROR en batch: {e}')
        batch = db.batch()
        ops = 0

if ops > 0:
    try:
        batch.commit()
    except Exception as e:
        errors += 1
        print(f'  ERROR en batch final: {e}')

# ─────────────────────────────────────────────────────────────────────
# Resultado
# ─────────────────────────────────────────────────────────────────────

print(f'\nListo. {deleted} documentos eliminados, {errors} errores.')
print(f'Estímulo de prueba preservado: {KEEP_ID}')
