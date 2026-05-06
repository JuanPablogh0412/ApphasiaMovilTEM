import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'tem_page_header.dart';
import '../../viewmodels/tem/tem_session_viewmodel.dart';

/// Pantalla: resumen post-sesión TEM.
///
/// Muestra:
///   - Estímulos completados N/total
///   - Estímulos abandonados (lista)
///   - Score provisional de la sesión
///   - Disclaimer: "Resultado preliminar — requiere validación del terapeuta"
///   - Botón "Volver al inicio"
///
/// Puede recibir el [TemSessionViewModel] activo via ChangeNotifierProvider.value
/// (navegación desde [TemExerciseScreen]) o construirse sin Provider cuando
/// se accede por ruta nominada con [args].
///
/// Sprint 1 — implementación completa.
class TemSessionSummaryScreen extends StatefulWidget {
  /// Constructor sin args — accede al ViewModel via Provider.
  const TemSessionSummaryScreen({super.key}) : args = const {};

  /// Constructor con args — compatible con la ruta `/tem-session-summary`.
  const TemSessionSummaryScreen.withArgs({super.key, required this.args});

  final Map<String, dynamic> args;

  @override
  State<TemSessionSummaryScreen> createState() =>
      _TemSessionSummaryScreenState();
}

class _TemSessionSummaryScreenState extends State<TemSessionSummaryScreen> {
  static const _bgColor = Color(0xFFFFF7F2);
  static const _accentColor = Color(0xFFF48A63);

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final vm = _tryGetViewModel(context);

    final completed =
        vm?.completedStimuli ??
        (widget.args['completed'] as List?)?.cast<String>() ??
        [];
    final abandoned =
        vm?.abandonedStimuli ??
        (widget.args['abandoned'] as List?)?.cast<String>() ??
        [];
    final score = vm?.sessionScore ?? (widget.args['score'] as int?) ?? 0;
    final total = vm?.totalStimuli ?? (widget.args['total'] as int?) ?? 0;
    final maxScore =
        (vm?.maxScorePerStimulus ??
            (widget.args['maxScorePerStimulus'] as int?) ??
            4) *
        total;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            const TemPageHeader(title: 'Resultado', showBack: false),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryHeader(score: score, maxScore: maxScore),
                    const SizedBox(height: 24),
                    _StimuliSummary(
                      completed: completed,
                      abandoned: abandoned,
                      total: total,
                    ),
                    const SizedBox(height: 24),
                    _DisclaimerCard(),
                    const SizedBox(height: 36),
                    _HomeButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/tem-home', (r) => false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TemSessionViewModel? _tryGetViewModel(BuildContext context) {
    try {
      return context.read<TemSessionViewModel>();
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SummaryHeader extends StatelessWidget {
  final int score;
  final int maxScore;
  const _SummaryHeader({required this.score, required this.maxScore});

  @override
  Widget build(BuildContext context) {
    final pct = maxScore > 0 ? (score / maxScore * 100).round() : 0;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF48A63), Color(0xFFFF7043)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF48A63).withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_rounded, size: 72, color: Colors.white),
          const SizedBox(height: 16),
          const Text(
            '¡Sesión finalizada!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          _CircularScore(score: score, maxScore: maxScore),
          const SizedBox(height: 12),
          Text(
            '$score / $maxScore pts',
            style: const TextStyle(fontSize: 22, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _StimuliSummary extends StatelessWidget {
  final List<String> completed;
  final List<String> abandoned;
  final int total;

  const _StimuliSummary({
    required this.completed,
    required this.abandoned,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2D2D),
            ),
          ),
          const Divider(height: 20),
          _StatRow(
            icon: Icons.check_circle_rounded,
            iconColor: Colors.green,
            label: 'Completados',
            value: '${completed.length}/$total',
          ),
          const SizedBox(height: 12),
          _StatRow(
            icon: Icons.cancel_rounded,
            iconColor: Colors.orange,
            label: 'Abandonados',
            value: '${abandoned.length}',
          ),
          if (completed.isNotEmpty || abandoned.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...completed.map(
                  (id) => _StimulusChip(label: id, completed: true),
                ),
                ...abandoned.map(
                  (id) => _StimulusChip(label: id, completed: false),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 28),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 18)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2D2D),
          ),
        ),
      ],
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.2),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFF9A825), size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Resultado preliminar — validación del terapeuta requerida.',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF795548),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _HomeButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ElevatedButton.icon(
        onPressed: () {
          HapticFeedback.mediumImpact();
          onPressed();
        },
        icon: const Icon(Icons.home_rounded, size: 28),
        label: const Text(
          'Volver al inicio',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF48A63),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Circular score indicator
// ---------------------------------------------------------------------------

class _CircularScore extends StatelessWidget {
  final int score;
  final int maxScore;
  const _CircularScore({required this.score, required this.maxScore});

  @override
  Widget build(BuildContext context) {
    final pct = maxScore > 0 ? score / maxScore : 0.0;
    return SizedBox(
      width: 100,
      height: 100,
      child: CustomPaint(
        painter: _CircularScorePainter(pct),
        child: Center(
          child: Text(
            '${(pct * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _CircularScorePainter extends CustomPainter {
  final double fraction;
  _CircularScorePainter(this.fraction);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Colors.white24;
    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularScorePainter old) =>
      old.fraction != fraction;
}

// ---------------------------------------------------------------------------
// Stimulus chip with ✓/✗
// ---------------------------------------------------------------------------

class _StimulusChip extends StatelessWidget {
  final String label;
  final bool completed;
  const _StimulusChip({required this.label, required this.completed});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        completed ? Icons.check_circle : Icons.cancel,
        size: 20,
        color: completed ? Colors.green : Colors.orange,
      ),
      label: Text(label, style: const TextStyle(fontSize: 14)),
      backgroundColor: completed
          ? const Color(0xFFE8F5E9)
          : const Color(0xFFFFF3E0),
      side: BorderSide(
        color: completed ? Colors.green.shade300 : const Color(0xFFFFB74D),
      ),
    );
  }
}
