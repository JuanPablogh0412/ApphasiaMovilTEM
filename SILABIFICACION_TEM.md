# Separación de Sílabas en el Módulo TEM

> **Propósito:** Explicar cómo funciona la silabificación en la app móvil y qué estrategia debe adoptar el portal web al momento de crear estímulos TEM.

---

## Resumen ejecutivo

La app móvil **no silabifica automáticamente** las frases al crear estímulos. Las sílabas son definidas manualmente y almacenadas en Firestore. La función `syllabify()` que existe en Flutter sirve exclusivamente para generar animación labial (visemas), **no** para crear el campo `syllables` de un estímulo.

Para el portal web, la recomendación es combinar dos cosas:
1. **Silabificador automático** como sugerencia inicial (NLP en JavaScript/Python).
2. **Revisión manual del terapeuta** antes de guardar — es obligatoria porque el estímulo fija el patrón de análisis acústico para siempre.

---

## 1. Cómo se crean los estímulos hoy (flujo completo)

La creación de un estímulo TEM tiene **tres etapas** que son independientes:

### Etapa 1 — Definición manual de sílabas (`scripts/seed_stimuli.js`)

Las sílabas de cada estímulo se definen **a mano** en el catálogo seed. Ejemplo:

```javascript
{ texto: 'mamá',    syllables: ['ma', 'má'] }
{ texto: 'ayuda',   syllables: ['a', 'yu', 'da'] }
{ texto: 'no sé',   syllables: ['no', 'sé'] }
{ texto: 'gracias', syllables: ['gra', 'cias'] }
{ texto: 'hambre',  syllables: ['ham', 'bre'] }
{ texto: 'agua',    syllables: ['a', 'gua'] }
```

Estas sílabas, junto con el texto, se suben a Firestore en `stimuli_TEM/{id}`.

Esta etapa NO usa ningún algoritmo — es decisión humana, considerando cómo el clínico quiere que el paciente articule la frase.

### Etapa 2 — Timings aproximados automáticos (`scripts/seed_stimuli.js`)

Una vez conocida la duración del WAV de referencia, el script genera timings de sílabas distribuyendo el tiempo de audio proporcionalmente:

```javascript
function generateTimingFromWav(syllables, wavPath) {
  const audio_duration_ms = readWavDurationMs(wavPath);
  const n = syllables.length;

  const silenceStart = Math.min(80,  audio_duration_ms * 0.08);
  const silenceEnd   = Math.min(50,  audio_duration_ms * 0.05);
  const available    = audio_duration_ms - silenceStart - silenceEnd;
  const spacing      = available / n;

  const onsets_ms    = syllables.map((_, i) => silenceStart + i * spacing);
  const durations_ms = syllables.map((_, i) =>
    i === n - 1
      ? audio_duration_ms - onsets_ms[i]   // última: hasta el final
      : Math.max(50, spacing - 20)          // las demás: spacing con gap
  );

  return { onsets_ms, durations_ms, audio_duration_ms };
}
```

Esto produce `onsets_ms` y `durations_ms` que se guardan en Firestore junto a las sílabas.

### Etapa 3 — Alineación precisa con Whisper (`scripts/align_stimuli.py`)

Opcionalmente, se ejecuta un script Python que usa **OpenAI Whisper** para obtener los timestamps reales de cada palabra en el audio. Luego distribuye las sílabas dentro de cada palabra proporcionalmente:

```python
def distribute_syllables_in_word(syllables, word_start_ms, word_end_ms):
    n = len(syllables)
    span = word_end_ms - word_start_ms
    spacing = span / n
    result = []
    for i, _ in enumerate(syllables):
        onset_ms = round(word_start_ms + i * spacing)
        duration_ms = max(30, round(spacing) - 10) if i < n-1 \
                      else word_end_ms - onset_ms      # última llega al final
        result.append({"onset_ms": onset_ms, "duration_ms": max(30, duration_ms)})
    return result
```

El resultado actualiza los campos `onsets_ms`, `durations_ms` y `audio_duration_ms` en Firestore.

**Nótese:** Whisper se usa para timestamps de palabras, no para silabificar. La separación de sílabas sigue siendo manual.

---

## 2. El `syllabify()` de Flutter — para qué sirve (y para qué NO)

Existe la función `syllabify()` en `lib/data/models/tem/lip_timeline.dart`. Es tentador pensar que es el motor de silabificación para crear estímulos, pero **no lo es**.

### Para qué SÍ sirve

Toma una sílaba ya definida (como `"gra"`, `"cias"`, `"ham"`) y la descompone en sus partes fonéticas (onset, nucleus, coda) para producir animación de labios (visemas). Es una función interna del reproductor visual.

```
"gra"  →  onset="gr"  nucleus="a"  coda=""   →  visema-g → visema-r → visema-a
"cias" →  onset="c"   nucleus="ia" coda="s"  →  visema-c → diptongo(i,a) → visema-s
"ham"  →  onset="h"   nucleus="a"  coda="m"  →  visema-h → visema-a → visema-m
```

### Para qué NO sirve

No toma una frase completa (`"hora de comer"`) y la divide en sílabas (`["ho","ra","de","co","mer"]`). Ese trabajo lo hace el terapeuta (o en el futuro, el portal web).

### El algoritmo interno (por si es útil de referencia)

Implementa el **Principio del Onset Máximo** del español con estas reglas:

| Regla | Descripción |
|-------|-------------|
| Dígrafos | `ch`, `ll`, `rr`, `qu`, `gu` → se codifican como carácter único antes de procesar |
| Diptongos | Vocales débiles (`i`, `u`) con fuertes (`a`, `e`, `o`) → una sola sílaba |
| Hiatos | Dos vocales fuertes juntas → sílabas separadas |
| Clusters de consonantes | `pr`, `pl`, `br`, `bl`, `tr`, `dr`, `cr`, `cl`, `fr`, `fl`, `gr`, `gl` → van juntos al onset de la siguiente sílaba |
| Consonante entre vocales | Va al onset de la sílaba siguiente (`ca-sa`, `pa-pá`) |
| Dos consonantes entre vocales | Se divide: primera a la coda anterior, segunda al onset siguiente (`ham-bre`) |
| Tres o más consonantes | Las dos últimas van al onset si forman cluster válido (`trans-por-te`) |

---

## 3. Reglas de silabificación del español relevantes para TEM

Para que el portal web pueda asistir al terapeuta, aquí están las reglas que se deben implementar:

### 3.1 Vocales — núcleo de toda sílaba

Toda sílaba tiene exactamente una vocal (o un diptongo). Las vocales son:
`a, e, i, o, u, á, é, í, ó, ú, ü`

Vocales **fuertes**: `a, e, o, á, é, ó`  
Vocales **débiles**: `i, u, í, ú`

### 3.2 Diptongos (vocal débil + fuerte o viceversa → misma sílaba)

```
ai, au, ei, eu, oi, ou
ia, ie, io, ua, ue, uo
iu, ui
(y sus versiones acentuadas)
```

Ejemplos:
- `agua` → `a-gua` (ua = diptongo)
- `bien` → `bien` (ie = diptongo, sílaba única)
- `gracias` → `gra-cias` (ia = diptongo)

Excepción: Si la vocal débil lleva tilde, **rompe el diptongo** (hiato):
- `día` → `dí-a` (no diptongo)
- `país` → `pa-ís`

### 3.3 Hiatos (dos vocales fuertes → sílabas separadas)

```
aa, ae, ao, ea, ee, eo, oa, oe, oo
```

Ejemplos:
- `teatro` → `te-a-tro`
- `poeta` → `po-e-ta`

### 3.4 Dígrafos (se tratan como una sola consonante)

| Dígrafo | Ejemplo |
|---------|---------|
| `ch` | `mu-cho` |
| `ll` | `ca-lle` |
| `rr` | `ca-rro` |
| `qu` | `que-so` (la `u` es muda) |
| `gu` | `gue-rra` (la `u` es muda) |

### 3.5 Consonante entre dos vocales → va con la siguiente sílaba

```
ca·sa → ca-sa       (s va al onset de "sa")
pa·pá → pa-pá       (p va al onset de "pá")
mo·ma → mo-ma
```

### 3.6 Dos consonantes entre vocales

Si las dos forman un **cluster válido** (`pr`, `br`, `tr`, `gr`, etc.), van juntas al onset siguiente:
```
ma·dre → ma-dre     (dr = cluster → va junto)
si·glo → si-glo     (gl = cluster → va junto)
a·pren·der → a-pren-der
```

Si NO forman cluster válido, se separan:
```
ham·bre → ham-bre   (mb: m va a coda, br va al onset)
con·tar → con-tar   (nt: n va a coda, t va al onset)
```

Clusters válidos: `pr, pl, br, bl, tr, dr, cr, cl, fr, fl, gr, gl`

### 3.7 Tres o más consonantes entre vocales

Las dos últimas van al onset siguiente si forman cluster válido; el resto va a la coda:
```
trans·por·te → trans-por-te   (nsp: sp = no cluster, n+s → coda, p → onset)
cons·truir → cons-truir        (str = no cluster directo: s → coda, tr → onset)
```

### 3.8 Palabras separadas en una frase → silabificar independientemente

Para frases de múltiples palabras, cada palabra se silabifica por separado:
```
"no sé"         → ["no", "sé"]
"hora de comer" → ["ho", "ra", "de", "co", "mer"]
"buenos días"   → ["bue", "nos", "dí", "as"]
```

El campo `words` en el catálogo del script de alineación refleja esto:
```python
{"texto": "no sé",  "syllables": ["no", "sé"],  "words": [["no"], ["sé"]]}
```

---

## 4. Implementación — Silabificador completo para JavaScript/React

Esta es la **traducción directa del algoritmo `syllabify()` de Flutter** (`lib/data/models/tem/lip_timeline.dart`) portado a JavaScript. Implementa el Principio del Onset Máximo con todas las reglas del español colombiano usadas en la app móvil. Es completamente autocontenido, sin dependencias externas, y funciona con cualquier palabra o frase.

### 4.1 Módulo `syllabifier.js`

```javascript
// syllabifier.js
// Silabificador del español — puerto del algoritmo usado en la app móvil Flutter.
// Principio del Onset Máximo (RAE) con soporte de dígrafos, diptongos y clusters.

const DIPHTHONGS = new Set([
  'ai','au','ei','eu','oi','ou',
  'ia','ie','io','ua','ue','uo',
  'iu','ui',
  // con tilde en la fuerte (no rompen el diptongo)
  'ái','áu','éi','éu','ói',
  'iá','ié','ió','uá','ué','uó',
]);

// Clusters de consonantes que van JUNTOS al onset de la siguiente sílaba
const ONSET_CLUSTERS = new Set([
  'pr','pl','br','bl','tr','dr',
  'cr','cl','fr','fl','gr','gl',
]);

const STRONG_VOWELS = new Set(['a','e','o','á','é','ó']);

function isVowel(ch) {
  return 'aeiouáéíóúü'.includes(ch);
}

function isDiphthong(v1, v2) {
  const combined = v1 + v2;
  if (DIPHTHONGS.has(combined)) return true;
  const v1Strong = STRONG_VOWELS.has(v1);
  const v2Strong = STRONG_VOWELS.has(v2);
  // vocal débil sin tilde + vocal fuerte (o viceversa) → diptongo
  // vocal débil + vocal débil → diptongo (iu, ui)
  if (v1Strong !== v2Strong) return true;
  if ((v1 === 'i' && v2 === 'u') || (v1 === 'u' && v2 === 'i')) return true;
  return false;
}

function restoreDigraphs(text) {
  return text
    .replace(/ç/g, 'ch')
    .replace(/ł/g, 'll')
    .replace(/ř/g, 'rr')
    .replace(/q([^u]|$)/g, 'qu$1'); // restaura 'qu' solo donde aplica
}

/**
 * Silabifica una sola palabra en español.
 * @param {string} word - Palabra en minúsculas o con tildes
 * @returns {string[]} - Array de sílabas, ej: syllabifyWord("gracias") → ["gra","cias"]
 */
function syllabifyWord(word) {
  if (!word) return [];

  // Codificar dígrafos como caracteres únicos para simplificar el parsing
  let normalized = word.toLowerCase()
    .replace(/ch/g, 'ç')
    .replace(/ll/g, 'ł')
    .replace(/rr/g, 'ř')
    .replace(/qu/g, 'q');

  const syllables = []; // { onset, nucleus, coda }
  let i = 0;

  while (i < normalized.length) {
    let onset = '';
    let nucleus = '';
    let coda = '';

    // --- Recoger consonantes iniciales (onset) ---
    while (i < normalized.length && !isVowel(normalized[i])) {
      onset += normalized[i];
      i++;
    }

    // Si el onset tiene 2+ consonantes, verificar si el final es cluster válido
    if (onset.length >= 2) {
      const lastTwo = onset.slice(-2);
      if (!ONSET_CLUSTERS.has(lastTwo)) {
        // No es cluster: la primera consonante del grupo va a la coda anterior
        if (syllables.length > 0) {
          const prev = syllables.pop();
          syllables.push({ onset: prev.onset, nucleus: prev.nucleus, coda: prev.coda + onset[0] });
          onset = onset.slice(1);
        }
      }
    }

    // --- Recoger núcleo vocálico (con posible diptongo) ---
    if (i < normalized.length && isVowel(normalized[i])) {
      nucleus += normalized[i];
      i++;
      if (i < normalized.length && isVowel(normalized[i])) {
        if (isDiphthong(nucleus, normalized[i])) {
          nucleus += normalized[i];
          i++;
        }
      }
    }

    // --- Recoger consonantes de cierre (coda) ---
    if (i < normalized.length && !isVowel(normalized[i])) {
      const consonantStart = i;
      let consonantCount = 0;
      while (i < normalized.length && !isVowel(normalized[i])) {
        consonantCount++;
        i++;
      }

      if (i >= normalized.length) {
        // Final de palabra: todas las consonantes van a la coda
        coda = normalized.slice(consonantStart, i);
      } else {
        if (consonantCount === 1) {
          // Una sola consonante entre vocales → va al onset de la siguiente
          i = consonantStart;
        } else if (consonantCount >= 2) {
          const lastTwo = normalized.slice(i - 2, i);
          if (ONSET_CLUSTERS.has(lastTwo)) {
            // Las 2 últimas forman cluster → van juntas al siguiente onset
            if (consonantCount > 2) {
              coda = normalized.slice(consonantStart, i - 2);
              i = consonantStart + coda.length;
            } else {
              i = consonantStart; // todas al siguiente onset
            }
          } else {
            // No es cluster: una va a esta coda, el resto al siguiente onset
            coda = normalized.slice(consonantStart, i - 1);
            i = consonantStart + coda.length;
          }
        }
      }
    }

    // Restaurar dígrafos y guardar sílaba
    onset   = restoreDigraphs(onset);
    nucleus = restoreDigraphs(nucleus);
    coda    = restoreDigraphs(coda);

    if (nucleus) {
      syllables.push({ onset, nucleus, coda });
    }
  }

  return syllables.map(s => s.onset + s.nucleus + s.coda);
}

/**
 * Silabifica una frase completa en español.
 * Cada palabra se silabifica de forma independiente.
 *
 * @param {string} phrase - Frase o palabra, ej: "hora de comer"
 * @returns {string[]} - Array de sílabas, ej: ["ho","ra","de","co","mer"]
 *
 * @example
 * syllabify("mamá")          // → ["ma","má"]
 * syllabify("gracias")       // → ["gra","cias"]
 * syllabify("no sé")         // → ["no","sé"]
 * syllabify("hora de comer") // → ["ho","ra","de","co","mer"]
 * syllabify("buenos días")   // → ["bue","nos","dí","as"]
 * syllabify("agua")          // → ["a","gua"]
 * syllabify("hambre")        // → ["ham","bre"]
 */
export function syllabify(phrase) {
  if (!phrase || !phrase.trim()) return [];
  const words = phrase.trim().split(/\s+/);
  return words.flatMap(word => syllabifyWord(word));
}
```

### 4.2 Casos de prueba para validar la implementación

Antes de integrar en el formulario de creación, verificar que estos casos pasen:

```javascript
import { syllabify } from './syllabifier';

// Estímulos existentes del catálogo
console.assert(JSON.stringify(syllabify("mamá"))    === '["ma","má"]');
console.assert(JSON.stringify(syllabify("papá"))    === '["pa","pá"]');
console.assert(JSON.stringify(syllabify("agua"))    === '["a","gua"]');
console.assert(JSON.stringify(syllabify("no sé"))   === '["no","sé"]');
console.assert(JSON.stringify(syllabify("ayuda"))   === '["a","yu","da"]');
console.assert(JSON.stringify(syllabify("gracias")) === '["gra","cias"]');
console.assert(JSON.stringify(syllabify("casa"))    === '["ca","sa"]');
console.assert(JSON.stringify(syllabify("hambre"))  === '["ham","bre"]');
console.assert(JSON.stringify(syllabify("dolor"))   === '["do","lor"]');
console.assert(JSON.stringify(syllabify("bien"))    === '["bien"]');

// Frases nuevas
console.assert(JSON.stringify(syllabify("hora de comer"))  === '["ho","ra","de","co","mer"]');
console.assert(JSON.stringify(syllabify("buenos días"))    === '["bue","nos","dí","as"]');
console.assert(JSON.stringify(syllabify("quiero agua"))    === '["quie","ro","a","gua"]');
console.assert(JSON.stringify(syllabify("por favor"))      === '["por","fa","vor"]');
console.assert(JSON.stringify(syllabify("tengo frío"))     === '["ten","go","frí","o"]');

console.log("✅ Todos los casos de prueba pasaron");
```

### 4.3 Integración en el formulario de creación de estímulos

```jsx
// En el componente React de creación de estímulo TEM
import { syllabify } from '../utils/syllabifier';

function CrearEstimuloTEM() {
  const [texto, setTexto] = useState('');
  const [syllables, setSyllables] = useState([]);

  // Auto-silabificar al cambiar el texto
  function handleTextoChange(e) {
    const valor = e.target.value;
    setTexto(valor);
    if (valor.trim()) {
      setSyllables(syllabify(valor));
    } else {
      setSyllables([]);
    }
  }

  // Permitir edición manual de una sílaba específica
  function handleSyllableEdit(index, newValue) {
    const updated = [...syllables];
    updated[index] = newValue;
    setSyllables(updated);
  }

  // Permitir dividir una sílaba en dos
  function handleSplitSyllable(index) {
    const syl = syllables[index];
    if (syl.length < 2) return;
    const mid = Math.ceil(syl.length / 2);
    const updated = [...syllables];
    updated.splice(index, 1, syl.slice(0, mid), syl.slice(mid));
    setSyllables(updated);
  }

  // Permitir unir dos sílabas consecutivas
  function handleMergeSyllables(index) {
    if (index >= syllables.length - 1) return;
    const updated = [...syllables];
    updated.splice(index, 2, syllables[index] + syllables[index + 1]);
    setSyllables(updated);
  }

  return (
    <form>
      <label>Texto de la frase</label>
      <input
        value={texto}
        onChange={handleTextoChange}
        placeholder="ej: hora de comer"
      />

      {syllables.length > 0 && (
        <div>
          <label>
            Sílabas ({syllables.length}) — Revisa y ajusta si es necesario:
          </label>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {syllables.map((syl, i) => (
              <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                <input
                  value={syl}
                  onChange={e => handleSyllableEdit(i, e.target.value)}
                  style={{ width: `${Math.max(syl.length + 1, 3)}ch`, textAlign: 'center' }}
                />
                <div style={{ display: 'flex', gap: 4, fontSize: 10 }}>
                  <button type="button" onClick={() => handleSplitSyllable(i)} title="Dividir">÷</button>
                  {i < syllables.length - 1 && (
                    <button type="button" onClick={() => handleMergeSyllables(i)} title="Unir con siguiente">+</button>
                  )}
                </div>
              </div>
            ))}
          </div>
          <small>El patrón tonal debe tener {syllables.length} caracteres (L o H)</small>
        </div>
      )}

      {/* ... resto del formulario ... */}
    </form>
  );
}
```

---

## 5. Estrategia recomendada para el portal web

### Opción A — Silabificador automático + revisión manual (recomendada)

1. El terapeuta escribe la frase: `"hora de comer"`
2. El portal la silabifica automáticamente usando `syllabify()` (ver sección 4): `["ho", "ra", "de", "co", "mer"]`
3. La sugerencia se muestra como chips editables (cada sílaba es un input)
4. El terapeuta puede editar, unir o dividir chips antes de confirmar
5. Al guardar, se almacena la versión final aprobada por el terapeuta en Firestore

**Implementación:** Usar el módulo `syllabifier.js` de la sección 4 — no requiere librerías externas, está basado directamente en el algoritmo Flutter del proyecto y fue validado contra todos los estímulos del catálogo.

### Opción B — Solo manual (aceptable como MVP)

Mostrar un campo de texto donde el terapeuta escribe las sílabas separadas por guion:
```
Frase:   hora de comer
Sílabas: ho-ra-de-co-mer   →  ["ho", "ra", "de", "co", "mer"]
```

Simple y no requiere NLP. El terapeuta con formación clínica sabe silabificar correctamente.

---

## 5. Campos que genera el terapeuta al crear un estímulo

Cuando el terapeuta cree un estímulo en el portal web, el documento que se sube a `stimuli_TEM/{id}` debe incluir:

| Campo | Tipo | Quién lo define | Ejemplo |
|-------|------|-----------------|---------|
| `texto` | string | Terapeuta | `"hora de comer"` |
| `syllables` | string[] | Terapeuta (asistido por silabificador) | `["ho","ra","de","co","mer"]` |
| `num_silabas` | int | Calculado: `syllables.length` | `5` |
| `patron_tonal` | string | Terapeuta | `"LHLHL"` (L=bajo, H=alto) |
| `categoria` | string | Terapeuta | `"rutina_diaria"` |
| `pregunta_texto` | string | Terapeuta | `"¿Eso que dijiste fue 'hora de comer'?"` |
| `nivel_clinico` | int | Terapeuta | `1`, `2` ó `3` |
| `audio_url` | string | Terapeuta (sube WAV) | URL de Firebase Storage |
| `onsets_ms` | int[] | Auto-generado desde WAV | `[80, 280, 480, 630, 830]` |
| `durations_ms` | int[] | Auto-generado desde WAV | `[200, 200, 150, 200, 220]` |
| `audio_duration_ms` | int | Auto-leído del WAV | `1050` |
| `f0_template_hz` | float[] | Calculado por backend Python | `[130, 175, 145, 160, 135]` |
| `imagen_url` | string | Opcional, terapeuta | URL de imagen |

**Los campos `onsets_ms`, `durations_ms` y `f0_template_hz` se deben poblar automáticamente después de que el terapeuta sube el audio WAV**, usando la misma lógica del script `generateTimingFromWav()` (distribución proporcional como aproximación inicial) o el endpoint del backend Python con Whisper.

---

## 6. Lógica de timings a portar al portal web

Esta es la función JavaScript equivalente a `generateTimingFromWav()` del seed script. Se puede usar directamente en el portal web una vez que el terapeuta sube el WAV:

```javascript
/**
 * Genera onsets_ms y durations_ms distribuyendo las sílabas
 * proporcionalmente a lo largo de la duración del audio.
 *
 * @param {string[]} syllables - Array de sílabas, ej: ["ho","ra","de","co","mer"]
 * @param {number} audioDurationMs - Duración del audio en milisegundos
 * @returns {{ onsets_ms: number[], durations_ms: number[], audio_duration_ms: number }}
 */
function generateTimings(syllables, audioDurationMs) {
  const n = syllables.length;
  if (n === 0) return { onsets_ms: [], durations_ms: [], audio_duration_ms: audioDurationMs };

  const silenceStart = Math.min(80,  Math.round(audioDurationMs * 0.08));
  const silenceEnd   = Math.min(50,  Math.round(audioDurationMs * 0.05));
  const available    = audioDurationMs - silenceStart - silenceEnd;

  if (available <= 0) {
    const spacing = Math.max(100, Math.round(audioDurationMs / n));
    return {
      onsets_ms:         syllables.map((_, i) => i * spacing),
      durations_ms:      syllables.map(() => spacing - 20),
      audio_duration_ms: audioDurationMs,
    };
  }

  const spacing = Math.round(available / n);
  const onsets_ms = syllables.map((_, i) => silenceStart + i * spacing);
  const durations_ms = syllables.map((_, i) =>
    i === n - 1
      ? audioDurationMs - onsets_ms[i]       // última sílaba: llega al final
      : Math.max(50, spacing - 20)           // las demás: pequeño gap natural
  );

  return { onsets_ms, durations_ms, audio_duration_ms: audioDurationMs };
}
```

Para leer la duración de un WAV en el navegador:

```javascript
/**
 * Lee la duración de un archivo WAV desde el navegador usando AudioContext.
 * @param {File} wavFile - El archivo WAV subido por el terapeuta
 * @returns {Promise<number>} Duración en milisegundos
 */
async function getWavDurationMs(wavFile) {
  const audioCtx = new AudioContext();
  const arrayBuffer = await wavFile.arrayBuffer();
  const audioBuffer = await audioCtx.decodeAudioData(arrayBuffer);
  await audioCtx.close();
  return Math.round(audioBuffer.duration * 1000);
}
```

---

## 7. Consideraciones clínicas importantes

1. **Las sílabas deben reflejar cómo el paciente articulará**, no necesariamente la silabificación ortográfica estricta. El terapeuta puede decidir romper un diptongo en dos sílabas si considera que es mejor para la práctica.

2. **El patrón tonal (`patron_tonal`) debe corresponder al número de sílabas.** Si hay 5 sílabas, el patrón debe tener 5 caracteres: `"LHLHL"`. Validar esto en el formulario web.

3. **Los timings son aproximaciones iniciales.** El backend Python (Whisper) puede refinarlos después, pero la app móvil funciona con la aproximación proporcional.

4. **El campo `f0_template_hz` lo genera el backend Python analizando el audio de referencia.** No lo genera el terapeuta. El portal puede dejarlo vacío al crear y esperar a que el Cloud Function lo complete.

5. **Una vez que hay intentos grabados para un estímulo, cambiar sus sílabas rompería los análisis previos.** Los estímulos deben considerarse inmutables después de ser usados en sesiones.
