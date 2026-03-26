library;

import 'dart:ui';

/// Modelo geométrico paramétrico de los labios
///
/// UBICACIÓN CANÓNICA: lib/data/models/tem/
/// Genera 28 puntos de control (4 contornos × 7 puntos) para renderizar
/// labios en 2D a partir de tres parámetros normalizados.
///
/// Solo depende de dart:ui (Offset, Size, Path) — sin dependencias de widgets.

// ==================== CONSTANTES GEOMÉTRICAS ====================

const double _BASE_HALF_WIDTH = 0.18;
const double _HALF_WIDTH_SCALE = 0.22;
const double _ROUND_SCALE = 0.08;
const double _OPENNESS_SCALE = 0.15;
const double _LIP_THICKNESS_BASE = 0.095;
const double _LIP_THICKNESS_OPENNESS_FACTOR = 0.18;
const double _CENTER_X = 0.5;
const double _CENTER_Y = 0.5;

/// Punto en coordenadas normalizadas [0.0 - 1.0]
class NormalizedPoint {
  final double x;
  final double y;

  const NormalizedPoint(this.x, this.y);

  Offset toOffset(double canvasWidth, double canvasHeight) {
    return Offset(x * canvasWidth, y * canvasHeight);
  }

  @override
  String toString() => 'NormalizedPoint($x, $y)';
}

/// Genera los 4 contornos del labio (28 puntos totales) en coordenadas absolutas.
///
/// Retorna [outerUpper, innerUpper, innerLower, outerLower] (7 puntos cada uno).
List<List<Offset>> generateLipContours(
  double openness,
  double width,
  double roundness,
  Size size,
) {
  assert(openness >= 0.0 && openness <= 1.0);
  assert(width >= 0.0 && width <= 1.0);
  assert(roundness >= 0.0 && roundness <= 1.0);

  final halfWidth = _BASE_HALF_WIDTH + (width * _HALF_WIDTH_SCALE);
  final roundEffect = roundness * _ROUND_SCALE;
  final upperLipOffset = openness * _OPENNESS_SCALE;
  final lowerLipOffset = openness * _OPENNESS_SCALE;
  final lipThickness =
      _LIP_THICKNESS_BASE * (1.0 - openness * _LIP_THICKNESS_OPENNESS_FACTOR);

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
  final innerContractionFactor = isInner ? (0.95 - roundness * 0.15) : 1.0;
  final innerRoundBoost = isInner ? 1.5 : 1.0;
  final verticalSign = isUpper ? -1 : 1;
  final thicknessOffset = isInner ? 0 : lipThickness;

  points.add(
    NormalizedPoint(
      _CENTER_X - halfWidth * innerContractionFactor,
      _CENTER_Y + verticalSign * (thicknessOffset + lipOffset * 0.3),
    ),
  );

  if (isUpper) {
    points.add(
      NormalizedPoint(
        _CENTER_X -
            halfWidth * 0.65 * innerContractionFactor +
            roundEffect * innerRoundBoost * 0.5,
        _CENTER_Y + verticalSign * (lipOffset * 0.6 + thicknessOffset * 1.1),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X -
            halfWidth * 0.30 * innerContractionFactor +
            roundEffect * innerRoundBoost * 0.3,
        _CENTER_Y + verticalSign * (lipOffset * 0.85 + thicknessOffset),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X,
        _CENTER_Y + verticalSign * (lipOffset * 1.0 + thicknessOffset),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X +
            halfWidth * 0.30 * innerContractionFactor -
            roundEffect * innerRoundBoost * 0.3,
        _CENTER_Y + verticalSign * (lipOffset * 0.85 + thicknessOffset),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X +
            halfWidth * 0.65 * innerContractionFactor -
            roundEffect * innerRoundBoost * 0.5,
        _CENTER_Y + verticalSign * (lipOffset * 0.6 + thicknessOffset * 1.1),
      ),
    );
  } else {
    points.add(
      NormalizedPoint(
        _CENTER_X -
            halfWidth * 0.65 * innerContractionFactor +
            roundEffect * innerRoundBoost * 0.5,
        _CENTER_Y + verticalSign * (lipOffset * 0.50 + thicknessOffset),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X -
            halfWidth * 0.30 * innerContractionFactor +
            roundEffect * innerRoundBoost * 0.3,
        _CENTER_Y + verticalSign * (lipOffset * 0.68 + thicknessOffset * 1.15),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X,
        _CENTER_Y + verticalSign * (lipOffset * 0.80 + thicknessOffset * 1.30),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X +
            halfWidth * 0.30 * innerContractionFactor -
            roundEffect * innerRoundBoost * 0.3,
        _CENTER_Y + verticalSign * (lipOffset * 0.68 + thicknessOffset * 1.15),
      ),
    );
    points.add(
      NormalizedPoint(
        _CENTER_X +
            halfWidth * 0.65 * innerContractionFactor -
            roundEffect * innerRoundBoost * 0.5,
        _CENTER_Y + verticalSign * (lipOffset * 0.50 + thicknessOffset),
      ),
    );
  }

  points.add(
    NormalizedPoint(
      _CENTER_X + halfWidth * innerContractionFactor,
      _CENTER_Y + verticalSign * (thicknessOffset + lipOffset * 0.3),
    ),
  );

  return points;
}

/// Aplica el arco de Cupido al contorno exterior superior
List<Offset> applyCupidsBow(
  List<Offset> outerUpper,
  double openness,
  Size size,
) {
  if (outerUpper.length != 7) return outerUpper;
  final intensity = (1.0 - (openness / 0.6)).clamp(0.0, 1.0);
  final peakUp = size.height * 0.028 * intensity;
  final dipDown = size.height * 0.013 * intensity;
  final m = List<Offset>.from(outerUpper);
  m[2] = Offset(m[2].dx, m[2].dy - peakUp);
  m[3] = Offset(m[3].dx, m[3].dy + dipDown);
  m[4] = Offset(m[4].dx, m[4].dy - peakUp);
  return m;
}

/// Unifica comisuras izquierda y derecha entre outerUpper y outerLower
List<List<Offset>> unifyCommissures(List<List<Offset>> contours) {
  if (contours.length != 4) return contours;
  final outerUpper = List<Offset>.from(contours[0]);
  final outerLower = List<Offset>.from(contours[3]);

  final leftX = (outerUpper[0].dx + outerLower[0].dx) / 2.0;
  final leftY = (outerUpper[0].dy + outerLower[0].dy) / 2.0;
  outerUpper[0] = Offset(leftX, leftY);
  outerLower[0] = Offset(leftX, leftY);

  final rightX = (outerUpper[6].dx + outerLower[6].dx) / 2.0;
  final rightY = (outerUpper[6].dy + outerLower[6].dy) / 2.0;
  outerUpper[6] = Offset(rightX, rightY);
  outerLower[6] = Offset(rightX, rightY);

  return [outerUpper, contours[1], contours[2], outerLower];
}

Offset _clampOffset(Offset offset, Size size) {
  return Offset(
    offset.dx.clamp(0.0, size.width),
    offset.dy.clamp(0.0, size.height),
  );
}

// ==================== GEOMETRÍA DE LENGUA ====================

const double _TONGUE_MAX_PROTRUSION = 0.12;
const double _TONGUE_MAX_HEIGHT = 0.35;
const double _TONGUE_DEFAULT_HEIGHT = 0.18;

/// Genera el path de la lengua para renderizado 2D paramétrico
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
  const baseWidth = 0.20;
  const baseY = _CENTER_Y + 0.25;
  final frontY =
      _CENTER_Y +
      _TONGUE_DEFAULT_HEIGHT -
      (tongueHeightFront * _TONGUE_MAX_HEIGHT);
  final protrusionOffset = (protrusion * _TONGUE_MAX_PROTRUSION).clamp(
    -0.06,
    0.06,
  );
  final effectiveWidth = tongueWidth * 0.35;
  final cx = _CENTER_X * size.width;

  final baseLeft = Offset(
    cx - baseWidth * size.width,
    baseY * size.height,
  ).clamp(size);
  final baseRight = Offset(
    cx + baseWidth * size.width,
    baseY * size.height,
  ).clamp(size);
  final dentalMarginMax = size.width * 0.85;
  final frontTip = Offset(
    (cx + protrusionOffset * size.width).clamp(0.0, dentalMarginMax),
    (frontY * size.height).clamp(0.0, size.height),
  );
  final frontLeft = Offset(
    (cx - effectiveWidth * size.width).clamp(0.0, size.width),
    (frontY * size.height + size.height * 0.05).clamp(0.0, size.height),
  );
  final frontRight = Offset(
    (cx + effectiveWidth * size.width).clamp(0.0, size.width),
    (frontY * size.height + size.height * 0.05).clamp(0.0, size.height),
  );

  path.moveTo(baseLeft.dx, baseLeft.dy);
  path.quadraticBezierTo(
    baseLeft.dx - size.width * 0.02,
    (baseLeft.dy + frontLeft.dy) / 2,
    frontLeft.dx,
    frontLeft.dy,
  );
  path.quadraticBezierTo(
    (frontLeft.dx + frontTip.dx) / 2,
    frontTip.dy - size.height * 0.02,
    frontTip.dx,
    frontTip.dy,
  );
  path.quadraticBezierTo(
    (frontTip.dx + frontRight.dx) / 2,
    frontTip.dy - size.height * 0.02,
    frontRight.dx,
    frontRight.dy,
  );
  path.quadraticBezierTo(
    baseRight.dx + size.width * 0.02,
    (frontRight.dy + baseRight.dy) / 2,
    baseRight.dx,
    baseRight.dy,
  );
  path.lineTo(baseLeft.dx, baseLeft.dy);
  path.close();
  return path;
}

extension _OffsetClamp on Offset {
  Offset clamp(Size size) {
    return Offset(dx.clamp(0.0, size.width), dy.clamp(0.0, size.height));
  }
}
