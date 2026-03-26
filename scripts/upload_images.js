// =============================================================================
// upload_images.js — Sube imágenes de estímulos a Firebase Storage y actualiza
//                    el campo `imagen_url` en Firestore (stimuli_TEM).
// =============================================================================
//
// Uso:
//   node scripts/upload_images.js
//
// PRERREQUISITOS:
//   - Tener el archivo serviceAccountKey.json en la carpeta scripts/
//   - Las imágenes deben estar en scripts/ImagenesEstimulos/
// =============================================================================

const admin  = require('firebase-admin');
const fs     = require('fs');
const path   = require('path');

// =============================================================================
// Configuración
// =============================================================================

const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'serviceAccountKey.json');
const IMAGES_FOLDER        = path.join(__dirname, 'ImagenesEstimulos');
const PROJECT_ID           = 'apphasia-7a930';
const BUCKET_NEW           = `${PROJECT_ID}.firebasestorage.app`;
const BUCKET_OLD           = `${PROJECT_ID}.appspot.com`;

// Mapeo: nombre de archivo → ID del estímulo en Firestore
const IMAGE_MAP = [
  { file: '1mama.png',    stimulusId: 'ST_TEM_N1_001' },
  { file: '2agua.png',    stimulusId: 'ST_TEM_N1_003' },
  { file: '3papa.png',    stimulusId: 'ST_TEM_N1_002' },
  { file: '4no_se.png',   stimulusId: 'ST_TEM_N1_004' },
  { file: '5ayuda.png',   stimulusId: 'ST_TEM_N1_005' },
  { file: '6gracias.png', stimulusId: 'ST_TEM_N1_006' },
  { file: '7dolor.png',   stimulusId: 'ST_TEM_N1_009' },
  { file: '8hambre.png',  stimulusId: 'ST_TEM_N1_008' },
  { file: '9bien.png',    stimulusId: 'ST_TEM_N1_010' },
];

function getContentType(filename) {
  if (filename.endsWith('.webp')) return 'image/webp';
  if (filename.endsWith('.png'))  return 'image/png';
  if (filename.endsWith('.jpg') || filename.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

async function main() {
  // --- Validaciones ---
  if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
    console.error(`\n❌ No encuentro serviceAccountKey.json en: ${SERVICE_ACCOUNT_PATH}`);
    process.exit(1);
  }
  if (!fs.existsSync(IMAGES_FOLDER)) {
    console.error(`\n❌ No existe la carpeta ImagenesEstimulos en: ${IMAGES_FOLDER}`);
    process.exit(1);
  }

  // --- Inicializar Firebase ---
  admin.initializeApp({
    credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH)),
  });
  const db = admin.firestore();

  // Auto-detectar bucket
  let bucket, BUCKET;
  const bucketNew = admin.storage().bucket(BUCKET_NEW);
  const [existsNew] = await bucketNew.exists();
  if (existsNew) {
    bucket = bucketNew; BUCKET = BUCKET_NEW;
  } else {
    const bucketOld = admin.storage().bucket(BUCKET_OLD);
    const [existsOld] = await bucketOld.exists();
    if (existsOld) {
      bucket = bucketOld; BUCKET = BUCKET_OLD;
    } else {
      console.error('❌ No se encontró ningún bucket de Storage.');
      process.exit(1);
    }
  }

  console.log(`\n🚀 Subiendo imágenes de estímulos → ${BUCKET}\n`);

  let uploaded = 0;
  let skipped  = 0;

  for (const { file, stimulusId } of IMAGE_MAP) {
    const localPath = path.join(IMAGES_FOLDER, file);
    if (!fs.existsSync(localPath)) {
      console.log(`⏭️  Saltando ${file} — no encontrado`);
      skipped++;
      continue;
    }

    const ext         = path.extname(file);
    const storagePath = `tem/images/${stimulusId}${ext}`;
    const contentType = getContentType(file);

    // 1. Subir imagen a Storage
    await bucket.upload(localPath, {
      destination: storagePath,
      metadata: { contentType },
    });

    // 2. Guardar URL gs:// en Firestore (mismo formato que audio_url)
    const gsUrl = `gs://${BUCKET}/${storagePath}`;
    console.log(`📤 ${file} → ${gsUrl}`);

    await db.collection('stimuli_TEM').doc(stimulusId).update({
      imagen_url: gsUrl,
    });
    console.log(`   ✅ stimuli_TEM/${stimulusId}.imagen_url = ${gsUrl}`);

    uploaded++;
  }

  console.log(`\n═══════════════════════════════════════`);
  console.log(`🎉 Completado: ${uploaded} subidas, ${skipped} saltadas`);
  console.log(`═══════════════════════════════════════\n`);

  process.exit(0);
}

main().catch(err => {
  console.error('\n❌ Error:', err.message ?? err);
  process.exit(1);
});
