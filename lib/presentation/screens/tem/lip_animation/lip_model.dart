library;

import 'dart:ui';

// CHANGES: Completely rewritten to unify geometric representation (4 arrays × 7 points = 28 total)
// CHANGES: All constants normalized and centralized (from requirements spec)

/// Modelo geométrico paramétrico de los labios
///
/// Genera 28 puntos de control (4 contornos × 7 puntos cada uno) para representar
/// labios en 2D basándose en tres parámetros normalizados: openness, width, roundness

// ==================== CONSTANTES GEOMÉTRICAS DEFINITIVAS ====================
// Estas constantes fueron calibradas para Terapia de Entonación Melódica (TEM)
// en tratamiento de Afasia de Broca. NO modificar sin validación clínica.

const double _BASE_HALF_WIDTH = 0.18; // Offset base de ancho del labio
const double _HALF_WIDTH_SCALE = 0.22; // Escala del parámetro width
const double _ROUND_SCALE =
    0.08; // Escala del parámetro roundness (proyección O/U)
const double _OPENNESS_SCALE =
    0.15; // Escala vertical: openness → separación labial
const double _LIP_THICKNESS_BASE =
    0.095; // Grosor suficiente para volumen natural
const double _LIP_THICKNESS_OPENNESS_FACTOR = 0.18; // Se reduce menos al abrir

// Centro de referencia en coordenadas normalizadas
const double _CENTER_X = 0.5;
const double _CENTER_Y = 0.5;

/// Punto en coordenadas normalizadas [0.0 - 1.0]
class NormalizedPoint {
  final double x;
  final double y;

  const NormalizedPoint(this.x, this.y);

  /// Convierte a coordenadas absolutas
  Offset toOffset(double canvasWidth, double canvasHeight) {
    return Offset(x * canvasWidth, y * canvasHeight);
  }

  @override
  String toString() => 'NormalizedPoint($x, $y)';
}

/// Genera los 4 contornos del labio (28 puntos totales) en coordenadas absolutas
///
/// Retorna una lista de 4 listas de Offsets:
/// [0] = outerUpper (7 puntos): Borde exterior del labio superior
/// [1] = innerUpper (7 puntos): Borde interior del labio superior (hacia boca)
/// [2] = innerLower (7 puntos): Borde interior del labio inferior (hacia boca)
/// [3] = outerLower (7 puntos): Borde exterior del labio inferior
///
/// [openness] Apertura vertical [0.0 = cerrado, 1.0 = muy abierto]
/// [width] Anchura horizontal [0.0 = estrecho, 1.0 = ancho]
/// [roundness] Redondez tipo O/U [0.0 = plano, 1.0 = circular proyectado]
/// [size] Tamaño del canvas para convertir a coordenadas absolutas
List<List<Offset>> generateLipContours(
  double openness,
  double width,
  double roundness,
  Size size,
) {
  // Validar parámetros normalizados
  assert(openness >= 0.0 && openness <= 1.0, 'openness must be [0.0-1.0]');
  assert(width >= 0.0 && width <= 1.0, 'width must be [0.0-1.0]');
  assert(roundness >= 0.0 && roundness <= 1.0, 'roundness must be [0.0-1.0]');

  // Calcular dimensiones geométricas base
  final halfWidth = _BASE_HALF_WIDTH + (width * _HALF_WIDTH_SCALE);
  final roundEffect = roundness * _ROUND_SCALE;
  final upperLipOffset = openness * _OPENNESS_SCALE;
  final lowerLipOffset = openness * _OPENNESS_SCALE;
  final lipThickness =
      _LIP_THICKNESS_BASE * (1.0 - openness * _LIP_THICKNESS_OPENNESS_FACTOR);

  // Generar contornos en coordenadas normalizadas
  final outerUpper = _generateContourFromParameters(
    openness,
    width,
    roundness,
    halfWidth,
    roundEffect,
    upperLipOffset,
    lipThickness,
    isUpper: true,
    isInner: false,
  );

  final innerUpper = _generateContourFromParameters(
    openness,
    width,
    roundness,
    halfWidth,
    roundEffect,
    upperLipOffset,
    lipThickness,
    isUpper: true,
    isInner: true,
  );

  final innerLower = _generateContourFromParameters(
    openness,
    width,
    roundness,
    halfWidth,
    roundEffect,
    lowerLipOffset,
    lipThickness,
    isUpper: false,
    isInner: true,
  );

  final outerLower = _generateContourFromParameters(
    openness,
    width,
    roundness,
    halfWidth,
    roundEffect,
    lowerLipOffset,
    lipThickness,
    isUpper: false,
    isInner: false,
  );

  // Convertir a coordenadas absolutas y validar que estén dentro del rectángulo
  return [
    outerUpper
        .map((p) => _clampOffset(p.toOffset(size.width, size.height), size))
        .toList(),
    innerUpper
        .map((p) => _clampOffset(p.toOffset(size.width, size.height), size))
        .toList(),
    innerLower
        .map((p) => _clampOffset(p.toOffset(size.width, size.height), size))
        .toList(),
    outerLower
        .map((p) => _clampOffset(p.toOffset(size.width, size.height), size))
        .toList(),
  ];
}

/// Genera un solo contorno de 7 puntos (normalizado)
///
/// Los 7 puntos corresponden a:
/// [0] = Comisura izquierda (extremo izquierdo)
/// [1] = Punto intermedio izquierdo superior
/// [2] = Punto medio-izquierdo
/// [3] = Centro (vértice del arco de Cupido en labio superior, o punto más bajo en inferior)
/// [4] = Punto medio-derecho
/// [5] = Punto intermedio derecho superior
/// [6] = Comisura derecha (extremo derecho)
List<NormalizedPoint> _generateContourFromParameters(
  double openness,
  double width,
  double roundness,
  double halfWidth,
  double roundEffect,
  double lipOffset,
  double lipThickness, {
  required bool isUpper,
  required bool isInner,
}) {
  final points = <NormalizedPoint>[];

  // Factor de contracción para borde interior (crea forma O/U)
  final innerContractionFactor = isInner ? (0.95 - roundness * 0.15) : 1.0;
  final innerRoundBoost =
      isInner ? 1.5 : 1.0; // Interior se contrae más con roundness

  // Signo vertical (superior sube, inferior baja)
  final verticalSign = isUpper ? -1 : 1;

  // Offset de grosor (exterior más alejado del centro que interior)
  final thicknessOffset = isInner ? 0 : lipThickness;

  // PUNTO 0: Comisura izquierda
  points.add(NormalizedPoint(
    _CENTER_X - halfWidth * innerContractionFactor,
    _CENTER_Y + verticalSign * (thicknessOffset + lipOffset * 0.3),
  ));

  // ANATOMÍA DIFERENCIADA: Labio inferior vs superior
  // El labio superior permite variación (arco de Cupido aplicado después)
  // El labio inferior DEBE ser un arco convexo suave SIN picos laterales

  if (isUpper) {
    // ═══════════════════════════════════════════════════════════════════════
    // LABIO SUPERIOR: Forma con variación vertical
    // ═══════════════════════════════════════════════════════════════════════

    // PUNTO 1: Intermedio izquierdo (65% del ancho)
    // Reducido de * 1.5 a * 1.1 para suavizar los picos laterales OU1/OU5
    points.add(NormalizedPoint(
      _CENTER_X -
          halfWidth * 0.65 * innerContractionFactor +
          roundEffect * innerRoundBoost * 0.5,
      _CENTER_Y + verticalSign * (lipOffset * 0.6 + thicknessOffset * 1.1),
    ));

    // PUNTO 2: Medio-izquierdo (30% del ancho)
    points.add(NormalizedPoint(
      _CENTER_X -
          halfWidth * 0.30 * innerContractionFactor +
          roundEffect * innerRoundBoost * 0.3,
      _CENTER_Y + verticalSign * (lipOffset * 0.85 + thicknessOffset),
    ));

    // PUNTO 3: Centro (base para arco de Cupido)
    points.add(NormalizedPoint(
      _CENTER_X,
      _CENTER_Y + verticalSign * (lipOffset * 1.0 + thicknessOffset),
    ));

    // PUNTO 4: Medio-derecho (espejo del 2)
    points.add(NormalizedPoint(
      _CENTER_X +
          halfWidth * 0.30 * innerContractionFactor -
          roundEffect * innerRoundBoost * 0.3,
      _CENTER_Y + verticalSign * (lipOffset * 0.85 + thicknessOffset),
    ));

    // PUNTO 5: Intermedio derecho (espejo del 1)
    // Reducido de * 1.5 a * 1.1 para suavizar los picos laterales OU1/OU5
    points.add(NormalizedPoint(
      _CENTER_X +
          halfWidth * 0.65 * innerContractionFactor -
          roundEffect * innerRoundBoost * 0.5,
      _CENTER_Y + verticalSign * (lipOffset * 0.6 + thicknessOffset * 1.1),
    ));
  } else {
    // ═══════════════════════════════════════════════════════════════════════
    // LABIO INFERIOR: Arco parabólico SUAVE y continuo
    // ═══════════════════════════════════════════════════════════════════════
    // BUG ANTERIOR: thicknessOffset * 1.5 en puntos 1 y 5 los empujaba MÁS
    // ABAJO que los puntos 2,3,4 → creaba alas / picos en forma de diamante.
    //
    // CORRECCIÓN: Puntos 1 y 5 usan thicknessOffset sin multiplicador,
    // igual que puntos 2,3,4. Solo el lipOffset varía: 0.50 → 0.65 → 0.75
    // Esto garantiza que la Y siga siempre una progresión ascendente suave.

    // PUNTO 1: Intermedio izquierdo (thicknessOffset SIN factor 1.5)
    points.add(NormalizedPoint(
      _CENTER_X -
          halfWidth * 0.65 * innerContractionFactor +
          roundEffect * innerRoundBoost * 0.5,
      _CENTER_Y + verticalSign * (lipOffset * 0.50 + thicknessOffset),
    ));

    // PUNTO 2: Medio-izquierdo
    // thicknessOffset * 1.15 para crear curvatura descendente en labio inferior
    points.add(NormalizedPoint(
      _CENTER_X -
          halfWidth * 0.30 * innerContractionFactor +
          roundEffect * innerRoundBoost * 0.3,
      _CENTER_Y + verticalSign * (lipOffset * 0.68 + thicknessOffset * 1.15),
    ));

    // PUNTO 3: Centro (punto más bajo del arco)
    // thicknessOffset * 1.30 para que sea el punto más bajo → forma convexa clara
    points.add(NormalizedPoint(
      _CENTER_X,
      _CENTER_Y + verticalSign * (lipOffset * 0.80 + thicknessOffset * 1.30),
    ));

    // PUNTO 4: Medio-derecho (espejo del 2)
    // thicknessOffset * 1.15 para crear curvatura descendente en labio inferior
    points.add(NormalizedPoint(
      _CENTER_X +
          halfWidth * 0.30 * innerContractionFactor -
          roundEffect * innerRoundBoost * 0.3,
      _CENTER_Y + verticalSign * (lipOffset * 0.68 + thicknessOffset * 1.15),
    ));

    // PUNTO 5: Intermedio derecho (espejo del 1)
    points.add(NormalizedPoint(
      _CENTER_X +
          halfWidth * 0.65 * innerContractionFactor -
          roundEffect * innerRoundBoost * 0.5,
      _CENTER_Y + verticalSign * (lipOffset * 0.50 + thicknessOffset),
    ));
  }

  // PUNTO 6: Comisura derecha
  points.add(NormalizedPoint(
    _CENTER_X + halfWidth * innerContractionFactor,
    _CENTER_Y + verticalSign * (thicknessOffset + lipOffset * 0.3),
  ));

  return points;
}

/// Aplica el arco de Cupido al contorno exterior superior
/// Modifica puntos [2, 3, 4] para crear la forma característica del labio superior
///
/// El bowDepth se reduce con la apertura (boca abierta → arco menos pronunciado)
///
/// CHANGES: Nuevo método para mejora visual v2.2 (gráficos mejorados)
/// Aplica el arco de Cupido EXCLUSIVAMENTE al labio superior exterior.
/// El arco de Cupido es sutil: una pequeña "M" en la mitad superior.
/// El labio inferior NUNCA debe recibir esta transformación.
List<Offset> applyCupidsBow(
  List<Offset> outerUpper,
  double openness,
  Size size,
) {
  if (outerUpper.length != 7) return outerUpper;

  // El arco desaparece cuando la boca está muy abierta (openness > 0.6)
  final intensity = (1.0 - (openness / 0.6)).clamp(0.0, 1.0);

  // Desplazamiento en píxeles: máximo 4px hacia arriba para los picos,
  // máximo 3px hacia abajo para la hendidura central.
  // Pequeño y sutil — un arco de Cupido humano es discreto.
  final peakUp = size.height *
      0.028 *
      intensity; // picos [2] y [4] suben (aumentado para arco más definido)
  final dipDown = size.height * 0.013 * intensity; // centro [3] baja

  final m = List<Offset>.from(outerUpper);
  m[2] = Offset(m[2].dx, m[2].dy - peakUp);
  m[3] = Offset(m[3].dx, m[3].dy + dipDown);
  m[4] = Offset(m[4].dx, m[4].dy - peakUp);

  return m;
}

/// Clamp offset para garantizar que esté dentro del rectángulo del canvas
Offset _clampOffset(Offset offset, Size size) {
  return Offset(
    offset.dx.clamp(0.0, size.width),
    offset.dy.clamp(0.0, size.height),
  );
}

// ==================== CONSTANTES GEOMÉTRICAS DE LENGUA ====================
// CHANGES: Añadidas para integración de lengua 2D paramétrica (v2.0)

/// Protrusión máxima de la lengua hacia adelante (normalizada)
const double _TONGUE_MAX_PROTRUSION = 0.12;

/// Altura máxima del punto frontal de la lengua (normalizada)
const double _TONGUE_MAX_HEIGHT = 0.35;

/// Altura por defecto del punto frontal de la lengua (normalizada)
const double _TONGUE_DEFAULT_HEIGHT = 0.18;

/// Genera el path de la lengua para renderizado 2D
///
/// CHANGES: Nueva función para integración de lengua paramétrica
///
/// La lengua se modela como una forma redondeada que emerge desde la parte
/// inferior-posterior de la boca, con control sobre:
/// - [tongueHeightFront]: Altura del punto frontal [0.0-1.0]
/// - [tongueWidth]: Ancho de la lengua [0.0-1.0]
/// - [protrusion]: Protrusión hacia adelante [-1.0 a 1.0], default 0
/// - [size]: Tamaño del canvas
///
/// Geometría:
/// - Base: Región posterior inferior de la boca (~40% width centrado)
/// - Frente: Punto elevable según tongueHeightFront
/// - Ancho: Escalable según tongueWidth (max ~70% del ancho bucal)
/// - Protrusión: Desplazamiento horizontal del punto frontal
///
/// Retorna Path suavizado con quadratic/cubic beziers, coordenadas absolutas
/// garantizadas dentro de Rect.fromLTWH(0, 0, size.width, size.height)
Path generateTonguePath({
  required double tongueHeightFront,
  required double tongueWidth,
  required double protrusion,
  required Size size,
}) {
  assert(tongueHeightFront >= 0.0 && tongueHeightFront <= 1.0);
  assert(tongueWidth >= 0.0 && tongueWidth <= 1.0);
  assert(protrusion >= -1.0 && protrusion <= 1.0);

  final path = Path();

  // Coordenadas normalizadas de la base posterior (ancho fijo ~40%)
  const baseWidth = 0.20; // Mitad del ancho base (40% total)
  const baseY = _CENTER_Y + 0.25; // Parte inferior de la boca

  // Coordenadas de la punta frontal
  final frontY = _CENTER_Y +
      _TONGUE_DEFAULT_HEIGHT -
      (tongueHeightFront * _TONGUE_MAX_HEIGHT);

  // CHANGES: Limitar protrusión para evitar que sobrepase plano dental
  // Clamp a [-0.06, +0.06] en lugar de [-0.12, +0.12] del max
  final protrusionOffset =
      (protrusion * _TONGUE_MAX_PROTRUSION).clamp(-0.06, 0.06);

  // Ancho efectivo de la lengua (max ~70% del ancho bucal)
  final effectiveWidth = tongueWidth * 0.35; // Mitad del ancho (70% total)

  // Convertir a coordenadas absolutas
  final cx = _CENTER_X * size.width;
  final cy = size.height;

  // Base izquierda
  final baseLeft =
      Offset(cx - baseWidth * size.width, baseY * size.height).clamp(size);

  // Base derecha
  final baseRight =
      Offset(cx + baseWidth * size.width, baseY * size.height).clamp(size);

  // CHANGES: Punta frontal con margen dental para evitar sobrepasar dientes
  // Limitar X para que no exceda ~85% del ancho (margen de seguridad)
  final dentalMarginMax = size.width * 0.85;
  final frontTip = Offset(
    (cx + protrusionOffset * size.width).clamp(0.0, dentalMarginMax),
    (frontY * size.height).clamp(0.0, size.height),
  );

  // Puntos laterales frontales (ancho variable)
  final frontLeft = Offset(
    (cx - effectiveWidth * size.width).clamp(0.0, size.width),
    (frontY * size.height + size.height * 0.05).clamp(0.0, size.height),
  );

  final frontRight = Offset(
    (cx + effectiveWidth * size.width).clamp(0.0, size.width),
    (frontY * size.height + size.height * 0.05).clamp(0.0, size.height),
  );

  // Construir path con curvas suaves
  path.moveTo(baseLeft.dx, baseLeft.dy);

  // Lado izquierdo (base → frente)
  path.quadraticBezierTo(
    baseLeft.dx - size.width * 0.02, // Control point x
    (baseLeft.dy + frontLeft.dy) / 2, // Control point y (punto medio)
    frontLeft.dx,
    frontLeft.dy,
  );

  // Frente izquierdo → punta
  path.quadraticBezierTo(
    (frontLeft.dx + frontTip.dx) / 2,
    frontTip.dy - size.height * 0.02,
    frontTip.dx,
    frontTip.dy,
  );

  // Punta → frente derecho
  path.quadraticBezierTo(
    (frontTip.dx + frontRight.dx) / 2,
    frontTip.dy - size.height * 0.02,
    frontRight.dx,
    frontRight.dy,
  );

  // Lado derecho (frente → base)
  path.quadraticBezierTo(
    baseRight.dx + size.width * 0.02,
    (frontRight.dy + baseRight.dy) / 2,
    baseRight.dx,
    baseRight.dy,
  );

  // Cerrar con línea recta en la base (oculta dentro de la boca)
  path.lineTo(baseLeft.dx, baseLeft.dy);
  path.close();

  return path;
}

/// Extension para clamping de Offset dentro de Size
extension _OffsetClamp on Offset {
  Offset clamp(Size size) {
    return Offset(
      dx.clamp(0.0, size.width),
      dy.clamp(0.0, size.height),
    );
  }
}

/// Ajusta los 4 contornos para que las comisuras izquierda y derecha
/// sean exactamente el mismo punto en outerUpper y outerLower.
/// Esto es obligatorio para que la boca se vea como una unidad.
/// NO modifica los contornos inner (apertura de la boca).
List<List<Offset>> unifyCommissures(List<List<Offset>> contours) {
  // contours = [outerUpper, innerUpper, innerLower, outerLower]
  if (contours.length != 4) return contours;

  final outerUpper = List<Offset>.from(contours[0]);
  final outerLower = List<Offset>.from(contours[3]);

  // Comisura izquierda: promedio Y entre outerUpper[0] y outerLower[0]
  final leftX = (outerUpper[0].dx + outerLower[0].dx) / 2.0;
  final leftY = (outerUpper[0].dy + outerLower[0].dy) / 2.0;
  outerUpper[0] = Offset(leftX, leftY);
  outerLower[0] = Offset(leftX, leftY);

  // Comisura derecha: promedio Y entre outerUpper[6] y outerLower[6]
  final rightX = (outerUpper[6].dx + outerLower[6].dx) / 2.0;
  final rightY = (outerUpper[6].dy + outerLower[6].dy) / 2.0;
  outerUpper[6] = Offset(rightX, rightY);
  outerLower[6] = Offset(rightX, rightY);

  return [outerUpper, contours[1], contours[2], outerLower];
}
