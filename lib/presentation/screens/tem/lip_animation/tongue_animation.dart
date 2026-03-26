library;

import 'dart:math' as math;

/// Utilidades para micro-animaciones procedurales de lengua
///
/// CHANGES: Nuevo archivo para motor de animación de lengua (v2.1 - Feb 2026)
///
/// Propósito: Implementar bumps (taps/oclusivas) y trills (vibrantes múltiples)
/// sin dependencias externas mediante funciones matemáticas puras.

// ==================== FUNCIONES DE EASING ====================

/// Easing suave in-out (curva S) para transiciones naturales
///
/// Implementa smoothstep: f(t) = 3t² - 2t³
/// [t] debe estar en [0.0 - 1.0]
double easeInOutSmooth(double t) {
  assert(t >= 0.0 && t <= 1.0, 'easeInOutSmooth: t must be in [0.0, 1.0]');
  return t * t * (3.0 - 2.0 * t);
}

/// Easing in-out cúbico (más pronunciado)
///
/// [t] debe estar en [0.0 - 1.0]
double easeInOutCubic(double t) {
  assert(t >= 0.0 && t <= 1.0, 'easeInOutCubic: t must be in [0.0, 1.0]');
  return t < 0.5
      ? 4.0 * t * t * t
      : 1.0 - math.pow(-2.0 * t + 2.0, 3.0) / 2.0;
}

/// Easing out (deceleración al final)
///
/// [t] debe estar en [0.0 - 1.0]
double easeOut(double t) {
  assert(t >= 0.0 && t <= 1.0, 'easeOut: t must be in [0.0, 1.0]');
  return 1.0 - (1.0 - t) * (1.0 - t);
}

// ==================== BUMP (TAP/OCLUSIVA) ====================

/// Calcula el offset de bump (elevación temporal) en un momento dado
///
/// CHANGES: Implementa bump simétrico con ataque + release eased
///
/// El bump tiene 3 fases:
/// - Attack (0% - 40%): Elevación rápida con easeIn
/// - Hold (40% - 60%): Mantiene altura máxima
/// - Release (60% - 100%): Descenso suave con easeOut
///
/// [elapsedMs] Tiempo transcurrido desde inicio del bump (en ms)
/// [durationMs] Duración total del bump (típico: 60-120ms)
/// [amplitude] Amplitud máxima del bump [0.0 - 0.15] (típico: 0.08-0.12)
///
/// Retorna offset de altura normalizado [0.0 - amplitude]
double calculateTongueBump({
  required double elapsedMs,
  required double durationMs,
  required double amplitude,
}) {
  assert(durationMs > 0.0, 'durationMs must be positive');
  assert(amplitude >= 0.0 && amplitude <= 0.15, 'amplitude must be in [0.0, 0.15]');

  if (elapsedMs < 0.0 || elapsedMs > durationMs) {
    return 0.0; // Fuera del rango del bump
  }

  final t = elapsedMs / durationMs; // Normalizar a [0.0 - 1.0]

  // Fase 1: Attack (0% - 40%)
  if (t < 0.4) {
    final attackT = t / 0.4; // Normalizar a [0.0 - 1.0] dentro de la fase
    return amplitude * easeInOutSmooth(attackT);
  }
  
  // Fase 2: Hold (40% - 60%)
  else if (t < 0.6) {
    return amplitude; // Altura máxima sostenida
  }
  
  // Fase 3: Release (60% - 100%)
  else {
    final releaseT = (t - 0.6) / 0.4; // Normalizar a [0.0 - 1.0]
    return amplitude * (1.0 - easeInOutSmooth(releaseT));
  }
}

// ==================== TRILL (VIBRANTE MÚLTIPLE) ====================

/// Calcula el offset de trill (oscilación sinusoidal) en un momento dado
///
/// CHANGES: Implementa vibración visual mediante modulación sinusoidal
///
/// El trill modula la altura de la lengua con una onda sinusoidal:
/// offset(t) = sin(2π f t + φ) * amplitude
///
/// donde:
/// - f = frecuencia en Hz (típico: 20-30 Hz para /r/ español)
/// - φ = fase inicial (aleatorizada por evento para naturalidad)
/// - amplitude = amplitud normalizada (típico: 0.02-0.04)
///
/// [elapsedMs] Tiempo transcurrido desde inicio del trill (en ms)
/// [frequencyHz] Frecuencia de vibración en Hz (típico: 24 Hz)
/// [amplitude] Amplitud máxima de oscilación [0.0 - 0.1] (típico: 0.03)
/// [phaseOffset] Offset de fase en radianes [0.0 - 2π] (para variación entre eventos)
///
/// Retorna offset de altura normalizado [-amplitude, +amplitude]
double calculateTongueTrill({
  required double elapsedMs,
  required double frequencyHz,
  required double amplitude,
  double phaseOffset = 0.0,
}) {
  assert(frequencyHz > 0.0, 'frequencyHz must be positive');
  assert(amplitude >= 0.0 && amplitude <= 0.1, 'amplitude must be in [0.0, 0.1]');

  // Convertir tiempo a segundos
  final elapsedSec = elapsedMs / 1000.0;

  // Calcular ángulo: θ = 2π f t + φ
  final angle = 2.0 * math.pi * frequencyHz * elapsedSec + phaseOffset;

  // Retornar modulación sinusoidal
  return math.sin(angle) * amplitude;
}

/// Genera un offset de fase aleatorio para trills
///
/// CHANGES: Introduce variación natural entre eventos de trill
///
/// Retorna un valor en radianes [0.0 - 2π]
double randomTrillPhase() {
  return math.Random().nextDouble() * 2.0 * math.pi;
}

// ==================== COMPOSITOR DE ANIMACIONES ====================

/// Calcula la altura total de la lengua combinando base + bump + trill
///
/// CHANGES: Función compositora que integra todas las micro-animaciones
///
/// Combina:
/// 1. Altura base del visema (tongueHeightFront)
/// 2. Bump (si está activo en este frame)
/// 3. Trill (si está activo)
///
/// [baseHeight] Altura base del visema [0.0 - 1.0]
/// [bumpActive] Si hay bump activo
/// [bumpElapsedMs] Tiempo transcurrido en el bump (si aplica)
/// [bumpDurationMs] Duración del bump (si aplica)
/// [bumpAmplitude] Amplitud del bump (típico: 0.08)
/// [trillActive] Si hay trill activo
/// [trillElapsedMs] Tiempo transcurrido en el trill (si aplica)
/// [trillFreqHz] Frecuencia del trill (si aplica)
/// [trillAmplitude] Amplitud del trill (si aplica)
/// [trillPhase] Fase del trill (si aplica)
///
/// Retorna altura final clampeada a [0.0 - 1.0]
double calculateAnimatedTongueHeight({
  required double baseHeight,
  bool bumpActive = false,
  double bumpElapsedMs = 0.0,
  double bumpDurationMs = 0.0,
  double bumpAmplitude = 0.0,
  bool trillActive = false,
  double trillElapsedMs = 0.0,
  double trillFreqHz = 0.0,
  double trillAmplitude = 0.0,
  double trillPhase = 0.0,
}) {
  double height = baseHeight;

  // Aplicar bump (additive)
  if (bumpActive && bumpDurationMs > 0.0) {
    final bumpOffset = calculateTongueBump(
      elapsedMs: bumpElapsedMs,
      durationMs: bumpDurationMs,
      amplitude: bumpAmplitude,
    );
    height += bumpOffset;
  }

  // Aplicar trill (additive)
  if (trillActive && trillFreqHz > 0.0) {
    final trillOffset = calculateTongueTrill(
      elapsedMs: trillElapsedMs,
      frequencyHz: trillFreqHz,
      amplitude: trillAmplitude,
      phaseOffset: trillPhase,
    );
    height += trillOffset;
  }

  // Clampear a rango válido
  return height.clamp(0.0, 1.0);
}
