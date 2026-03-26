# Guía de grabación de estímulos — RehabilitIA TEM

> **Para:** Colaborador de tesis encargado de la grabación de audio
> **Propósito:** Producir los 30 archivos de audio que la aplicación RehabilitIA necesita para funcionar  
> **Entrega a:** Juan (desarrollador) para subir al sistema

---

## ¿Para qué son estos audios?

RehabilitIA es una aplicación de rehabilitación del lenguaje para personas con afasia. Usa una técnica clínica llamada **Entonación Melódica** (TEM), en la que el paciente repite frases cortas siguiendo un ritmo y una melodía exagerados.

La app reproduce cada frase en audio mientras anima unos labios en pantalla y envía vibración al ritmo de las sílabas. Para que todo esto funcione, **necesita grabaciones de alta calidad** de un hablante nativo de español con voz clara y dicción precisa.

Tu tarea es grabar esas 30 frases y entregarle los archivos de audio a Juan.

---

## Lo que necesitas antes de empezar

### Equipo
- Micrófono de escritorio o diadema USB (preferiblemente, no el micrófono integrado del portátil)
- Computador con acceso a internet
- Cuarto silencioso (cierra puertas y ventanas, apaga ventiladores o aires acondicionados)

### Software gratuito: Audacity

Descárgalo en **https://www.audacityteam.org/** e instálalo. Es el programa con el que vas a grabar y exportar los archivos.

---

## Configuración de Audacity (hazlo una sola vez)

Antes de grabar el primer estímulo, configura Audacity así:

1. Abre Audacity
2. Ve al menú **Editar → Preferencias → Dispositivos**
   - Dispositivo de grabación: elige el micrófono que vas a usar
   - Canales: **Mono (1 canal)**
3. Ve a **Editar → Preferencias → Calidad**
   - Frecuencia de muestreo predeterminada: **16000 Hz**
   - Formato de muestra: **16-bit**
4. Haz clic en **Aceptar**

> Estos valores son obligatorios. La app no funcionará correctamente con otra configuración.

---

## Cómo grabar cada estímulo

### Paso a paso

1. Haz clic en el botón rojo de **grabar** (⏺)
2. Espera 1 segundo en silencio
3. Di la frase en voz alta con la entonación indicada
4. Espera 1 segundo más en silencio
5. Haz clic en **detener** (⏹)
6. Escucha la grabación. Si hay ruido de fondo, errores de pronunciación o la voz se distorsionó (se ve todo rojo en la onda), **repítela**
7. Cuando estés satisfecho, **exporta** el archivo:
   - Menú → **Archivo → Exportar → Exportar como WAV**
   - Nombre del archivo: usa exactamente el ID de la tabla (por ejemplo: `ST_TEM_N1_001.wav`)
   - Formato: **WAV (Microsoft) 16-bit PCM**
   - Guárdalo en una carpeta llamada `estimulos_grabados/`

### Lo que debes evitar
- No grabes en un lugar con eco (baños, pasillos grandes)
- No respires directamente al micrófono entre sílabas
- No aceleres al final de la frase — el ritmo debe ser **constante**
- No hagas clics, golpes de mesa o ruidos de fondo durante la toma

---

## Pautas de entonación por nivel

La técnica TEM usa una melodía exagerada e intencional. No es una lectura normal — hay que canturlear las sílabas.

### Nivel 1 — Muy lento, muy exagerado (~60 BPM)

Di cada sílaba como si fuera una **nota musical separada**. Hay una pausa breve entre sílaba y sílaba. El contraste entre grave y agudo debe ser muy pronunciado.

- Patrón `LH` (bajo-alto): la primera sílaba grave, la segunda aguda. Ej: "ma-**MÁ**" (voz sube al final)
- Patrón `HL` (alto-bajo): la primera sílaba aguda, la segunda grave. Ej: "**A**-gua" (voz baja al final)
- Patrón `H` (solo alta): única sílaba en tono alto y sostenido. Ej: "**BIEN**"

### Nivel 2 — Lento, melódico (~70 BPM)

La frase suena como una **melodía corta**. Las notas siguen siendo perceptibles pero fluye más que el Nivel 1. No hay pausa entre sílabas, solo la subida y bajada de tono.

### Nivel 3 — Más natural, contorno visible (~80 BPM)

La entonación es más parecida al habla normal, pero el contorno melódico (la curva de grave a agudo o viceversa) aún debe ser claramente audible.

---

## Lista completa de estímulos a grabar

### Nivel 1 — 10 frases

| # | Nombre de archivo | Frase | Separación silábica | Patrón de tono |
|---|-------------------|-------|---------------------|----------------|
| 1 | `ST_TEM_N1_001.wav` | **mamá** | ma · má | bajo → **ALTO** |
| 2 | `ST_TEM_N1_002.wav` | **papá** | pa · pá | bajo → **ALTO** |
| 3 | `ST_TEM_N1_003.wav` | **agua** | a · gua | **ALTO** → bajo |
| 4 | `ST_TEM_N1_004.wav` | **no sé** | no · sé | bajo → **ALTO** |
| 5 | `ST_TEM_N1_005.wav` | **ayuda** | a · yu · da | bajo → **ALTO** → bajo |
| 6 | `ST_TEM_N1_006.wav` | **gracias** | gra · cias | **ALTO** → bajo |
| 7 | `ST_TEM_N1_007.wav` | **casa** | ca · sa | **ALTO** → bajo |
| 8 | `ST_TEM_N1_008.wav` | **hambre** | ham · bre | **ALTO** → bajo |
| 9 | `ST_TEM_N1_009.wav` | **dolor** | do · lor | bajo → **ALTO** |
| 10 | `ST_TEM_N1_010.wav` | **bien** | bien | **ALTO** sostenido |

### Nivel 2 — 10 frases

| # | Nombre de archivo | Frase | Separación silábica | Patrón de tono |
|---|-------------------|-------|---------------------|----------------|
| 11 | `ST_TEM_N2_001.wav` | **quiero agua** | quie · ro · a · gua | bajo → **ALTO** → bajo → bajo |
| 12 | `ST_TEM_N2_002.wav` | **buenos días** | bue · nos · dí · as | bajo → **ALTO** → **ALTO** → bajo |
| 13 | `ST_TEM_N2_003.wav` | **por favor** | por · fa · vór | bajo → bajo → **ALTO** |
| 14 | `ST_TEM_N2_004.wav` | **tengo sed** | ten · go · séd | bajo → bajo → **ALTO** |
| 15 | `ST_TEM_N2_005.wav` | **me duele** | me · due · le | **ALTO** → bajo → bajo |
| 16 | `ST_TEM_N2_006.wav` | **quiero ir** | quie · ro · ír | bajo → bajo → **ALTO** |
| 17 | `ST_TEM_N2_007.wav` | **buenas noches** | bue · nas · no · ches | bajo → **ALTO** → bajo → bajo |
| 18 | `ST_TEM_N2_008.wav` | **no quiero** | no · quie · ro | **ALTO** → **ALTO** → bajo |
| 19 | `ST_TEM_N2_009.wav` | **necesito** | ne · ce · si · to | bajo → bajo → **ALTO** → bajo |
| 20 | `ST_TEM_N2_010.wav` | **me llamo** | me · lla · mo | **ALTO** → bajo → bajo |

### Nivel 3 — 10 frases

| # | Nombre de archivo | Frase | Separación silábica |
|---|-------------------|-------|---------------------|
| 21 | `ST_TEM_N3_001.wav` | **quiero comer** | quie · ro · co · mer |
| 22 | `ST_TEM_N3_002.wav` | **necesito ayuda** | ne · ce · si · to · a · yu · da |
| 23 | `ST_TEM_N3_003.wav` | **buenos días señor** | bue · nos · dí · as · se · ñor |
| 24 | `ST_TEM_N3_004.wav` | **quiero ir al baño** | quie · ro · ir · al · ba · ño |
| 25 | `ST_TEM_N3_005.wav` | **me duele la cabeza** | me · due · le · la · ca · be · za |
| 26 | `ST_TEM_N3_006.wav` | **tengo mucho frío** | ten · go · mu · cho · frí · o |
| 27 | `ST_TEM_N3_007.wav` | **quiero llamar a mi mamá** | quie · ro · lla · mar · a · mi · ma · má |
| 28 | `ST_TEM_N3_008.wav` | **no me siento bien** | no · me · sien · to · bien |
| 29 | `ST_TEM_N3_009.wav` | **gracias por tu ayuda** | gra · cias · por · tu · a · yu · da |
| 30 | `ST_TEM_N3_010.wav` | **quiero hablar con el doctor** | quie · ro · ha · blar · con · el · doc · tor |

---

## Checklist de entrega

Cuando termines, verifica que tienes exactamente **30 archivos WAV** con estos nombres:

```
estimulos_grabados/
├── ST_TEM_N1_001.wav
├── ST_TEM_N1_002.wav
├── ST_TEM_N1_003.wav
├── ST_TEM_N1_004.wav
├── ST_TEM_N1_005.wav
├── ST_TEM_N1_006.wav
├── ST_TEM_N1_007.wav
├── ST_TEM_N1_008.wav
├── ST_TEM_N1_009.wav
├── ST_TEM_N1_010.wav
├── ST_TEM_N2_001.wav
├── ST_TEM_N2_002.wav
├── ST_TEM_N2_003.wav
├── ST_TEM_N2_004.wav
├── ST_TEM_N2_005.wav
├── ST_TEM_N2_006.wav
├── ST_TEM_N2_007.wav
├── ST_TEM_N2_008.wav
├── ST_TEM_N2_009.wav
├── ST_TEM_N2_010.wav
├── ST_TEM_N3_001.wav
├── ST_TEM_N3_002.wav
├── ST_TEM_N3_003.wav
├── ST_TEM_N3_004.wav
├── ST_TEM_N3_005.wav
├── ST_TEM_N3_006.wav
├── ST_TEM_N3_007.wav
├── ST_TEM_N3_008.wav
├── ST_TEM_N3_009.wav
└── ST_TEM_N3_010.wav
```

Comprime la carpeta (`estimulos_grabados.zip`) y envíasela a Juan por el canal acordado (Drive, WhatsApp, correo, etc.).

> **Nota:** Los nombres deben ser exactamente como se indica. Una letra diferente, un guion mal puesto o una extensión distinta (`.mp3`, `.m4a`) hará que el sistema no encuentre los archivos.

---

## Preguntas frecuentes

**¿Tengo que grabar los 30 de una vez?**
No. Puedes empezar solo con el Nivel 1 (10 frases) para que Juan pueda hacer una primera prueba con la app. Luego entregas los Niveles 2 y 3.

**¿Qué pasa si el arhivo se ve muy bajo (onda chica) en Audacity?**
Acércate más al micrófono o sube el volumen de entrada en las preferencias de Audacity. La onda debe ocupar entre el 50% y el 80% del espacio vertical, nunca llegar al tope.

**¿Puedo grabar varias frases en un mismo archivo y luego cortar?**
Sí, pero es más fácil manejarlas grabando una por una. Si lo haces en bloque, tendrás que exportar cada segmento por separado.

**¿Qué pasa si me equivoco a mitad de una grabación?**
Detén la grabación, borra la pista y graba de nuevo desde el principio. No edites el audio cortando o pegando partes — la app necesita que el ritmo sea continuo.

**¿Con qué micrófono es suficiente?**
Un micrófono de diadema USB básico (JLab, Logitech) es suficiente para el MVP. No necesita ser profesional, solo que no sea el integrado del portátil si hay ruido de fondo.

**Empieza por los 10 del Nivel 1.** Son suficientes para la primera prueba clínica.
