library;

import 'package:flutter/material.dart';
import 'lip_viseme.dart';
import 'lip_model.dart';
import 'tongue_animation.dart'; // CHANGES: Import para micro-animaciones (v2.1)

// CHANGES: Updated to use generateLipContours() directly (no LipModel class)
// CHANGES: Added debug mode with visual overlay showing 28 points and timeline bar
// CHANGES: Extended with tongue micro-animation support (v2.1 - Feb 2026)

/// Renderizador paramétrico de labios usando CustomPainter
///
/// Responsabilidades:
/// - Dibujar labios con 4 contornos × 7 puntos = 28 puntos totales
/// - Mostrar dientes, interior oscuro, grosor variable
/// - CHANGES: Renderizar micro-animaciones de lengua (bumps + trills)
/// - Opcional: Modo debug con puntos coloreados y timeline

class LipPainter extends CustomPainter {
  /// Visema actual a renderizar
  final Viseme viseme;

  /// Color de los labios
  final Color lipColor;

  /// Modo debug: muestra los 28 puntos de control y timeline
  final bool debugMode;

  /// Progreso actual en la animación [0.0 - 1.0] (para barra de timeline en debug)
  final double? timelineProgress;

  // CHANGES: Parámetros de animación de lengua (v2.1)

  /// Tiempo transcurrido desde el inicio del evento actual (en ms)
  /// Usado para calcular bumps y trills en tiempo real
  final double elapsedEventMs;

  /// Fase del trill (radianes) - aleatorizada por evento para naturalidad
  final double trillPhase;

  LipPainter({
    required this.viseme,
    this.lipColor = const Color(0xFFB71C1C),
    this.debugMode = false,
    this.timelineProgress,
    // CHANGES: Parámetros opcionales de animación (v2.1)
    this.elapsedEventMs = 0.0,
    this.trillPhase = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Obtener los 28 puntos de control ───────────────────────────────────
    final rawContours = generateLipContours(
      viseme.openness,
      viseme.width,
      viseme.roundness,
      size,
    );

    // ── 2. Unificar comisuras (CRÍTICO: boca como unidad) ─────────────────────
    final contours = unifyCommissures(rawContours);
    final outerUpper = contours[0];
    final innerUpper = contours[1];
    final innerLower = contours[2];
    final outerLower = contours[3];

    // ── 3. Aplicar arco de Cupido SOLO al labio superior ──────────────────────
    final upperWithBow = applyCupidsBow(outerUpper, viseme.openness, size);

    // ── 4. Calcular comisuras unificadas (puntos de anclaje) ──────────────────
    final commL = outerUpper[0]; // = outerLower[0] tras unifyCommissures
    final commR = outerUpper[6]; // = outerLower[6] tras unifyCommissures

    // ── 5. Bounds (mantenidos para compatibilidad con _calculateBounds) ──────────
    // Los gradientes fueron eliminados; los labios usan color plano.
    const upperBounds = Rect.zero;
    const lowerBounds = Rect.zero;

    // ── 6. CAPA 1: Interior de la boca ────────────────────────────────────────
    // Se pasan commL/commR para que el relleno llegue hasta la comisura exterior
    // y cubra el triángulo blanco que aparece en las esquinas.
    if (viseme.openness > 0.05) {
      _paintMouthInterior(canvas, innerUpper, innerLower, commL, commR);
    }

    // ── 7. CAPA 2: Lengua ─────────────────────────────────────────────────────
    if (viseme.tongueVisible && viseme.openness > 0.05) {
      _paintTongue(canvas, innerUpper, innerLower, size);
    }

    // ── 8. CAPA 3: Dientes ────────────────────────────────────────────────────
    if (viseme.openness > 0.15) {
      _paintTeeth(canvas, innerUpper, innerLower, size);
    }

    // ── 9. CAPA 4: Labio inferior ─────────────────────────────────────────────
    // El labio inferior es una curva convexa SIMPLE, sin arco de Cupido.
    _paintLipZone(
      canvas: canvas,
      outerPts: outerLower,
      innerPts: innerLower,
      commL: commL,
      commR: commR,
      lipPaint: _lowerLipPaint(lowerBounds, lipColor),
      isUpper: false,
    );

    // ── 10. CAPA 5: Labio superior ────────────────────────────────────────────
    // El labio superior usa los puntos con arco de Cupido.
    _paintLipZone(
      canvas: canvas,
      outerPts: upperWithBow,
      innerPts: innerUpper,
      commL: commL,
      commR: commR,
      lipPaint: _upperLipPaint(upperBounds, lipColor),
      isUpper: true,
    );

    // ── 11. Brillos y detalles eliminados (color plano solicitado) ───────────────

    // ── 12. Debug ─────────────────────────────────────────────────────────────
    if (debugMode) {
      _paintDebugOverlay(
          canvas, size, [outerUpper, innerUpper, innerLower, outerLower]);
    }
  }

  /// Calcula el rectángulo delimitador de un conjunto de puntos
  Rect _calculateBounds(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;

    double minX = points[0].dx;
    double maxX = points[0].dx;
    double minY = points[0].dy;
    double maxY = points[0].dy;

    for (final point in points) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ==================== HELPERS DE CONVERSIÓN CATMULL-ROM ====================

  /// Calcula los 2 handles Bézier cúbicos para el segmento pts[i] → pts[i+1].
  /// Cubre todos los índices incluyendo extremos (0 y length-2) mediante
  /// clamping de los vecinos.
  /// tension: 0.0 = recto, 0.5 = muy curvo. Recomendado: 0.22
  List<Offset> _crHandles(List<Offset> pts, int i, {double tension = 0.22}) {
    final n = pts.length;
    final p0 = pts[(i - 1).clamp(0, n - 1)];
    final p1 = pts[i.clamp(0, n - 1)];
    final p2 = pts[(i + 1).clamp(0, n - 1)];
    final p3 = pts[(i + 2).clamp(0, n - 1)];

    // Tangente en p1 y p2 (Catmull-Rom)
    final dx1 = (p2.dx - p0.dx) * tension;
    final dy1 = (p2.dy - p0.dy) * tension;
    final dx2 = (p3.dx - p1.dx) * tension;
    final dy2 = (p3.dy - p1.dy) * tension;

    return [
      Offset(p1.dx + dx1 / 3.0, p1.dy + dy1 / 3.0),
      Offset(p2.dx - dx2 / 3.0, p2.dy - dy2 / 3.0),
    ];
  }

  // ==================== HELPERS DE GRADIENTES Y PINTURAS ====================

  /// Retorna Paint de color sólido para labio SUPERIOR (sin gradiente)
  Paint _upperLipPaint(Rect bounds, Color baseColor) {
    return Paint()
      ..color = baseColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
  }

  /// Retorna Paint de color sólido para labio INFERIOR (sin gradiente)
  Paint _lowerLipPaint(Rect bounds, Color baseColor) {
    return Paint()
      ..color = baseColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
  }

  // ==================== MÉTODOS DE RENDERIZADO MEJORADOS ====================

  /// Pinta labio CON curvas cúbicas suaves (Catmull-Rom)
  /// Reemplazo de _paintLipWithThickness con gradientes volumétricos
  /// Pinta una zona labial (superior o inferior) como una forma orgánica
  /// anclada en las comisuras. Las comisuras son puntos FIJOS que no
  /// varían entre el labio superior e inferior.
  ///
  /// [outerPts] : 7 puntos del contorno exterior del labio
  /// [innerPts] : 7 puntos del contorno interior del labio (borde de la apertura)
  /// [commL]    : comisura izquierda unificada
  /// [commR]    : comisura derecha unificada
  /// [isUpper]  : true = labio superior, false = labio inferior
  void _paintLipZone({
    required Canvas canvas,
    required List<Offset> outerPts,
    required List<Offset> innerPts,
    required Offset commL,
    required Offset commR,
    required Paint lipPaint,
    required bool isUpper,
  }) {
    final path = Path();

    // ── Iniciar en comisura izquierda ─────────────────────────────────────────
    path.moveTo(commL.dx, commL.dy);

    // ── Trazar arco exterior del labio ───────────────────────────────────────
    // Usamos spline cúbico Catmull-Rom para toda la longitud (índices 0 a 6).
    // El primer y último punto son las comisuras, que ya están ancladas.
    for (int i = 0; i < outerPts.length - 1; i++) {
      final h = _crHandles(outerPts, i);
      path.cubicTo(
        h[0].dx,
        h[0].dy,
        h[1].dx,
        h[1].dy,
        outerPts[i + 1].dx,
        outerPts[i + 1].dy,
      );
    }
    // Ahora estamos en commR (outerPts[6])

    // ── Curva de cierre en comisura derecha ──────────────────────────────────
    // La curva conecta el extremo del arco exterior con el extremo del arco
    // interior. Para que se vea redondeada (no puntiaguda), usamos un arco
    // que "dobla" alrededor del punto de comisura.
    final innerEnd = innerPts[innerPts.length - 1]; // innerPts[6]
    // Control point: ligeramente "afuera" de la comisura
    final cpR = Offset(
      commR.dx + (commR.dx - innerEnd.dx) * 0.3,
      commR.dy,
    );
    path.quadraticBezierTo(cpR.dx, cpR.dy, innerEnd.dx, innerEnd.dy);

    // ── Trazar arco interior del labio (en sentido inverso) ──────────────────
    for (int i = innerPts.length - 1; i > 0; i--) {
      final rev = innerPts.reversed.toList();
      final ri = innerPts.length - 1 - i;
      final h = _crHandles(rev, ri);
      path.cubicTo(
        h[0].dx,
        h[0].dy,
        h[1].dx,
        h[1].dy,
        innerPts[i - 1].dx,
        innerPts[i - 1].dy,
      );
    }
    // Ahora estamos en innerPts[0] (comisura interior izquierda)

    // ── Cierre en comisura izquierda ─────────────────────────────────────────
    final innerStart = innerPts[0];
    final cpL = Offset(
      commL.dx + (commL.dx - innerStart.dx) * 0.3,
      commL.dy,
    );
    path.quadraticBezierTo(cpL.dx, cpL.dy, commL.dx, commL.dy);

    path.close();

    lipPaint.isAntiAlias = true;
    canvas.drawPath(path, lipPaint);
  }

  /// Pinta el interior oscuro de la boca (espacio entre bordes INTERIORES)
  /// CHANGES: Gradiente radial para simular profundidad (faringe oscura)
  /// CHANGES v5: Recibe commL/commR para extender el relleno hasta las comisuras
  /// exteriores y eliminar los triángulos blancos en las esquinas de la boca.
  void _paintMouthInterior(
    Canvas canvas,
    List<Offset> upperInner,
    List<Offset> lowerInner,
    Offset commL,
    Offset commR,
  ) {
    // Calcular bounds extendidos hasta las comisuras exteriores
    final leftX = commL.dx;
    final rightX = commR.dx;
    final topY = upperInner[3].dy;
    final bottomY = lowerInner[3].dy;

    final interiorBounds = Rect.fromLTRB(leftX, topY, rightX, bottomY);

    // Gradiente radial: centro oscuro (faringe) → bordes más claros
    final interiorPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [
          Color(0xFF1A0000), // Centro muy oscuro (faringe profunda)
          Color(0xFF580000), // Transición
          Color(0xFF880000), // Bordes (tejido bucal visible)
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(interiorBounds)
      ..style = PaintingStyle.fill;

    final path = Path();

    // ── Arrancar desde la comisura EXTERIOR izquierda ──────────────────────────
    // Esto cubre el triángulo entre commL, innerUpper[0] e innerLower[0]
    path.moveTo(commL.dx, commL.dy);

    // ── Borde interior del labio SUPERIOR (izquierda → derecha) ───────────────
    path.lineTo(upperInner[0].dx, upperInner[0].dy);
    for (int i = 0; i < upperInner.length - 1; i++) {
      final h = _crHandles(upperInner, i);
      path.cubicTo(
        h[0].dx,
        h[0].dy,
        h[1].dx,
        h[1].dy,
        upperInner[i + 1].dx,
        upperInner[i + 1].dy,
      );
    }
    // Ahora en upperInner[6]

    // ── Llegar a la comisura EXTERIOR derecha ─────────────────────────────────
    path.lineTo(commR.dx, commR.dy);

    // ── Bajar al borde interior del labio INFERIOR (derecha) ─────────────────
    path.lineTo(lowerInner[6].dx, lowerInner[6].dy);

    // ── Borde interior del labio INFERIOR (de derecha a izquierda) ────────────
    final lowerRev = lowerInner.reversed.toList();
    for (int i = 0; i < lowerRev.length - 1; i++) {
      final h = _crHandles(lowerRev, i);
      path.cubicTo(
        h[0].dx,
        h[0].dy,
        h[1].dx,
        h[1].dy,
        lowerRev[i + 1].dx,
        lowerRev[i + 1].dy,
      );
    }
    // Ahora en lowerInner[0]

    // ── Volver a la comisura EXTERIOR izquierda y cerrar ──────────────────────
    path.lineTo(commL.dx, commL.dy);
    path.close();

    canvas.drawPath(path, interiorPaint);
  }

  /// Pinta un labio CON GROSOR (entre borde exterior e interior)
  void _paintLipWithThickness(
      Canvas canvas, List<Offset> outer, List<Offset> inner, Color color,
      {required bool isUpperLip}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();

    // CONTORNO EXTERIOR (izquierda a derecha)
    path.moveTo(outer[0].dx, outer[0].dy);
    for (int i = 0; i < outer.length - 1; i++) {
      path.quadraticBezierTo(
        outer[i].dx,
        outer[i].dy,
        outer[i + 1].dx,
        outer[i + 1].dy,
      );
    }

    // Conectar con borde INTERIOR en comisura derecha
    path.lineTo(inner[6].dx, inner[6].dy);

    // CONTORNO INTERIOR (derecha a izquierda)
    for (int i = 6; i > 0; i--) {
      path.quadraticBezierTo(
        inner[i].dx,
        inner[i].dy,
        inner[i - 1].dx,
        inner[i - 1].dy,
      );
    }

    // Cerrar en comisura izquierda
    path.close();

    // Sombra sutil para profundidad
    canvas.drawShadow(
      path,
      Colors.black.withOpacity(0.2),
      isUpperLip ? 1.5 : 2.0,
      false,
    );

    canvas.drawPath(path, paint);
  }

  /// Pinta los dientes dentro de la boca (superiores E inferiores)
  /// CHANGES: Anatomía detallada con encías (gum tissue) y separación individual
  void _paintTeeth(Canvas canvas, List<Offset> upperInner,
      List<Offset> lowerInner, Size size) {
    // Número de dientes a mostrar
    const numTeeth = 6;
    // FIX v4: Dientes más centrados y compactos
    final teethAreaWidth = (upperInner[6].dx - upperInner[0].dx) *
        0.62; // 62% del ancho de apertura
    final teethLeft = upperInner[0].dx +
        (upperInner[6].dx - upperInner[0].dx) * 0.19; // Centrado ajustado
    final toothWidth = teethAreaWidth / numTeeth;
    final gap = toothWidth *
        0.03; // FIX v4: Separación interproximal mínima (casi imperceptible)

    // Altura de dientes variable según apertura
    final teethHeight = size.height * 0.035 * (viseme.openness + 0.3);
    final gumHeight = teethHeight * 0.25; // Altura de encía visible

    // Colores anatómicos
    const toothColor = Color(0xFFFFFAF0); // Blanco marfil (esmalte dental)
    const gumColor = Color(0xFFBB7070); // Rosa pálido (tejido gingival)

    final toothPaint = Paint()
      ..color = toothColor
      ..style = PaintingStyle.fill;

    final gumPaint = Paint()
      ..color = gumColor
      ..style = PaintingStyle.fill;

    // ========== ENCÍA SUPERIOR + DIENTES SUPERIORES ==========
    final upperTeethY = upperInner[3].dy;

    // Banda de encía superior
    final upperGumRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        teethLeft,
        upperTeethY - gumHeight,
        teethAreaWidth,
        gumHeight,
      ),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(upperGumRect, gumPaint);

    // Dientes superiores
    for (int i = 0; i < numTeeth; i++) {
      final x = teethLeft + (i * toothWidth);

      // Rectángulo del diente superior (borde superior redondeado)
      final upperToothRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          x + gap,
          upperTeethY,
          toothWidth - (gap * 2),
          teethHeight,
        ),
        topLeft: const Radius.circular(2.0),
        topRight: const Radius.circular(2.0),
        bottomLeft: const Radius.circular(0.5),
        bottomRight: const Radius.circular(0.5),
      );

      canvas.drawRRect(upperToothRect, toothPaint);

      // Gradiente de volumen (zona oclusal más oscura)
      final shadowPaint = Paint()
        ..color = Colors.grey.withOpacity(0.18)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x + gap,
            upperTeethY + teethHeight * 0.75,
            toothWidth - (gap * 2),
            teethHeight * 0.25,
          ),
          const Radius.circular(0.5),
        ),
        shadowPaint,
      );
    }

    // ========== ENCÍA INFERIOR + DIENTES INFERIORES ==========
    final lowerTeethY = lowerInner[3].dy - teethHeight;

    // Dientes inferiores
    for (int i = 0; i < numTeeth; i++) {
      final x = teethLeft + (i * toothWidth);

      // Rectángulo del diente inferior (borde inferior redondeado)
      final lowerToothRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          x + gap,
          lowerTeethY,
          toothWidth - (gap * 2),
          teethHeight,
        ),
        topLeft: const Radius.circular(0.5),
        topRight: const Radius.circular(0.5),
        bottomLeft: const Radius.circular(2.0),
        bottomRight: const Radius.circular(2.0),
      );

      canvas.drawRRect(lowerToothRect, toothPaint);

      // Gradiente de volumen (zona coronal más clara)
      final shadowPaint = Paint()
        ..color = Colors.grey.withOpacity(0.18)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x + gap,
            lowerTeethY,
            toothWidth - (gap * 2),
            teethHeight * 0.25,
          ),
          const Radius.circular(0.5),
        ),
        shadowPaint,
      );
    }

    // Banda de encía inferior
    final lowerGumRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        teethLeft,
        lowerInner[3].dy,
        teethAreaWidth,
        gumHeight,
      ),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(lowerGumRect, gumPaint);
  }

  /// Pinta la lengua dentro de la cavidad oral (solo si está visible)
  /// Usa CLIPPING al interior de la boca para evitar overflow
  /// Pinta la lengua con micro-animaciones (bumps + trills)
  ///
  /// CHANGES: Implementa animación procedural de lengua (v2.1 - Feb 2026)
  /// CHANGES: Gradiente volumétrico + surco medio (median groove) (v2.2)
  void _paintTongue(Canvas canvas, List<Offset> upperInner,
      List<Offset> lowerInner, Size size) {
    // ========== PASO 1: Crear path de CLIPPING (interior de la boca) ==========
    final clipPath = Path();

    // Borde superior interior (izquierda a derecha)
    clipPath.moveTo(upperInner[0].dx, upperInner[0].dy);
    for (int i = 0; i < upperInner.length - 1; i++) {
      clipPath.quadraticBezierTo(
        upperInner[i].dx,
        upperInner[i].dy,
        upperInner[i + 1].dx,
        upperInner[i + 1].dy,
      );
    }

    // Conectar con comisura derecha del labio inferior
    clipPath.lineTo(lowerInner[6].dx, lowerInner[6].dy);

    // Borde inferior interior (derecha a izquierda)
    for (int i = 6; i > 0; i--) {
      clipPath.quadraticBezierTo(
        lowerInner[i].dx,
        lowerInner[i].dy,
        lowerInner[i - 1].dx,
        lowerInner[i - 1].dy,
      );
    }

    // Cerrar el path
    clipPath.close();

    // ========== PASO 2: CALCULAR ALTURA ANIMADA DE LA LENGUA ==========
    // CHANGES: Integrar micro-animaciones (bumps + trills) (v2.1)

    // Amplitud de bump (típico: 0.08-0.12 para oclusivas/taps)
    const double bumpAmplitude = 0.10;

    final animatedHeight = calculateAnimatedTongueHeight(
      baseHeight: viseme.tongueHeightFront,
      // Bump (para /t/, /d/, /ɾ/)
      bumpActive: viseme.tongueBumpEnabled,
      bumpElapsedMs: elapsedEventMs,
      bumpDurationMs: viseme.tongueBumpDurationMs,
      bumpAmplitude: bumpAmplitude,
      // Trill (para /rr/)
      trillActive: viseme.tongueVibrateEnabled,
      trillElapsedMs: elapsedEventMs,
      trillFreqHz: viseme.tongueVibrateFreqHz,
      trillAmplitude: viseme.tongueVibrateAmp,
      trillPhase: trillPhase,
    );

    // ========== PASO 3: Generar path de la lengua CON altura animada ==========
    final tonguePath = generateTonguePath(
      tongueHeightFront: animatedHeight, // CHANGES: Usar altura animada
      tongueWidth: viseme.tongueWidth,
      protrusion: viseme.tongueProtrusion,
      size: size,
    );

    // ========== PASO 4: Calcular bounds para gradiente ==========
    final tonguePathBounds = tonguePath.getBounds();

    // Gradiente volumétrico (centro más claro, bordes más oscuros)
    final tonguePaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          Color(0xFFFFCDD2), // Centro más claro (zona dorsal)
          Color(0xFFFFB6C1), // Rosa pálido (base)
          Color(0xFFD89DA0), // Bordes más oscuros (sombra lateral)
        ],
        stops: [0.0, 0.6, 1.0],
      ).createShader(tonguePathBounds)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // ========== PASO 5: Aplicar clipping y pintar ==========
    canvas.save(); // Guardar estado del canvas
    canvas.clipPath(clipPath); // Aplicar recorte al interior de la boca

    // Sombra sutil para profundidad
    canvas.drawShadow(
      tonguePath,
      Colors.black.withOpacity(0.18),
      2.0,
      false,
    );

    // Dibujar la lengua con gradiente
    canvas.drawPath(tonguePath, tonguePaint);

    // ========== PASO 6: Dibujar surco medio (median groove / lingual sulcus) ==========
    final groovePath = Path();

    // Línea central de la lengua (desde base hasta punta)
    final centerX = tonguePathBounds.center.dx;
    final grooveStartY =
        tonguePathBounds.bottom - tonguePathBounds.height * 0.15;
    final grooveEndY = tonguePathBounds.top + tonguePathBounds.height * 0.15;
    final grooveDepth = tonguePathBounds.width * 0.08;

    groovePath.moveTo(centerX, grooveStartY);

    // Curva suave con quadratic bezier
    groovePath.quadraticBezierTo(
      centerX - grooveDepth * 0.5, // Control point X (ligera curvatura)
      (grooveStartY + grooveEndY) / 2, // Control point Y (punto medio)
      centerX,
      grooveEndY,
    );

    // Pintar surco como línea semitransparente oscura
    final groovePaint = Paint()
      ..color = const Color(0xFF8A2030).withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

    canvas.drawPath(groovePath, groovePaint);

    canvas.restore(); // Restaurar estado del canvas (eliminar clipping)
  }

  // ==================== MÉTODOS DE EFECTOS ESPECULARES ====================

  /// Pinta brillo especular en labio INFERIOR (zona de reflexión de luz)
  /// CHANGES: Efecto gloss para realismo fotográfico (v2.2)
  void _paintLipGloss(
      Canvas canvas, List<Offset> lowerOuter, Rect lowerBounds) {
    // Posición de la zona especular (centro-inferior del labio)
    final glossCenterX = lowerBounds.center.dx;
    final glossCenterY = lowerBounds.top + lowerBounds.height * 0.3;

    // Tamaño del óvalo especular (proporcional al área del labio)
    final glossWidth = lowerBounds.width * 0.4;
    final glossHeight = lowerBounds.height * 0.35;

    // Gradiente radial para el brillo (centro blanco → transparente)
    final glossPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [
          Colors.white.withOpacity(0.28), // Centro brillante
          Colors.white.withOpacity(0.12), // Transición
          Colors.white.withOpacity(0.0), // Bordes transparentes
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCenter(
        center: Offset(glossCenterX, glossCenterY),
        width: glossWidth,
        height: glossHeight,
      ))
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    // Dibujar óvalo especular
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(glossCenterX, glossCenterY),
        width: glossWidth,
        height: glossHeight,
      ),
      glossPaint,
    );
  }

  /// Pinta brillo especular en labio SUPERIOR (arco de Cupido)
  /// CHANGES: Efecto gloss para realismo fotográfico (v2.2)
  void _paintUpperLipGloss(Canvas canvas, Rect upperBounds) {
    // Dos puntos de brillo a ambos lados del arco de Cupido
    final leftGlossX = upperBounds.center.dx - upperBounds.width * 0.15;
    final rightGlossX = upperBounds.center.dx + upperBounds.width * 0.15;
    final glossY = upperBounds.top + upperBounds.height * 0.4;

    final glossWidth = upperBounds.width * 0.22;
    final glossHeight = upperBounds.height * 0.3;

    // Paint para los brillos
    final glossPaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    // Brillo izquierdo
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(leftGlossX, glossY),
        width: glossWidth,
        height: glossHeight,
      ),
      glossPaint,
    );

    // Brillo derecho
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rightGlossX, glossY),
        width: glossWidth,
        height: glossHeight,
      ),
      glossPaint,
    );
  }

  /// Pinta detalles anatómicos en las comisuras de los labios
  /// CHANGES: Líneas de unión + círculos de detalle (v2.2)
  /// Pinta el detalle visual de las comisuras: un pequeño gradiente circular
  /// que suaviza la transición entre labio superior e inferior.
  void _paintLipDetails(Canvas canvas, Offset commL, Offset commR) {
    // Radial gradient suave en cada comisura para unir visualmente los labios
    for (final corner in [commL, commR]) {
      final cornerPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(lipColor, Colors.black, 0.25)!.withOpacity(0.55),
            Color.lerp(lipColor, Colors.black, 0.25)!.withOpacity(0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: corner, radius: 7.0))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(corner, 7.0, cornerPaint);
    }
  }

  /// CHANGES: Nuevo método para debug overlay
  /// Muestra los 28 puntos de control en colores diferentes y barra de timeline
  void _paintDebugOverlay(
      Canvas canvas, Size size, List<List<Offset>> contours) {
    // Colores para los 4 contornos
    const colors = [
      Color(0xFF00FF00), // Verde: Outer upper
      Color(0xFF00FFFF), // Cyan: Inner upper
      Color(0xFFFFFF00), // Amarillo: Inner lower
      Color(0xFFFF00FF), // Magenta: Outer lower
    ];

    final labels = ['OU', 'IU', 'IL', 'OL'];

    // Dibujar puntos de cada contorno
    for (int contourIndex = 0; contourIndex < contours.length; contourIndex++) {
      final points = contours[contourIndex];
      final color = colors[contourIndex];
      final label = labels[contourIndex];

      for (int pointIndex = 0; pointIndex < points.length; pointIndex++) {
        final point = points[pointIndex];

        // Círculo del punto
        final pointPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

        canvas.drawCircle(point, 4.0, pointPaint);

        // Borde negro para contraste
        final borderPaint = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

        canvas.drawCircle(point, 4.0, borderPaint);

        // Etiqueta del punto (ej: "OU-0", "IU-3")
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$label-$pointIndex',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black, blurRadius: 2)],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(point.dx + 6, point.dy - 4));
      }
    }

    // Barra de timeline (si se proporciona progreso)
    if (timelineProgress != null) {
      const barHeight = 8.0;
      final barY = size.height - barHeight - 10;
      final barWidth = size.width * 0.8;
      final barX = (size.width - barWidth) / 2;

      // Fondo de la barra
      final bgPaint = Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barY, barWidth, barHeight),
          const Radius.circular(4),
        ),
        bgPaint,
      );

      // Progreso de la barra
      final progressPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barY, barWidth * timelineProgress!, barHeight),
          const Radius.circular(4),
        ),
        progressPaint,
      );

      // Texto de progreso
      final progressText = TextPainter(
        text: TextSpan(
          text: '${(timelineProgress! * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      progressText.layout();
      progressText.paint(
        canvas,
        Offset(barX + barWidth + 5, barY - 1),
      );
    }
  }

  @override
  bool shouldRepaint(LipPainter oldDelegate) {
    return oldDelegate.viseme.openness != viseme.openness ||
        oldDelegate.viseme.width != viseme.width ||
        oldDelegate.viseme.roundness != viseme.roundness ||
        oldDelegate.lipColor != lipColor ||
        oldDelegate.debugMode != debugMode ||
        oldDelegate.timelineProgress != timelineProgress;
  }
}
