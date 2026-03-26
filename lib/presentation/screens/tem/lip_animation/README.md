# Módulo de Animación Labial 2D para TEM

## Descripción

Sistema de animación labial 2D minimalista para Terapia de Entonación Melódica (TEM), desarrollado completamente en Flutter nativo sin dependencias externas.

## Características

✅ **Animación paramétrica** - Basada en modelo geométrico matemático  
✅ **7 visemas** - Neutral, A, E, I, O, U, Cerrada  
✅ **Control temporal** - Duración por sílaba configurable  
✅ **Elongación vocálica** - Factor de elongación ajustable  
✅ **Flutter nativo** - Solo CustomPainter, sin assets ni SVG  
✅ **60 FPS** - Rendimiento optimizado  
✅ **Responsive** - Se adapta a diferentes tamaños de pantalla  

## Arquitectura

```
/lib/lip_animation
    ├── lip_viseme.dart          # Definición de visemas y mapeo fonema→visema
    ├── lip_model.dart           # Modelo geométrico paramétrico (8 puntos)
    ├── lip_painter.dart         # Renderizado con CustomPainter
    ├── lip_timeline.dart        # Eventos temporales
    ├── lip_animation_engine.dart # Motor temporal (silabificación)
    └── lip_animation_widget.dart # Widget principal
```

## Uso Básico

```dart
import 'package:tem_lip_animation_app/lip_animation/lip_animation_widget.dart';

// Uso simple
LipAnimationWidget(
  text: 'mama',
)

// Uso con parámetros personalizados
LipAnimationWidget(
  text: 'bebé',
  durationPerSyllable: Duration(milliseconds: 1000),
  vowelStretchFactor: 1.5,
  lipColor: Colors.red,
  loop: true,
)
```

## Parámetros

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `text` | `String` | (requerido) | Palabra o frase a animar |
| `durationPerSyllable` | `Duration` | `800ms` | Duración base por sílaba |
| `vowelStretchFactor` | `double` | `1.0` | Factor de elongación vocálica (≥1.0) |
| `lipColor` | `Color` | `Color(0xFFB71C1C)` | Color de los labios |
| `loop` | `bool` | `false` | Repetir animación en bucle |

## Integración en Pantalla TEM

```dart
Column(
  children: [
    Text(
      palabraActual,
      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    ),
    SizedBox(height: 40),
    SizedBox(
      width: 250,
      height: 150,
      child: LipAnimationWidget(
        text: palabraActual,
        durationPerSyllable: Duration(milliseconds: 800),
        vowelStretchFactor: 1.2,
        loop: true,
      ),
    ),
  ],
)
```

## Modelo Paramétrico

Cada visema se define mediante 3 parámetros normalizados `[0.0 - 1.0]`:

- **openness** - Apertura vertical
- **width** - Anchura horizontal  
- **roundness** - Redondez tipo O/U

### Visemas Definidos

| Visema | openness | width | roundness | Uso |
|--------|----------|-------|-----------|-----|
| Neutral | 0.2 | 0.5 | 0.0 | Reposo |
| A | 1.0 | 0.8 | 0.0 | Vocal /a/ |
| E | 0.6 | 0.9 | 0.0 | Vocal /e/ |
| I | 0.3 | 1.0 | 0.0 | Vocal /i/ |
| O | 0.6 | 0.5 | 0.8 | Vocal /o/ |
| U | 0.3 | 0.3 | 1.0 | Vocal /u/ |
| Cerrada | 0.0 | 0.5 | 0.0 | Consonantes m, b, p |

## Distribución Temporal (TEM)

Cada sílaba se divide en:

- **30%** - Consonante inicial
- **60%** - Vocal núcleo (afectada por elongación)
- **10%** - Consonante final

### Elongación Vocálica

El factor `vowelStretchFactor` **solo** afecta la duración de la vocal:

- `1.0` - Sin elongación (distribución estándar)
- `1.5` - Vocal 50% más larga
- `2.0` - Vocal doblemente larga

## Mapeo Fonema → Visema

```dart
a → Viseme.A
e → Viseme.E
i → Viseme.I
o → Viseme.O
u → Viseme.U
m, b, p → Viseme.Cerrada
otros → Viseme.Neutral
```

## Restricciones de Diseño

❌ **NO usar:**
- Assets PNG/JPG
- SVG externos
- Motores 3D (Unity, etc.)
- WebView
- Librerías de animación externas
- Física

✅ **SOLO usar:**
- Flutter SDK
- CustomPainter
- Path
- AnimationController
- Dart puro

## Criterios de Éxito

El módulo cumple con:

- ✅ Anima correctamente las vocales
- ✅ Transiciones suaves entre visemas
- ✅ Responde a duración configurada
- ✅ Permite elongación vocálica
- ✅ Se integra sin errores en Flutter
- ✅ Mantiene 60fps

## Ejemplo Completo

Ver [main.dart](../main.dart) para una demostración completa con:
- Múltiples palabras de ejemplo
- Controles de velocidad
- Controles de elongación vocálica
- Navegación entre palabras
- Bucle automático

## Notas Técnicas

### Silabificación Simple (V1)

La versión 1.0 usa un algoritmo simple de silabificación:
- Lee consonantes iniciales hasta encontrar vocal
- Lee vocal (núcleo obligatorio)
- Lee consonantes finales hasta la próxima vocal

### Interpolación

La interpolación siempre se hace **entre parámetros**, NO entre puntos geométricos. Esto garantiza transiciones naturales.

### Renderizado

El renderizado usa `quadraticBezierTo` para crear curvas suaves entre los 8 puntos de control estructurales.

## Licencia

Desarrollado para uso académico en el tratamiento de la afasia de Broca mediante Terapia de Entonación Melódica (TEM).

---

**Versión:** 1.0  
**Plataforma:** Flutter 3.5+  
**Autor:** Pontificia Universidad Javeriana
