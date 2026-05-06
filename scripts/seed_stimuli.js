// =============================================================================
// seed_stimuli.js — Carga inicial de estímulos TEM a Firebase
// =============================================================================
//
// Qué hace este script (en orden):
//   1. Lee cada archivo .wav de la carpeta `wavs/`
//   2. Sube el audio a Firebase Storage  →  tem/audio/ST_TEM_Nx_xxx.wav
//   3. Genera el timeline JSON (tiempos aproximados) y lo sube →  tem/timelines/ST_TEM_Nx_xxx.json
//   4. Crea el documento en Firestore  →  stimuli_TEM/ST_TEM_Nx_xxx
//   5. Crea un paciente de prueba en   →  pacientes/{TEST_PATIENT_UID}
//   6. Crea un ejercicio asignado en   →  ejercicios_TEM/{auto-id}
//
// PRERREQUISITOS — ver INSTRUCCIONES_SEED.md antes de correr.
// =============================================================================

const admin = require('firebase-admin');
const fs    = require('fs');
const path  = require('path');
const os    = require('os');

// =============================================================================
// ⚙️  CONFIGURACIÓN — editar estas 2 líneas antes de correr
// =============================================================================

// Ruta al archivo de clave de servicio descargado desde Firebase Console.
const SERVICE_ACCOUNT_PATH = './serviceAccountKey.json';

// UID del usuario de prueba que ya existe en tu Firebase Authentication.
// Puedes obtenerlo en Firebase Console → Authentication → Users → copia el UID.
const TEST_PATIENT_UID = 'JlS6OPiBvqV9QtFIh3kfl9ZdcIk2';

// =============================================================================
// Configuración interna — no necesitas tocar esto
// =============================================================================

// Los proyectos Firebase nuevos usan  projectId.firebasestorage.app
// Los proyectos Firebase viejos usan  projectId.appspot.com
// El script prueba ambos automáticamente si el primero falla.
const PROJECT_ID  = 'apphasia-7a930';
const BUCKET_NEW  = `${PROJECT_ID}.firebasestorage.app`;   // formato nuevo
const BUCKET_OLD  = `${PROJECT_ID}.appspot.com`;           // formato viejo
const WAVS_FOLDER = path.join(__dirname, 'wavs');

// =============================================================================
// Catálogo completo de estímulos — Nivel 1 (10 frases)
// =============================================================================
//
// Si tu compañero solo entregó 9, el script simplemente saltará el que falte
// y te dirá cuál es. Puedes correr el script de nuevo cuando llegue el décimo.
//
const STIMULI_N1 = [
  {
    id:             'ST_TEM_N1_001',
    texto:          'mamá',
    syllables:      ['ma', 'má'],
    patron_tonal:   'LH',
    categoria:      'vinculo_familiar',
    pregunta_texto: "¿Eso que dijiste fue 'mamá'?",
  },
  {
    id:             'ST_TEM_N1_002',
    texto:          'papá',
    syllables:      ['pa', 'pá'],
    patron_tonal:   'LH',
    categoria:      'vinculo_familiar',
    pregunta_texto: "¿Eso que dijiste fue 'papá'?",
  },
  {
    id:             'ST_TEM_N1_003',
    texto:          'agua',
    syllables:      ['a', 'gua'],
    patron_tonal:   'HL',
    categoria:      'necesidad_basica',
    pregunta_texto: "¿Eso que dijiste fue 'agua'?",
  },
  {
    id:             'ST_TEM_N1_004',
    texto:          'no sé',
    syllables:      ['no', 'sé'],
    patron_tonal:   'LH',
    categoria:      'comunicacion',
    pregunta_texto: "¿Eso que dijiste fue 'no sé'?",
  },
  {
    id:             'ST_TEM_N1_005',
    texto:          'ayuda',
    syllables:      ['a', 'yu', 'da'],
    patron_tonal:   'LHL',
    categoria:      'necesidad_basica',
    pregunta_texto: "¿Eso que dijiste fue 'ayuda'?",
  },
  {
    id:             'ST_TEM_N1_006',
    texto:          'gracias',
    syllables:      ['gra', 'cias'],
    patron_tonal:   'HL',
    categoria:      'cortesia',
    pregunta_texto: "¿Eso que dijiste fue 'gracias'?",
  },
  {
    id:             'ST_TEM_N1_007',
    texto:          'casa',
    syllables:      ['ca', 'sa'],
    patron_tonal:   'HL',
    categoria:      'lugar',
    pregunta_texto: "¿Eso que dijiste fue 'casa'?",
  },
  {
    id:             'ST_TEM_N1_008',
    texto:          'hambre',
    syllables:      ['ham', 'bre'],
    patron_tonal:   'HL',
    categoria:      'necesidad_basica',
    pregunta_texto: "¿Eso que dijiste fue 'hambre'?",
  },
  {
    id:             'ST_TEM_N1_009',
    texto:          'dolor',
    syllables:      ['do', 'lor'],
    patron_tonal:   'LH',
    categoria:      'necesidad_basica',
    pregunta_texto: "¿Eso que dijiste fue 'dolor'?",
  },
  {
    id:             'ST_TEM_N1_010',
    texto:          'bien',
    syllables:      ['bien'],
    patron_tonal:   'H',
    categoria:      'evaluacion',
    pregunta_texto: "¿Eso que dijiste fue 'bien'?",
  },
];

// =============================================================================
// Lectura de duración real del WAV (sin dependencias externas)
// Lee los chunks RIFF/fmt/data del header binario para obtener los ms exactos.
// =============================================================================

function readWavDurationMs(filePath) {
  const buf = fs.readFileSync(filePath);

  if (buf.toString('ascii', 0, 4) !== 'RIFF' ||
      buf.toString('ascii', 8, 12) !== 'WAVE') {
    throw new Error(`Archivo no válido (no es RIFF/WAVE): ${filePath}`);
  }

  let byteRate = 0;
  let dataBytes = 0;
  let offset = 12; // después de 'RIFF....WAVE'

  while (offset < buf.length - 8) {
    const chunkId   = buf.toString('ascii', offset, offset + 4);
    const chunkSize = buf.readUInt32LE(offset + 4);

    if (chunkId === 'fmt ') {
      // fmt data: audioFormat(2) + numChannels(2) + sampleRate(4) + byteRate(4) ...
      byteRate = buf.readUInt32LE(offset + 16);
    } else if (chunkId === 'data') {
      dataBytes = chunkSize;
      break;
    }

    offset += 8 + chunkSize + (chunkSize % 2); // los chunks WAV están alineados a 2 bytes
  }

  if (byteRate === 0) throw new Error(`No se pudo leer el chunk fmt en: ${filePath}`);
  if (dataBytes === 0) throw new Error(`No se encontró el chunk data en: ${filePath}`);

  return Math.round((dataBytes / byteRate) * 1000); // ms exactos
}

// =============================================================================
// Generación de tiempos proporcionales a la duración REAL del audio
//
// Estrategia:
//   - Se lee la duración exacta del WAV en ms.
//   - Se deja un pequeño silencio inicial (≤80 ms) y final (≤50 ms).
//   - Se distribuyen las sílabas de forma equiespaciada en lo que queda.
//   - El último onset se extiende hasta el final del audio.
//
// Así `totalDuration` de LipTimeline = audio_duration_ms, y el mapping
//   controller.value = position / totalDuration
// queda perfectamente a escala 1:1 con el audio real.
// =============================================================================

function generateTimingFromWav(syllables, wavPath) {
  const audio_duration_ms = readWavDurationMs(wavPath);
  const n = syllables.length;

  if (n === 0) return { onsets_ms: [], durations_ms: [], audio_duration_ms };

  // Silencias naturales al inicio y al final
  const silenceStart = Math.min(80,  Math.round(audio_duration_ms * 0.08));
  const silenceEnd   = Math.min(50,  Math.round(audio_duration_ms * 0.05));
  const available    = audio_duration_ms - silenceStart - silenceEnd;

  if (available <= 0) {
    // Audio demasiado corto: spacing uniforme sin silencios
    const spacing = Math.max(100, Math.round(audio_duration_ms / n));
    const onsets_ms    = syllables.map((_, i) => i * spacing);
    const durations_ms = syllables.map(() => spacing - 20);
    return { onsets_ms, durations_ms, audio_duration_ms };
  }

  const spacing = Math.round(available / n);

  const onsets_ms = syllables.map((_, i) => silenceStart + i * spacing);

  // La última sílaba se extiende hasta el fin del audio;
  // las demás duran (spacing - 20ms) dejando un pequeño gap entre ellas.
  const durations_ms = syllables.map((_, i) => {
    if (i === n - 1) return audio_duration_ms - onsets_ms[i]; // hasta el final
    return Math.max(50, spacing - 20);                         // gap natural
  });

  return { onsets_ms, durations_ms, audio_duration_ms };
}

// =============================================================================
// Subida a Firebase Storage
// =============================================================================

async function uploadFile(bucket, bucketName, localPath, storagePath) {
  await bucket.upload(localPath, {
    destination: storagePath,
    metadata: { contentType: localPath.endsWith('.wav') ? 'audio/wav' : 'application/json' },
  });
  return `gs://${bucketName}/${storagePath}`;
}

// =============================================================================
// Script principal
// =============================================================================

async function main() {
  // --- Validaciones previas ------------------------------------------------

  if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
    console.error(`\n❌ No encuentro el archivo de clave de servicio en: ${SERVICE_ACCOUNT_PATH}`);
    console.error('   Descárgalo desde Firebase Console → Configuración → Cuentas de servicio → Generar clave.');
    process.exit(1);
  }

  if (TEST_PATIENT_UID === 'REEMPLAZA_CON_TU_UID') {
    console.error('\n❌ Debes reemplazar TEST_PATIENT_UID con tu UID real de Firebase Authentication.');
    console.error('   Encuéntralo en Firebase Console → Authentication → Users.');
    process.exit(1);
  }

  if (!fs.existsSync(WAVS_FOLDER)) {
    console.error(`\n❌ No existe la carpeta "wavs/" en: ${WAVS_FOLDER}`);
    console.error('   Crea la carpeta y mueve los archivos .wav allí.');
    process.exit(1);
  }

  // --- Inicializar Firebase Admin ------------------------------------------

  admin.initializeApp({
    credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH)),
  });

  const db = admin.firestore();

  // Auto-detectar nombre del bucket (nuevo: .firebasestorage.app / viejo: .appspot.com)
  let bucket;
  let BUCKET;
  process.stdout.write('\n🔍 Buscando bucket de Firebase Storage...');
  const bucketNew = admin.storage().bucket(BUCKET_NEW);
  const [existsNew] = await bucketNew.exists();
  if (existsNew) {
    bucket = bucketNew;
    BUCKET = BUCKET_NEW;
    console.log(` encontrado → ${BUCKET_NEW}`);
  } else {
    const bucketOld = admin.storage().bucket(BUCKET_OLD);
    const [existsOld] = await bucketOld.exists();
    if (existsOld) {
      bucket = bucketOld;
      BUCKET = BUCKET_OLD;
      console.log(` encontrado → ${BUCKET_OLD}`);
    } else {
      console.log(' ❌ no encontrado');
      console.error('\n❌ No existe ningún bucket de Storage para este proyecto.');
      console.error('   Ve a Firebase Console → Storage → clic en "Comenzar" para activarlo.');
      console.error(`   Probados: ${BUCKET_NEW}  y  ${BUCKET_OLD}`);
      process.exit(1);
    }
  }

  console.log('\n🚀 Iniciando carga de estímulos TEM — Nivel 1');
  console.log(`   Proyecto: ${PROJECT_ID}`);
  console.log(`   Bucket:   ${BUCKET}`);
  console.log(`   Carpeta WAVs: ${WAVS_FOLDER}\n`);

  const stimuliSubidos = [];
  const stimuliSaltados = [];

  // --- Procesar cada estímulo ----------------------------------------------

  for (const stim of STIMULI_N1) {
    const wavName  = `${stim.id}.wav`;
    const wavLocal = path.join(WAVS_FOLDER, wavName);

    if (!fs.existsSync(wavLocal)) {
      console.log(`⏭️  Saltando ${stim.id} — "${stim.texto}" (archivo ${wavName} no encontrado)`);
      stimuliSaltados.push(stim.id);
      continue;
    }

    console.log(`\n📤 ${stim.id} — "${stim.texto}" (${stim.syllables.length} sílaba${stim.syllables.length > 1 ? 's' : ''})`);

    // 1. Subir WAV
    const audioStoragePath = `tem/audio/${wavName}`;
    const audio_url = await uploadFile(bucket, BUCKET, wavLocal, audioStoragePath);
    console.log(`   ✅ Audio → ${audio_url}`);

    // 2. Calcular timing proporcional a la duración REAL del WAV
    const { onsets_ms, durations_ms, audio_duration_ms } =
        generateTimingFromWav(stim.syllables, wavLocal);
    console.log(`   ⏱  Duración real: ${audio_duration_ms} ms → ` +
        `onsets: [${onsets_ms.join(', ')}] ms`);

    // 3. Generar timeline JSON y subir
    const timelineJson = { syllables: stim.syllables, onsets_ms, durations_ms,
                            audio_duration_ms };
    const jsonName     = `${stim.id}.json`;
    const tmpJsonPath  = path.join(os.tmpdir(), jsonName);
    fs.writeFileSync(tmpJsonPath, JSON.stringify(timelineJson, null, 2));

    const timelineStoragePath = `tem/timelines/${jsonName}`;
    const timeline_url = await uploadFile(bucket, BUCKET, tmpJsonPath, timelineStoragePath);
    console.log(`   ✅ Timeline → ${timeline_url}`);

    // Limpiar tmp
    fs.unlinkSync(tmpJsonPath);

    // 3. Crear documento Firestore
    const docData = {
      texto:               stim.texto,
      syllables:           stim.syllables,
      onsets_ms,
      durations_ms,
      audio_duration_ms,   // duración exacta del WAV → usada por LipTimeline
      audio_url,
      timeline_url,
      nivel_clinico:       1,
      patron_tonal:        stim.patron_tonal,
      num_silabas:         stim.syllables.length,
      num_completions:     0,
      fallos_consecutivos: 0,
      categoria:           stim.categoria,
      pregunta:            stim.pregunta_texto,
      imagen_url:          '',
    };

    await db.collection('stimuli_TEM').doc(stim.id).set(docData);
    console.log(`   ✅ Firestore → stimuli_TEM/${stim.id}`);

    stimuliSubidos.push(stim.id);
  }

  // --- Crear paciente de prueba -------------------------------------------

  await db.collection('pacientes').doc(TEST_PATIENT_UID).set(
    {
      nombre:       'Paciente Prueba',
      nivel_actual: 1,
      createdAt:    admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },   // no sobrescribe si ya existe
  );
  console.log(`\n✅ Paciente → pacientes/${TEST_PATIENT_UID}`);

  // --- Crear ejercicio asignado -------------------------------------------

  if (stimuliSubidos.length > 0) {
    const ejercicioRef = db.collection('ejercicios_TEM').doc();
    await ejercicioRef.set({
      pacienteId:  TEST_PATIENT_UID,
      stimulusIds: stimuliSubidos,
      nivel:       1,
      activo:      true,
      createdAt:   admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`✅ Ejercicio → ejercicios_TEM/${ejercicioRef.id}`);
  }

  // --- Resumen final -------------------------------------------------------

  console.log('\n═══════════════════════════════════════');
  console.log(`🎉 Completado`);
  console.log(`   Subidos:  ${stimuliSubidos.length} estímulos (${stimuliSubidos.join(', ')})`);
  if (stimuliSaltados.length > 0) {
    console.log(`   Faltantes: ${stimuliSaltados.length} estímulos (${stimuliSaltados.join(', ')})`);
    console.log(`   ➡️  Cuando tengas esos WAVs, vuelve a correr el script — solo procesará los que faltan.`);
  }
  console.log(`\n   Abre la app con el UID: ${TEST_PATIENT_UID}`);
  console.log('═══════════════════════════════════════\n');

  process.exit(0);
}

main().catch(err => {
  console.error('\n❌ Error inesperado:', err.message ?? err);
  process.exit(1);
});
