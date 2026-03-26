# Instrucciones para subir los estímulos a Firebase

> Hazlo desde tu computador. Solo necesitas hacer esto **una vez** por nivel.

---

## Paso 1 — Instalar Node.js (si no lo tienes)

1. Ve a **https://nodejs.org** y descarga la versión **LTS**
2. Instala con las opciones por defecto
3. Verifica la instalación abriendo una terminal y escribiendo:
   ```
   node --version
   ```
   Debe mostrar algo como `v20.x.x`

---

## Paso 2 — Descargar la clave de servicio de Firebase

Esta clave le da permiso al script para escribir en tu Firebase.

1. Ve a **https://console.firebase.google.com**
2. Selecciona el proyecto **apphasia-7a930**
3. Clic en el ícono de engranaje (⚙️) → **Configuración del proyecto**
4. Pestaña **Cuentas de servicio**
5. Botón **Generar nueva clave privada** → confirmar → se descarga un `.json`
6. Renombra ese archivo a exactamente `serviceAccountKey.json`
7. Muévelo a la carpeta `scripts/` del proyecto (donde está este archivo)

> ⚠️ **Nunca subas este archivo a Git.** Está en `.gitignore`. Si lo pierdes, genera uno nuevo.

---

## Paso 3 — Obtener tu UID de Firebase Authentication

El script necesita saber a qué usuario de prueba asignarle los ejercicios.

1. Ve a Firebase Console → **Authentication** → pestaña **Users**
2. Si ya tienes un usuario (el que usas para probar la app), copia su **UID** (es la columna "Identificador del usuario", una cadena como `abc123...`)
3. Si no tienes ningún usuario, crea uno con **Agregar usuario** → ponle cualquier correo y contraseña → copia el UID

---

## Paso 4 — Configurar el script

Abre el archivo `scripts/seed_stimuli.js` y edita la línea:

```js
const TEST_PATIENT_UID = 'REEMPLAZA_CON_TU_UID';
```

Reemplaza `REEMPLAZA_CON_TU_UID` con el UID que copiaste. Ejemplo:

```js
const TEST_PATIENT_UID = 'pQr7sT9uVwXyZ0aBcDeF';
```

---

## Paso 5 — Colocar los archivos WAV

1. Dentro de la carpeta `scripts/`, crea una carpeta llamada `wavs`
2. Mueve los archivos que te pasó tu compañero ahí dentro
3. Verifica que los nombres sean **exactamente** estos (sin mayúsculas, sin espacios):

```
scripts/
└── wavs/
    ├── ST_TEM_N1_001.wav
    ├── ST_TEM_N1_002.wav
    ├── ST_TEM_N1_003.wav
    ├── ST_TEM_N1_004.wav
    ├── ST_TEM_N1_005.wav
    ├── ST_TEM_N1_006.wav
    ├── ST_TEM_N1_007.wav
    ├── ST_TEM_N1_008.wav
    └── ST_TEM_N1_009.wav   ← (el décimo puede faltar, el script lo saltará)
```

---

## Paso 6 — Instalar dependencias y correr el script

Abre una terminal, entra a la carpeta `scripts/` y ejecuta:

```powershell
cd scripts
npm install
node seed_stimuli.js
```

El script te irá mostrando el progreso en pantalla. Al final verás algo como:

```
🎉 Completado
   Subidos:  9 estímulos (ST_TEM_N1_001, ST_TEM_N1_002, ...)
   Faltantes: 1 estímulos (ST_TEM_N1_010)
   ➡️  Cuando tengas esos WAVs, vuelve a correr el script — solo procesará los que faltan.

   Abre la app con el UID: pQr7sT9uVwXyZ0aBcDeF
```

---

## Paso 7 — Verificar en Firebase Console

Antes de probar la app, confirma en la consola que todo llegó:

1. **Storage** → carpeta `tem/audio/` → deberías ver 9 archivos `.wav`
2. **Storage** → carpeta `tem/timelines/` → deberías ver 9 archivos `.json`
3. **Firestore** → colección `stimuli_TEM` → deberías ver 9 documentos
4. **Firestore** → colección `pacientes` → deberías ver 1 documento con tu UID
5. **Firestore** → colección `ejercicios_TEM` → deberías ver 1 documento

---

## Paso 8 — Probar la app

Ya puedes correr la app. El usuario con el UID configurado verá los 9 estímulos disponibles y podrá iniciar una sesión TEM.

---

## Si algo falla

| Error en consola | Qué significa | Solución |
|------------------|---------------|----------|
| `No encuentro el archivo de clave de servicio` | Falta `serviceAccountKey.json` | Revisa el Paso 2 |
| `Debes reemplazar TEST_PATIENT_UID` | Olvidaste editar el script | Revisa el Paso 4 |
| `No existe la carpeta "wavs/"` | Falta la carpeta | Revisa el Paso 5 |
| `PERMISSION_DENIED` | La clave de servicio no tiene permisos | Verifica las reglas de Firestore/Storage en Firebase Console |
| `Cannot find module 'firebase-admin'` | No corriste `npm install` | Corre `npm install` en la carpeta `scripts/` |

---

## Cuando llegue el estímulo 10 ("bien")

1. Coloca `ST_TEM_N1_010.wav` en la carpeta `scripts/wavs/`
2. Corre el script de nuevo:
   ```
   node seed_stimuli.js
   ```
   El script detectará que los 9 anteriores ya existen en Firestore y solo subirá el nuevo.

   > Nota: actualmente el script usa `set()` que sobreescribe — para una versión futura puedes pedir que se cambie a `create()` para saltar los que ya existen.
