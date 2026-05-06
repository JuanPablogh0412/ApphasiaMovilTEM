import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../services/tem/narration_service.dart';
import '../../widgets/mute_button.dart';
import '../../viewmodels/tem/tem_session_viewmodel.dart';
import 'speaking_indicator.dart';
import 'tem_exercise_screen.dart';

/// Pantalla pre-sesión: muestra info del nivel, número de ejercicios,
/// botón tutorial y botón EMPEZAR con diseño accesible.
///
/// Se ubica entre TemHomeScreen y TemExerciseScreen.
class TemPreSessionScreen extends StatefulWidget {
  final NarrationService narration;
  const TemPreSessionScreen({super.key, required this.narration});

  @override
  State<TemPreSessionScreen> createState() => _TemPreSessionScreenState();
}

class _TemPreSessionScreenState extends State<TemPreSessionScreen> {
  static const _accentColor = Color(0xFFF48A63);
  static const _bgColor = Color(0xFFFFF7F2);

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.narration.speak('pre_session_info');
    });
  }

  Future<void> _startSession() async {
    if (_loading) return;
    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    final vm = context.read<TemSessionViewModel>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await vm.startSession(uid);
    if (!mounted) return;

    if (vm.errorMessage != null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(vm.errorMessage!),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await widget.narration.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: TemExerciseScreen(narration: widget.narration),
        ),
      ),
    );
  }

  void _showTutorial() {
    widget.narration.speak('tutorial_paso1');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final nivel = context.read<TemSessionViewModel>().nivelActual;
        return _TutorialSheet(narration: widget.narration, nivel: nivel);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TemSessionViewModel>();
    final nivel = vm.nivelActual;
    final totalPasos = nivel >= 2 ? 4 : 5;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // -- Indicador de voz + mute ---------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SpeakingIndicatorBadge(narration: widget.narration),
                  const SizedBox(width: 8),
                  MuteButton(narration: widget.narration),
                ],
              ),
              const SizedBox(height: 16),

              // -- Ícono de nivel ------------------------------------------
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  size: 52,
                  color: _accentColor,
                ),
              ),
              const SizedBox(height: 24),

              // -- Nivel ---------------------------------------------------
              Text(
                'Nivel $nivel',
                style: const TextStyle(
                  fontSize: 32,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                  color: _accentColor,
                ),
              ),
              const SizedBox(height: 16),

              // -- Info cards ----------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _InfoChip(
                    icon: Icons.format_list_numbered_rounded,
                    label: '$totalPasos pasos',
                  ),
                  const SizedBox(width: 16),
                  const _InfoChip(icon: Icons.timer_rounded, label: '~10 min'),
                ],
              ),
              const SizedBox(height: 32),

              // -- Botón Tutorial ------------------------------------------
              OutlinedButton.icon(
                onPressed: _showTutorial,
                icon: const Icon(Icons.help_outline_rounded, size: 28),
                label: const Text(
                  '¿Cómo funciona?',
                  style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accentColor,
                  side: const BorderSide(color: _accentColor, width: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // -- Botón EMPEZAR -------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 72,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _startSession,
                  icon: _loading
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(Icons.arrow_forward_rounded, size: 36),
                  label: Text(
                    _loading ? 'Cargando...' : 'EMPEZAR',
                    style: const TextStyle(
                      fontSize: 24,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    elevation: 6,
                    shadowColor: _accentColor.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // -- Volver --------------------------------------------------
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                label: const Text(
                  'Volver',
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
  }
}

// ---------------------------------------------------------------------------
// Info chip (pasos / duración)
// ---------------------------------------------------------------------------

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: const Color(0xFFF48A63)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D2D2D),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tutorial bottom sheet (carousel con narración)
// ---------------------------------------------------------------------------

class _TutorialSheet extends StatefulWidget {
  final NarrationService narration;
  final int nivel;
  const _TutorialSheet({required this.narration, required this.nivel});

  @override
  State<_TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<_TutorialSheet> {
  static const _accentColor = Color(0xFFF48A63);

  final _controller = PageController();
  int _page = 0;

  static const _stepsN1 = [
    _TutorialStep(
      icon: Icons.headphones_rounded,
      title: 'Escucha',
      body: 'Escucha la frase con melodía.',
      narrationKey: 'tutorial_paso1',
    ),
    _TutorialStep(
      icon: Icons.music_note_rounded,
      title: 'Canta junto',
      body: 'Canta imitando la melodía.',
      narrationKey: 'tutorial_paso2',
    ),
    _TutorialStep(
      icon: Icons.mic_rounded,
      title: 'Completa',
      body: 'El audio se silencia y tú completas.',
      narrationKey: 'tutorial_paso3',
    ),
    _TutorialStep(
      icon: Icons.replay_rounded,
      title: 'Repite',
      body: 'Escucha una vez y repite tú solo.',
      narrationKey: 'tutorial_paso4',
    ),
    _TutorialStep(
      icon: Icons.chat_bubble_rounded,
      title: 'Responde',
      body: 'Responde una pregunta al final.',
      narrationKey: 'tutorial_paso5',
    ),
  ];

  static const _stepsN2 = [
    _TutorialStep(
      icon: Icons.headphones_rounded,
      title: 'Escucha',
      body: 'Escucha el estímulo con atención.',
      narrationKey: 'tutorial_n2_paso1',
    ),
    _TutorialStep(
      icon: Icons.music_note_rounded,
      title: 'Canta y completa',
      body: 'Canta junto al audio y completa la segunda mitad.',
      narrationKey: 'tutorial_n2_paso2',
    ),
    _TutorialStep(
      icon: Icons.mic_rounded,
      title: 'Repite solo',
      body: 'Después del silencio, repite el estímulo solo.',
      narrationKey: 'tutorial_n2_paso3',
    ),
    _TutorialStep(
      icon: Icons.chat_bubble_rounded,
      title: 'Responde',
      body: 'Responde la pregunta al final.',
      narrationKey: 'tutorial_n2_paso4',
    ),
  ];

  List<_TutorialStep> get _steps => widget.nivel >= 2 ? _stepsN2 : _stepsN1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            '¿Cómo funciona?',
            style: TextStyle(
              fontSize: 22,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D2D2D),
            ),
          ),
          const SizedBox(height: 16),

          // PageView
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _steps.length,
              onPageChanged: (i) {
                setState(() => _page = i);
                widget.narration.speak(_steps[i].narrationKey);
              },
              itemBuilder: (_, i) => _buildPage(_steps[i], i),
            ),
          ),

          // Dots
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _steps.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _page ? 28 : 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: i == _page ? _accentColor : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),

          // Botones
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                if (_page > 0)
                  IconButton(
                    onPressed: () => _goToPage(_page - 1),
                    icon: const Icon(Icons.arrow_back_rounded, size: 32),
                    color: Colors.black45,
                  )
                else
                  const SizedBox(width: 48),
                const Spacer(),
                if (_page < _steps.length - 1)
                  ElevatedButton.icon(
                    onPressed: () => _goToPage(_page + 1),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text(
                      'Siguiente',
                      style: TextStyle(fontFamily: 'Manrope'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () {
                      widget.narration.speak('tutorial_listo');
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      '¡Entendido!',
                      style: TextStyle(fontFamily: 'Manrope'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF81C784),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_TutorialStep step, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 48, color: _accentColor),
          ),
          const SizedBox(height: 20),
          Text(
            'Paso ${index + 1}: ${step.title}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D2D2D),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w400,
              color: Color(0xFF555555),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialStep {
  final IconData icon;
  final String title;
  final String body;
  final String narrationKey;

  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.narrationKey,
  });
}
