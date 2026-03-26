library;

/// Definición de visemas para animación labial
///
/// Cada visema representa una configuración específica de los labios
/// mediante tres parámetros numéricos normalizados [0.0 - 1.0]
///
/// UBICACIÓN CANÓNICA: lib/data/models/tem/
/// Esta clase es un modelo de datos puro — no tiene dependencias de Flutter UI.
/// Los archivos en presentation/screens/tem/lip_animation/ re-exportan desde aquí.

/// Clase que representa un visema (posición labial + lengua)
class Viseme {
  /// Apertura vertical de los labios [0.0 - 1.0]
  final double openness;

  /// Anchura horizontal de los labios [0.0 - 1.0]
  final double width;

  /// Redondez tipo O/U [0.0 - 1.0]
  final double roundness;

  /// Nombre descriptivo del visema
  final String name;

  /// Indica si la lengua es visible para este visema
  final bool tongueVisible;

  /// Altura del punto frontal de la lengua [0.0 - 1.0]
  final double tongueHeightFront;

  /// Ancho de la lengua [0.0 - 1.0]
  final double tongueWidth;

  /// Protrusión de la lengua [-1.0 a 1.0]
  final double tongueProtrusion;

  /// Activa vibración visual de la lengua (trill /r/)
  final bool tongueVibrateEnabled;

  /// Frecuencia de vibración en Hz (típico: 20-30 Hz para /r/)
  final double tongueVibrateFreqHz;

  /// Amplitud de vibración normalizada [0.0 - 0.1]
  final double tongueVibrateAmp;

  /// Activa bump único de lengua (tap /ɾ/ o oclusivas /t/, /d/)
  final bool tongueBumpEnabled;

  /// Duración del bump en milisegundos
  final double tongueBumpDurationMs;

  const Viseme({
    required this.openness,
    required this.width,
    required this.roundness,
    required this.name,
    this.tongueVisible = false,
    this.tongueHeightFront = 0.5,
    this.tongueWidth = 0.7,
    this.tongueProtrusion = -0.02,
    this.tongueVibrateEnabled = false,
    this.tongueVibrateFreqHz = 0.0,
    this.tongueVibrateAmp = 0.0,
    this.tongueBumpEnabled = false,
    this.tongueBumpDurationMs = 0.0,
  }) : assert(openness >= 0.0 && openness <= 1.0),
       assert(width >= 0.0 && width <= 1.0),
       assert(roundness >= 0.0 && roundness <= 1.0),
       assert(tongueHeightFront >= 0.0 && tongueHeightFront <= 1.0),
       assert(tongueWidth >= 0.0 && tongueWidth <= 1.0),
       assert(tongueProtrusion >= -1.0 && tongueProtrusion <= 1.0),
       assert(tongueVibrateFreqHz >= 0.0),
       assert(tongueVibrateAmp >= 0.0 && tongueVibrateAmp <= 0.15),
       assert(tongueBumpDurationMs >= 0.0);

  /// Interpolación lineal entre dos visemas
  Viseme lerp(Viseme other, double t) {
    assert(t >= 0.0 && t <= 1.0);
    return Viseme(
      openness: openness + (other.openness - openness) * t,
      width: width + (other.width - width) * t,
      roundness: roundness + (other.roundness - roundness) * t,
      name: 'interpolated',
      tongueVisible: tongueVisible || other.tongueVisible,
      tongueHeightFront:
          tongueHeightFront + (other.tongueHeightFront - tongueHeightFront) * t,
      tongueWidth: tongueWidth + (other.tongueWidth - tongueWidth) * t,
      tongueProtrusion:
          tongueProtrusion + (other.tongueProtrusion - tongueProtrusion) * t,
      tongueVibrateEnabled: t > 0.5
          ? other.tongueVibrateEnabled
          : tongueVibrateEnabled,
      tongueVibrateFreqHz: t > 0.5
          ? other.tongueVibrateFreqHz
          : tongueVibrateFreqHz,
      tongueVibrateAmp: t > 0.5 ? other.tongueVibrateAmp : tongueVibrateAmp,
      tongueBumpEnabled: t > 0.5 ? other.tongueBumpEnabled : tongueBumpEnabled,
      tongueBumpDurationMs: t > 0.5
          ? other.tongueBumpDurationMs
          : tongueBumpDurationMs,
    );
  }

  @override
  String toString() {
    final tongueInfo = tongueVisible
        ? "visible(h=$tongueHeightFront${tongueVibrateEnabled ? ',trill=${tongueVibrateFreqHz}Hz' : ''}${tongueBumpEnabled ? ',bump=${tongueBumpDurationMs}ms' : ''})"
        : "hidden";
    return 'Viseme($name: o=$openness, w=$width, r=$roundness, tongue=$tongueInfo)';
  }
}

/// Visemas definidos según especificación TEM
class Visemes {
  static const Viseme neutral = Viseme(
    openness: 0.15,
    width: 0.5,
    roundness: 0.0,
    name: 'Neutral',
  );

  static const Viseme a = Viseme(
    openness: 0.95,
    width: 0.9,
    roundness: 0.0,
    name: 'A',
  );

  static const Viseme e = Viseme(
    openness: 0.55,
    width: 1.0,
    roundness: 0.0,
    name: 'E',
  );

  static const Viseme i = Viseme(
    openness: 0.3,
    width: 1.0,
    roundness: 0.0,
    name: 'I',
  );

  static const Viseme o = Viseme(
    openness: 0.85,
    width: 0.35,
    roundness: 1.0,
    name: 'O',
  );

  static const Viseme u = Viseme(
    openness: 0.45,
    width: 0.2,
    roundness: 1.0,
    name: 'U',
  );

  static const Viseme cerrada = Viseme(
    openness: 0.0,
    width: 0.5,
    roundness: 0.0,
    name: 'Cerrada',
  );

  /// Mapeo completo de fonema a visema según reglas TEM (español)
  static Viseme fromPhoneme(String phoneme) {
    final p = phoneme.toLowerCase();

    if (p == 'a' || p == 'á') return a;
    if (p == 'e' || p == 'é') return e;
    if (p == 'i' || p == 'í' || p == 'y') return i;
    if (p == 'o' || p == 'ó') return o;
    if (p == 'u' || p == 'ú' || p == 'ü') return u;

    if (p == 'm' || p == 'b' || p == 'p') return cerrada;

    if (p == 'f' || p == 'v') {
      return const Viseme(
        openness: 0.25,
        width: 0.55,
        roundness: 0.0,
        name: 'Labiodental-F',
      );
    }

    if (p == 'l') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Alveolar-L',
        tongueVisible: true,
        tongueHeightFront: 0.78,
        tongueWidth: 0.8,
        tongueProtrusion: 0.0,
      );
    }

    if (p == 'n') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Alveolar-N',
        tongueVisible: true,
        tongueHeightFront: 0.55,
        tongueWidth: 0.8,
        tongueProtrusion: 0.0,
      );
    }

    if (p == 'ñ') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Palatal-Ñ',
        tongueVisible: true,
        tongueHeightFront: 0.70,
        tongueWidth: 0.8,
        tongueProtrusion: 0.0,
      );
    }

    if (p == 't' || p == 'd') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Dental-T/D',
        tongueVisible: true,
        tongueHeightFront: 0.62,
        tongueWidth: 0.6,
        tongueProtrusion: 0.0,
        tongueBumpEnabled: true,
        tongueBumpDurationMs: 60.0,
      );
    }

    if (p == 's' || p == 'z') {
      return const Viseme(
        openness: 0.08,
        width: 0.65,
        roundness: 0.0,
        name: 'Fricativa-S',
        tongueVisible: true,
        tongueHeightFront: 0.48,
        tongueWidth: 0.42,
        tongueProtrusion: 0.04,
      );
    }

    if (p == 'r' && p.length == 1) {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Vibrante-Tap-R',
        tongueVisible: true,
        tongueHeightFront: 0.70,
        tongueWidth: 0.7,
        tongueProtrusion: 0.0,
        tongueBumpEnabled: true,
        tongueBumpDurationMs: 110.0,
      );
    }

    if (p == 'rr') {
      return const Viseme(
        openness: 0.15,
        width: 0.5,
        roundness: 0.0,
        name: 'Vibrante-Trill-RR',
        tongueVisible: true,
        tongueHeightFront: 0.75,
        tongueWidth: 0.7,
        tongueProtrusion: 0.0,
        tongueVibrateEnabled: true,
        tongueVibrateFreqHz: 24.0,
        tongueVibrateAmp: 0.03,
      );
    }

    if (p == 'ch' || p == 'll' || p == 'j') {
      return const Viseme(
        openness: 0.20,
        width: 0.5,
        roundness: 0.0,
        name: 'Palatal-CH/LL',
        tongueVisible: true,
        tongueHeightFront: 0.62,
        tongueWidth: 0.7,
        tongueProtrusion: 0.0,
      );
    }

    if (p == 'k' || p == 'g' || p == 'c' || p == 'q' || p == 'x') {
      return neutral;
    }

    if (p == 'w') return u;
    if (p == 'h') return neutral;

    return neutral;
  }
}
