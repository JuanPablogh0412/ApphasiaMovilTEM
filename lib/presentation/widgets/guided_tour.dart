import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/tem/narration_service.dart';

/// Modelo de un paso del recorrido guiado.
///
/// [key] apunta al widget a iluminar.
/// [label] es el texto descriptivo que aparece en el tooltip.
/// [ttsKey] (opcional) es la clave de Firebase Storage para reproducir audio.
class GuidedTourStep {
  final GlobalKey key;
  final String label;
  final String? ttsKey;

  const GuidedTourStep({required this.key, required this.label, this.ttsKey});
}

/// Muestra un recorrido guiado secuencial sobre los widgets indicados.
///
/// Oscurece la pantalla y resalta cada widget en orden con un borde naranja
/// y un tooltip con descripción. Si se proporciona [narration] y el paso
/// tiene [ttsKey], reproduce el audio correspondiente.
///
/// Retorna cuando el usuario ha completado todos los pasos.
Future<void> showGuidedTour({
  required BuildContext context,
  required List<GuidedTourStep> steps,
  NarrationService? narration,
}) async {
  bool skipped = false;

  for (int i = 0; i < steps.length; i++) {
    if (!context.mounted || skipped) return;
    final step = steps[i];

    // Desplazar la pantalla para que el widget esté visible antes del spotlight.
    final stepCtx = step.key.currentContext;
    if (stepCtx != null) {
      await Scrollable.ensureVisible(
        stepCtx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
      // Esperar a que el layout se estabilice tras el scroll.
      await Future.delayed(const Duration(milliseconds: 80));
    }

    if (!context.mounted || skipped) return;
    final rect = _getRectForKey(step.key);
    if (rect == null) continue;

    final completer = Completer<void>();
    final entry = OverlayEntry(
      builder: (_) => _GuidedStep(
        rect: rect,
        label: step.label,
        stepIndex: i,
        totalSteps: steps.length,
        onNext: completer.complete,
        onSkip: () {
          skipped = true;
          narration?.stop();
          completer.complete();
        },
      ),
    );

    Overlay.of(context).insert(entry);

    if (step.ttsKey != null) {
      unawaited(narration?.speakAndWait(step.ttsKey!));
    }

    await completer.future;
    entry.remove();
    if (skipped) return;
  }
}

/// Calcula el Rect global de un widget identificado por [key].
/// Retorna null si el widget no está montado o no tiene tamaño.
Rect? _getRectForKey(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final offset = box.localToGlobal(Offset.zero);
  return offset & box.size;
}

// ─── Widget de overlay por paso ─────────────────────────────────────────────

class _GuidedStep extends StatelessWidget {
  final Rect rect;
  final String label;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _GuidedStep({
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

    // Posición del tooltip: debajo si cabe, si no encima.
    final belowY = spotRect.bottom + 16;
    final tooltipTop = belowY + 156 < size.height ? belowY : spotRect.top - 172;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ── Overlay oscuro con hueco transparente sobre el target ────
          ClipPath(
            clipper: _SpotlightClipper(spotRect),
            child: Container(
              width: size.width,
              height: size.height,
              color: Colors.black.withOpacity(0.65),
            ),
          ),

          // ── Borde naranja alrededor del elemento iluminado ───────────
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

          // ── Tooltip con descripción y botón avanzar ──────────────────
          Positioned(
            left: 24,
            right: 24,
            top: tooltipTop.clamp(8.0, size.height - 200),
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
                  // Indicador de pasos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      totalSteps,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
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
                      fontSize: 17,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D2D2D),
                      height: 1.4,
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
                            : 'Entendido ✓',
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

// ─── Clipper: pantalla completa con hueco redondeado ────────────────────────

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
