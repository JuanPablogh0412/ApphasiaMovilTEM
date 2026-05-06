import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/tem/stimulus_repository.dart';
import 'tem_page_header.dart';

/// Pantalla: progreso clínico del paciente en el protocolo TEM.
/// Muestra una línea de tiempo de 3 niveles con el estado de cada uno.
class TemHistoryScreen extends StatefulWidget {
  const TemHistoryScreen({super.key});

  @override
  State<TemHistoryScreen> createState() => _TemHistoryScreenState();
}

class _TemHistoryScreenState extends State<TemHistoryScreen> {
  final _repository = StimulusRepository();
  late Future<({int nivel, int consecutive})> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<({int nivel, int consecutive})> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final nivel = await _repository.getNivelActual(uid);
    final consecutive = await _repository.countConsecutiveHighSessions(
      uid,
      nivel: nivel,
    );
    return (nivel: nivel, consecutive: consecutive);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F2),
      body: SafeArea(
        child: Column(
          children: [
            const TemPageHeader(title: 'Mi Progreso'),
            Expanded(
              child: FutureBuilder<({int nivel, int consecutive})>(
                future: _dataFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFF48A63),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    debugPrint('TemHistory error: ${snap.error}');
                  }
                  final int nivel = snap.data?.nivel ?? 1;
                  final int consecutive = snap.data?.consecutive ?? 0;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Column(
                      children: [
                        _LevelCard(
                          level: 1,
                          title: 'Nivel 1 — Melodía con apoyo',
                          nivelActual: nivel,
                          consecutive: consecutive,
                        ),
                        _TimelineConnector(active: nivel >= 2),
                        _LevelCard(
                          level: 2,
                          title: 'Nivel 2 — Desvanecimiento',
                          nivelActual: nivel,
                          consecutive: consecutive,
                        ),
                        _TimelineConnector(active: nivel >= 3),
                        _LevelCard(
                          level: 3,
                          title: 'Nivel 3 — Habla espontánea',
                          nivelActual: nivel,
                          consecutive: consecutive,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conector vertical entre tarjetas
// ---------------------------------------------------------------------------

class _TimelineConnector extends StatelessWidget {
  const _TimelineConnector({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 32,
      color: active ? const Color(0xFFF48A63) : const Color(0xFFDDDDDD),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de nivel
// ---------------------------------------------------------------------------

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.title,
    required this.nivelActual,
    required this.consecutive,
  });

  final int level;
  final String title;
  final int nivelActual;
  final int consecutive;

  static const int _requiredSessions = 5;
  static const double _threshold = 90.0;

  _CardState get _state {
    if (nivelActual > level) return _CardState.completed;
    if (nivelActual == level) return _CardState.active;
    return _CardState.locked;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;

    Color bgColor;
    Color borderColor;
    Widget statusIcon;

    switch (state) {
      case _CardState.completed:
        bgColor = const Color(0xFFE8F5E9);
        borderColor = const Color(0xFF81C784);
        statusIcon = const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF388E3C),
          size: 28,
        );
      case _CardState.active:
        bgColor = const Color(0xFFFFF3EE);
        borderColor = const Color(0xFFF48A63);
        statusIcon = const Icon(
          Icons.radio_button_checked_rounded,
          color: Color(0xFFF48A63),
          size: 28,
        );
      case _CardState.locked:
        bgColor = const Color(0xFFF5F5F5);
        borderColor = const Color(0xFFBDBDBD);
        statusIcon = const Icon(
          Icons.lock_rounded,
          color: Color(0xFF9E9E9E),
          size: 28,
        );
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              statusIcon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
            ],
          ),
          if (state == _CardState.active) ...[
            const SizedBox(height: 16),
            _SessionDots(count: consecutive, total: _requiredSessions),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: consecutive / _requiredSessions,
                minHeight: 10,
                backgroundColor: const Color(0xFFFFCCB3),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFF48A63),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$consecutive de $_requiredSessions sesiones al ${_threshold.toInt()}% para pasar al Nivel ${level + 1}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
          ],
          if (state == _CardState.completed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '¡Nivel completado!',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF388E3C),
                ),
              ),
            ),
          if (state == _CardState.locked)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Completa el nivel anterior para desbloquear',
                style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Indicador de puntos (sesiones consecutivas)
// ---------------------------------------------------------------------------

class _SessionDots extends StatelessWidget {
  const _SessionDots({required this.count, required this.total});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final filled = i < count;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? const Color(0xFFF48A63) : const Color(0xFFFFCCB3),
              border: Border.all(color: const Color(0xFFF48A63), width: 2),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado interno de la tarjeta
// ---------------------------------------------------------------------------

enum _CardState { completed, active, locked }
