import 'package:flutter/material.dart';

/// Pantalla: historial de ejercicios TEM completados por el paciente.
/// Muestra fecha, estímulo, score global y estado (analyzed/validated).
/// Sprint 3 — implementación completa.
/// Sprint 0 — stub compilable.
class TemHistoryScreen extends StatelessWidget {
  const TemHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F2),
      appBar: AppBar(
        title: const Text('Historial TEM'),
        backgroundColor: const Color(0xFFF48A63),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'Historial de ejercicios\n(Sprint 3)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.black54),
        ),
      ),
    );
  }
}
