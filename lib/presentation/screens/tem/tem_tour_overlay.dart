import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/tem/narration_service.dart';

/// Clave de SharedPreferences que indica si el tour ya fue visto.
const _kTourSeen = 'tem_tour_seen';

/// Devuelve true si el tour ya fue mostrado al usuario.
Future<bool> temTourAlreadySeen() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kTourSeen) ?? false;
}

/// Marca el tour como visto.
Future<void> _markTourSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kTourSeen, true);
}

/// Muestra el tour guiado de la pantalla de inicio TEM.
///
/// [practicarKey], [calibrarKey], [progressKey] son las GlobalKeys de los
/// tres botones principales. Si algún widget no está montado, ese paso se omite.
///
/// Devuelve un Future que completa cuando el tour termina (aceptado o repetido).
/// Si el usuario elige "Repetir", el Future completa con `false` para que el
/// llamador pueda volver a mostrar el tour.
Future<void> showTemTour({
  required BuildContext context,
  required NarrationService narration,
  required GlobalKey practicarKey,
  required GlobalKey calibrarKey,
  required GlobalKey progressKey,
}) async {
  final steps = [
    _TourStep(
      key: practicarKey,
      ttsKey: 'home_toca_practicar',
      label: 'Toca aquí para comenzar a practicar',
    ),
    _TourStep(
      key: calibrarKey,
      ttsKey: 'home_calibrar',
      label: 'Aquí puedes calibrar tu voz',
    ),
    _TourStep(
      key: progressKey,
      ttsKey: 'home_progreso',
      label: 'Aquí consultas tu progreso',
    ),
  ];

  bool repeat = true;
  while (repeat) {
    bool skipped = false;

    for (int i = 0; i < steps.length; i++) {
      if (!context.mounted || skipped) break;
      final step = steps[i];
      final rect = _getRectForKey(step.key);
      if (rect == null) continue;

      final completer = Completer<void>();

      final entry = OverlayEntry(
        builder: (_) => _TourStepOverlay(
          rect: rect,
          label: step.label,
          stepIndex: i,
          totalSteps: steps.length,
          onNext: () => completer.complete(),
          onSkip: () {
            skipped = true;
            narration.stop();
            completer.complete();
          },
        ),
      );

      Overlay.of(context).insert(entry);

      // Narrar la descripción del paso
      unawaited(
        narration.speakAndWait(step.ttsKey).then((_) {
          // No auto-avanzar; el usuario toca el botón "Siguiente"
        }),
      );

      await completer.future;
      entry.remove();
    }

    if (skipped) {
      await _markTourSeen();
      return;
    }

    if (!context.mounted) return;
    repeat = await _showEndDialog(context, narration);
    if (!repeat) {
      await _markTourSeen();
    }
  }
}

/// Obtiene el Rect global de un widget identificado por [key].
Rect? _getRectForKey(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final offset = box.localToGlobal(Offset.zero);
  return offset & box.size;
}

/// Diálogo final del tour: "Entendido" o "Repetir".
Future<bool> _showEndDialog(
  BuildContext context,
  NarrationService narration,
) async {
  narration.speak('tutorial_listo');
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 64,
              color: Color(0xFFF48A63),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Ya sabes cómo funciona!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF48A63),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Entendido',
                  style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.replay_rounded, size: 22),
              label: const Text(
                'Repetir el recorrido',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.black45),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

// ─── Modelos internos ────────────────────────────────────────────────────────

class _TourStep {
  final GlobalKey key;
  final String ttsKey;
  final String label;
  const _TourStep({
    required this.key,
    required this.ttsKey,
    required this.label,
  });
}

// ─── Widget de overlay por paso ──────────────────────────────────────────────

class _TourStepOverlay extends StatelessWidget {
  final Rect rect;
  final String label;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourStepOverlay({
    required this.rect,
    required this.label,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  static const _padding = 16.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final spotRect = rect.inflate(_padding);

    // Posición del tooltip: debajo del spotlight si cabe, si no encima.
    final belowY = spotRect.bottom + 16;
    final tooltipTop = belowY + 120 < size.height ? belowY : spotRect.top - 136;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ── Overlay oscuro con spotlight recortado ───────────────────
          ClipPath(
            clipper: _SpotlightClipper(spotRect),
            child: Container(
              width: size.width,
              height: size.height,
              color: Colors.black.withOpacity(0.65),
            ),
          ),

          // ── Borde animado alrededor del spotlight ────────────────────
          Positioned(
            left: spotRect.left,
            top: spotRect.top,
            width: spotRect.width,
            height: spotRect.height,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFF48A63), width: 3),
                borderRadius: BorderRadius.circular(_padding),
              ),
            ),
          ),
          // ── Botón Saltar — esquina superior derecha ─────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              elevation: 4,
              shadowColor: Colors.black38,
              child: InkWell(
                onTap: onSkip,
                borderRadius: BorderRadius.circular(24),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Saltar',
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF48A63),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: Color(0xFFF48A63),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── Tooltip con descripción ──────────────────────────────────
          Positioned(
            left: 24,
            right: 24,
            top: tooltipTop,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Indicador de paso
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      totalSteps,
                      (i) => Container(
                        width: i == stepIndex ? 20 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == stepIndex
                              ? const Color(0xFFF48A63)
                              : const Color(0xFFFFCCBC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D2D2D),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: onNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF48A63),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        stepIndex < totalSteps - 1
                            ? 'Siguiente →'
                            : 'Finalizar',
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Clipper que dibuja un rectángulo oscuro con hueco ─────────────────────

class _SpotlightClipper extends CustomClipper<Path> {
  final Rect spotlight;
  const _SpotlightClipper(this.spotlight);

  @override
  Path getClip(Size size) {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(spotlight, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant _SpotlightClipper old) =>
      spotlight != old.spotlight;
}
