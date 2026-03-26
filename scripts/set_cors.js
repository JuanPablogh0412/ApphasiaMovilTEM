// =============================================================================
// set_cors.js — Configura CORS en el bucket de Firebase Storage para que
//               Flutter Web (CanvasKit) pueda cargar imágenes via fetch().
// =============================================================================
//
// Uso:   node scripts/set_cors.js
//
// PRERREQUISITOS:
//   - Tener el archivo serviceAccountKey.json en la carpeta scripts/
// =============================================================================

const admin = require('firebase-admin');
const path  = require('path');

const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'serviceAccountKey.json');
const PROJECT_ID           = 'apphasia-7a930';
const BUCKET_NAME          = `${PROJECT_ID}.firebasestorage.app`;

if (!admin.apps.length) {
  admin.initializeApp({
    credential:  admin.credential.cert(require(SERVICE_ACCOUNT_PATH)),
    storageBucket: BUCKET_NAME,
  });
}

async function main() {
  const bucket = admin.storage().bucket(BUCKET_NAME);

  const corsConfig = [
    {
      origin:       ['*'],           // Permite cualquier origen (localhost, dominio de prod, etc.)
      method:       ['GET'],         // Solo lecturas — no necesitamos PUT/POST desde el navegador
      maxAgeSeconds: 3600,
      responseHeader: ['Content-Type'],
    },
  ];

  await bucket.setCorsConfiguration(corsConfig);
  console.log(`✅ CORS configurado en gs://${BUCKET_NAME}`);
  console.log(JSON.stringify(corsConfig, null, 2));
}

main().catch((err) => {
  console.error('❌ Error configurando CORS:', err);
  process.exit(1);
});
