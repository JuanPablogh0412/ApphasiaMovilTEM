library;

/// Definición de visemas para animación labial
///
/// Cada visema representa una configuración específica de los labios
/// mediante tres parámetros numéricos normalizados [0.0 - 1.0]

/// Clase que representa un visema (posición labial + lengua)
///
/// CHANGES: Extendida con propiedades de lengua (v2.0)
/// CHANGES: Añadidos parámetros de micro-animación de lengua (v2.1 - Feb 2026)
class Viseme {
  /// Apertura vertical de los labios [0.0 - 1.0]
  final double openness;

  /// Anchura horizontal de los labios [0.0 - 1.0]
  final double width;

  /// Redondez tipo O/U [0.0 - 1.0]
  final double roundness;

  /// Nombre descriptivo del visema
  final String name;

  // CHANGES: Propiedades de lengua (v2.0)

  /// Indica si la lengua es visible para este visema
  final bool tongueVisible;

  /// Altura del punto frontal de la lengua [0.0 - 1.0]
  /// 0.0 = baja (s, t, d), 1.0 = alta (l, n)
  final double tongueHeightFront;

  /// Ancho de la lengua [0.0 - 1.0]
  final double tongueWidth;

  /// Protrusión de la lengua [-1.0 a 1.0]
  /// -1.0 = retraída, 0.0 = neutral, 1.0 = protruida
  final double tongueProtrusion;

  // CHANGES: Micro-animaciones procedurales de lengua (v2.1 - Feb 2026)

  /// Activa vibración visual de la lengua (trill /r/)
  final bool tongueVibrateEnabled;

  /// Frecuencia de vibración en Hz (típico: 20-30 Hz para /r/)
  final double tongueVibrateFreqHz;

  /// Amplitud de vibración normalizada [0.0 - 0.1]
  /// Modula tongueHeightFront con sin(2π f t) * amp
  final double tongueVibrateAmp;

  /// Activa bump único de lengua (tap /ɾ/ o oclusivas /t/, /d/)
  final bool tongueBumpEnabled;

  /// Duración del bump en milisegundos (tap: 80-120ms, oclusivas: 40-80ms)
  final double tongueBumpDurationMs;

  const Viseme({
    required this.openness,
    required this.width,
    required this.roundness,
    required this.name,
    this.tongueVisible = false,
    this.tongueHeightFront = 0.5,
    this.tongueWidth = 0.7,
    // CHANGES: Default ligeramente retraído para evitar protrusión excesiva
    this.tongueProtrusion = -0.02,
    // CHANGES: Micro-animaciones desactivadas por defecto
    this.tongueVibrateEnabled = false,
    this.tongueVibrateFreqHz = 0.0,
    this.tongueVibrateAmp = 0.0,
    this.tongueBumpEnabled = false,
    this.tongueBumpDurationMs = 0.0,
  })  : assert(openness >= 0.0 && openness <= 1.0),
        assert(width >= 0.0 && width <= 1.0),
        assert(roundness >= 0.0 && roundness <= 1.0),
        assert(tongueHeightFront >= 0.0 && tongueHeightFront <= 1.0),
        assert(tongueWidth >= 0.0 && tongueWidth <= 1.0),
        assert(tongueProtrusion >= -1.0 && tongueProtrusion <= 1.0),
        assert(tongueVibrateFreqHz >= 0.0),
        assert(tongueVibrateAmp >= 0.0 && tongueVibrateAmp <= 0.15),
        assert(tongueBumpDurationMs >= 0.0);

  /// Interpolación lineal entre dos visemas
  ///
  /// [other] El visema destino
  /// [t] Factor de interpolación [0.0 - 1.0]
  ///
  /// Retorna un nuevo visema interpolado
  ///
  /// CHANGES: Ahora incluye interpolación de propiedades de lengua (v2.0)
  /// CHANGES: Añadida interpolación de parámetros de micro-animación (v2.1)
  Viseme lerp(Viseme other, double t) {
    assert(t >= 0.0 && t <= 1.0);

    return Viseme(
      openness: openness + (other.openness - openness) * t,
      width: width + (other.width - width) * t,
      roundness: roundness + (other.roundness - roundness) * t,
      name: 'interpolated',
      // Interpolar lengua: visible si CUALQUIERA de los dos es visible
      tongueVisible: tongueVisible || other.tongueVisible,
      tongueHeightFront:
          tongueHeightFront + (other.tongueHeightFront - tongueHeightFront) * t,
      tongueWidth: tongueWidth + (other.tongueWidth - tongueWidth) * t,
      tongueProtrusion:
          tongueProtrusion + (other.tongueProtrusion - tongueProtrusion) * t,
      // CHANGES: Micro-animaciones - heredar del visema de destino (no interpolar)
      // Razón: vibrate/bump son eventos discretos, no continuos
      tongueVibrateEnabled:
          t > 0.5 ? other.tongueVibrateEnabled : tongueVibrateEnabled,
      tongueVibrateFreqHz:
          t > 0.5 ? other.tongueVibrateFreqHz : tongueVibrateFreqHz,
      tongueVibrateAmp: t > 0.5 ? other.tongueVibrateAmp : tongueVibrateAmp,
      tongueBumpEnabled: t > 0.5 ? other.tongueBumpEnabled : tongueBumpEnabled,
      tongueBumpDurationMs:
          t > 0.5 ? other.tongueBumpDurationMs : tongueBumpDurationMs,
    );
  }

  @override
  String toString() {
    // CHANGES: Añadido info de micro-animaciones (v2.1)
    final tongueInfo = tongueVisible
        ? "visible(h=$tongueHeightFront${tongueVibrateEnabled ? ',trill=${tongueVibrateFreqHz}Hz' : ''}${tongueBumpEnabled ? ',bump=${tongueBumpDurationMs}ms' : ''})"
        : "hidden";
    return 'Viseme($name: o=$openness, w=$width, r=$roundness, tongue=$tongueInfo)';
  }
}

/// Visemas definidos según especificación TEM - VERSIÓN MEJORADA
/// Ajustados para labios separados con mayor realismo
class Visemes {
  /// Posición neutral/reposo
  static const Viseme neutral = Viseme(
    openness: 0.15,
    width: 0.5,
    roundness: 0.0,
    name: 'Neutral',
  );

  /// Vocal A - boca muy abierta y ancha
  static const Viseme a = Viseme(
    openness: 0.95, // Muy abierto - debe verse interior oscuro
    width: 0.9, // Ancho para ver separación
    roundness: 0.0,
    name: 'A',
  );

  /// Vocal E - boca semi-abierta y muy ancha (sonrisa)
  static const Viseme e = Viseme(
    openness: 0.55, // Apertura moderada visible
    width: 1.0, // Máximo ancho
    roundness: 0.0,
    name: 'E',
  );

  /// Vocal I - boca poco abierta y muy ancha (sonrisa amplia)
  static const Viseme i = Viseme(
    openness: 0.3, // Ligera apertura visible
    width: 1.0,
    roundness: 0.0,
    name: 'I',
  );

  /// Vocal O - boca abierta y muy redondeada
  static const Viseme o = Viseme(
    openness: 0.85, // Muy abierto en forma circular
    width: 0.35, // Estrecho redondeado
    roundness: 1.0,
    name: 'O',
  );

  /// Vocal U - boca poco abierta y muy redondeada (labios hacia adelante)
  static const Viseme u = Viseme(
    openness: 0.45, // Apertura moderada, proyectados
    width: 0.2, // Muy estrecho
    roundness: 1.0,
    name: 'U',
  );

  /// Boca cerrada para consonantes bilabiales (m, b, p)
  static const Viseme cerrada = Viseme(
    openness: 0.0,
    width: 0.5,
    roundness: 0.0,
    name: 'Cerrada',
  );

  /// Mapeo COMPLETO de fonema a visema según reglas TEM
  ///
  /// CHANGES: Expandido para TODOS los fonemas del español (20+ fonemas)
  /// CHANGES: Añadidos mapeos de lengua (v2.0) para consonantes linguales
  /// CHANGES: Configuraciones de micro-animación para alveolares y vibrantes (v2.1 - Feb 2026)
  ///
  /// [phoneme] Fonema en minúscula (símbolos SAMPA o grafemas españoles)
  ///
  /// Retorna el visema correspondiente con propiedades de lengua y animaciones
  static Viseme fromPhoneme(String phoneme) {
    final p = phoneme.toLowerCase();

    // ==================== VOCALES ====================
    if (p == 'a' || p == 'á') return a;
    if (p == 'e' || p == 'é') return e;
    if (p == 'i' || p == 'í' || p == 'y') return i; // 'y' como vocal
    if (p == 'o' || p == 'ó') return o;
    if (p == 'u' || p == 'ú' || p == 'ü') return u;

    // ==================== CONSONANTES BILABIALES ====================
    // Requieren contacto labial → boca cerrada
    if (p == 'm' || p == 'b' || p == 'p') return cerrada;

    // ==================== CONSONANTES LABIODENTALES ====================
    // f, v → Labio inferior toca dientes superiores
    if (p == 'f' || p == 'v') {
      return const Viseme(
        openness: 0.25,
        width: 0.55,
        roundness: 0.0,
        name: 'Labiodental-F',
      );
    }

    // ==================== CONSONANTES ALVEOLARES LATERALES ====================
    // CHANGES: l → Lengua alta tocando alvéolos (v2.1 - configuración refinada)
    if (p == 'l') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Alveolar-L',
        tongueVisible: true,
        tongueHeightFront: 0.78, // Alta - toca alvéolos
        tongueWidth: 0.8,
        tongueProtrusion: 0.0,
      );
    }

    // ==================== CONSONANTES ALVEOLARES NASALES ====================
    // CHANGES: n → Lengua media-alta tocando alvéolos (v2.1 - configuración refinada)
    if (p == 'n') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Alveolar-N',
        tongueVisible: true,
        tongueHeightFront: 0.55, // Media-alta
        tongueWidth: 0.8,
        tongueProtrusion: 0.0,
      );
    }

    // ==================== CONSONANTES PALATALES NASALES ====================
    // CHANGES: ñ → Lengua elevada hacia paladar (v2.1 - configuración refinada)
    if (p == 'ñ') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Palatal-Ñ',
        tongueVisible: true,
        tongueHeightFront: 0.70, // Elevada hacia paladar
        tongueWidth: 0.8,
        tongueProtrusion: 0.0,
      );
    }

    // ==================== CONSONANTES DENTALES/ALVEOLARES OCLUSIVAS ====================
    // CHANGES: t, d → Lengua baja-media con BUMP para oclusión (v2.1)
    if (p == 't' || p == 'd') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Dental-T/D',
        tongueVisible: true,
        tongueHeightFront: 0.62, // Media (ajustada desde 0.45)
        tongueWidth: 0.6,
        tongueProtrusion: 0.0,
        // CHANGES: Bump para representar oclusión breve
        tongueBumpEnabled: true,
        tongueBumpDurationMs: 60.0, // 60ms - oclusión breve en onset
      );
    }

    // ==================== CONSONANTES ALVEOLARES FRICATIVAS ====================
    // s, z → Dientes casi cerrados (apenas se aprecian), labios ligeramente
    // separados y extendidos para exponer los dientes, lengua en posición
    // alveolar alta con leve protrusión hacia el borde dental.
    if (p == 's' || p == 'z') {
      return const Viseme(
        openness:
            0.08, // Casi cerrado: labios apenas entreabiertos (se ven dientes)
        width: 0.65, // Labios algo extendidos para mostrar los dientes
        roundness: 0.0,
        name: 'Fricativa-S',
        tongueVisible: true,
        tongueHeightFront:
            0.48, // Media-alta: punta cerca de los alvéolos/dientes
        tongueWidth: 0.42, // Estrecha para el surco central
        tongueProtrusion: 0.04, // Punta levemente hacia los dientes superiores
      );
    }

    // ==================== CONSONANTES ALVEOLARES VIBRANTES ====================

    // CHANGES: r simple (tap/flap /ɾ/) → BUMP único y rápido (v2.1)
    if (p == 'r' && p.length == 1) {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Vibrante-Tap-R',
        tongueVisible: true,
        tongueHeightFront: 0.70, // Alta para tap alveolar
        tongueWidth: 0.7,
        tongueProtrusion: 0.0,
        // CHANGES: Tap = bump único de ~110ms
        tongueBumpEnabled: true,
        tongueBumpDurationMs: 110.0, // 110ms - tap pronunciado
      );
    }

    // CHANGES: rr (trill /r/) → VIBRACIÓN visual continua (v2.1)
    if (p == 'rr') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Vibrante-Trill-RR',
        tongueVisible: true,
        tongueHeightFront: 0.75, // Alta - posición base del trill
        tongueWidth: 0.7,
        tongueProtrusion: 0.0,
        // CHANGES: Trill visual - oscilación rápida de la punta
        tongueVibrateEnabled: true,
        tongueVibrateFreqHz:
            24.0, // 24 Hz - frecuencia típica del trill español
        tongueVibrateAmp: 0.03, // Amplitud pequeña (3% de altura normalizada)
      );
    }

    // ==================== CONSONANTES PALATALES AFRICADAS/FRICATIVAS ====================
    // CHANGES: ch (tʃ), ll (ʝ), y consonante → Lengua media-elevada (v2.1)
    if (p == 'ch' || p == 'll' || p == 'j') {
      return const Viseme(
        openness: 0.20,
        width: 0.5,
        roundness: 0.0,
        name: 'Palatal-CH/LL',
        tongueVisible: true,
        tongueHeightFront: 0.62, // Media-elevada hacia paladar
        tongueWidth: 0.7,
        tongueProtrusion: 0.0,
      );
    }

    // ==================== CONSONANTES VELARES ====================
    // k, g, x → Labios neutrales (lengua toca velo, no visible frontalmente)
    if (p == 'k' || p == 'g' || p == 'c' || p == 'q' || p == 'x') {
      return neutral;
    }

    // ==================== CONSONANTES APROXIMANTES/FRICATIVAS ====================
    // w → Similar a U (labios redondeados)
    if (p == 'w') return u;

    // h → Neutra (en español, h es muda)
    if (p == 'h') return neutral;

    // ==================== DEFAULT ====================
    return neutral;
  }
}
