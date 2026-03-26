import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
class TemSessionSummaryScreen extends StatelessWidget {
  /// Constructor sin args — accede al ViewModel via Provider.
  const TemSessionSummaryScreen({super.key}) : args = const {};

  /// Constructor con args — compatible con la ruta `/tem-session-summary`.
  const TemSessionSummaryScreen.withArgs({super.key, required this.args});

  final Map<String, dynamic> args;

  static const _bgColor = Color(0xFFFFF7F2);
  static const _accentColor = Color(0xFFF48A63);

  @override
  Widget build(BuildContext context) {
    // Intentar obtener el ViewModel del árbol de widgets
    final vm = _tryGetViewModel(context);

    final completed =
        vm?.completedStimuli ??
        (args['completed'] as List?)?.cast<String>() ??
        [];
    final abandoned =
        vm?.abandonedStimuli ??
        (args['abandoned'] as List?)?.cast<String>() ??
        [];
    final score = vm?.sessionScore ?? (args['score'] as int?) ?? 0;
    final total = vm?.totalStimuli ?? (args['total'] as int?) ?? 0;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text('Resultado de la sesión'),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryHeader(score: score, total: total),
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
  final int total;
  const _SummaryHeader({required this.score, required this.total});

  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.emoji_events_rounded, size: 48, color: Colors.white),
          const SizedBox(height: 12),
          const Text(
            '¡Sesión finalizada!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Score provisional: $score pts',
            style: const TextStyle(fontSize: 18, color: Colors.white70),
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
            'Resumen de estímulos',
            style: TextStyle(
              fontSize: 16,
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
          const SizedBox(height: 8),
          _StatRow(
            icon: Icons.cancel_rounded,
            iconColor: Colors.orange,
            label: 'Abandonados',
            value: '${abandoned.length}',
          ),
          if (abandoned.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Estímulos abandonados:',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: abandoned
                  .map(
                    (id) => Chip(
                      label: Text(id, style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFFFFF3E0),
                      side: const BorderSide(color: Color(0xFFFFB74D)),
                    ),
                  )
                  .toList(),
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
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 15)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
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
          Icon(Icons.info_outline_rounded, color: Color(0xFFF9A825), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Resultado preliminar — requiere validación del terapeuta '
              'antes de avanzar de nivel.',
              style: TextStyle(
                fontSize: 14,
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
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.home_rounded),
      label: const Text(
        'Volver al inicio',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFF48A63),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
      ),
    );
  }
}
