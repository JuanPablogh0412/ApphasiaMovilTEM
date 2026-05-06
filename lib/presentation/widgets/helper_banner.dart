import 'package:flutter/material.dart';

/// Banner informativo que invita al paciente a pedir ayuda a un familiar
/// durante el proceso de registro.
///
/// Se muestra en todas las pantallas del flujo de registro.
/// Opcionalmente se puede cerrar con [onDismiss].
class HelperBanner extends StatelessWidget {
  /// Callback para cerrar el banner. Si es null no se muestra la X.
  final VoidCallback? onDismiss;

  const HelperBanner({super.key, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE9E7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF48A63).withOpacity(0.35),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👥', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '¿Tienes un familiar o ayudante cerca?\n'
              '¡Pídele que te acompañe en este registro!',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Manrope',
                color: Colors.brown.shade700,
                height: 1.45,
              ),
            ),
          ),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.brown.shade400,
              ),
            ),
        ],
      ),
    );
  }
}
