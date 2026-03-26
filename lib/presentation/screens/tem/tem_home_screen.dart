import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/tem/tem_session_viewmodel.dart';
import '../register/register_viewmodel.dart';
import 'tem_calibration_screen.dart';
import 'tem_exercise_screen.dart';

/// Pantalla de inicio de la Terapia de Entonación Melódica.
///
/// Diseño basado en el mockup Figma:
///   - Logo cerebro + título TEM
///   - Saludo personalizado con nombre del paciente
///   - Tarjeta "Ejercicios TEM" → inicia sesión
///   - Tarjeta "Consultar progreso" → historial
class TemHomeScreen extends StatefulWidget {
  const TemHomeScreen({super.key});

  @override
  State<TemHomeScreen> createState() => _TemHomeScreenState();
}

class _TemHomeScreenState extends State<TemHomeScreen> {
  static const _accentColor = Color(0xFFF48A63);

  /// true si el paciente tiene calibración guardada en Firestore.
  bool _isCalibrated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!mounted) return;

    // Verificar calibración en paralelo con la carga del home.
    final calFuture = FirebaseFirestore.instance
        .collection('pacientes')
        .doc(uid)
        .get()
        .then((snap) {
          final cal = snap.data()?['calibracion'];
          return cal is Map && cal['last_calibrated_at'] != null;
        })
        .catchError((_) => false);

    await context.read<TemSessionViewModel>().loadHomeData(uid);
    final calibrated = await calFuture;
    if (mounted) setState(() => _isCalibrated = calibrated);
  }

  Future<void> _onStartSession(TemSessionViewModel vm) async {
    // Bloquear si no está calibrado
    if (!_isCalibrated) {
      _showCalibrationRequired();
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await vm.startSession(uid);
    if (!mounted) return;
    if (vm.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(vm.errorMessage!),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: const TemExerciseScreen(),
        ),
      ),
    );
  }

  void _showCalibrationRequired() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 36,
                  color: _accentColor,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Calibración necesaria',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Para obtener una evaluación precisa de tus ejercicios, '
                'primero necesitamos calibrar el sistema a tu voz. '
                'Solo toma unos segundos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w400,
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TemCalibrationScreen(),
                      ),
                    ).then((_) => _loadData()); // refrescar estado al volver
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Ir a calibración',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Ahora no',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TemSessionViewModel>(
      builder: (context, vm, _) {
        // Solo primer nombre del paciente
        final rawNombre = context.watch<RegisterViewModel>().nombre;
        final nombre = rawNombre.isNotEmpty
            ? rawNombre.split(' ').first
            : 'Paciente';

        return Scaffold(
          backgroundColor: const Color(0xFFFFF7F2),
          // Sin AppBar — diseño Figma no tiene barra superior
          body: SafeArea(
            child: vm.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _accentColor),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 31,
                      vertical: 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // -- Logo cerebro -----------------------------------
                        Image.asset(
                          'assets/icons/brain_logo.png',
                          width: 91,
                          height: 91,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 12),

                        // -- Título -----------------------------------------
                        const Text(
                          'Terapia De entonación Melodica',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _accentColor,
                            fontSize: 20,
                            fontFamily: 'Manrope',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // -- Saludo -----------------------------------------
                        Text(
                          'Hola $nombre',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontFamily: 'Manrope',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Hoy es un buen día para progresar en tu terapia',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.45),
                            fontSize: 13,
                            fontFamily: 'Manrope',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // -- Tarjeta: Ejercicios TEM ------------------------
                        _HomeCard(
                          title: 'Ejercicios TEM',
                          description: TextSpan(
                            children: [
                              const TextSpan(
                                text:
                                    'Continúa progresando en tus ejercicios de entonación melódica.  ',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontFamily: 'Manrope',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              TextSpan(
                                text: 'Nivel actual: ${vm.nivelActual}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontFamily: 'Manrope',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          buttonLabel: 'Comenzar',
                          onPressed: vm.isLoading
                              ? null
                              : () => _onStartSession(vm),
                        ),
                        const SizedBox(height: 20),

                        // -- Tarjeta: Calibración de voz ──────────────────
                        _HomeCard(
                          title: 'Calibración de voz',
                          description: const TextSpan(
                            text:
                                'Ajusta el análisis a tu forma de hablar. '
                                'Graba 5 segundos antes de tus ejercicios.',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontFamily: 'Manrope',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          buttonLabel: 'Calibrar',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TemCalibrationScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // -- Tarjeta: Consultar progreso -------------------
                        _HomeCard(
                          title: 'Consultar progreso',
                          description: const TextSpan(
                            text:
                                'Consulta tus resultados en sesiones anteriores y tu progreso en la terapia.',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontFamily: 'Manrope',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          buttonLabel: 'Consultar',
                          onPressed: () =>
                              Navigator.pushNamed(context, '/tem-history'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widget reutilizable: tarjeta con título, descripción y botón
// ---------------------------------------------------------------------------

class _HomeCard extends StatelessWidget {
  final String title;
  final InlineSpan description;
  final String buttonLabel;
  final VoidCallback? onPressed;

  const _HomeCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Título
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF48A63),
              fontSize: 13,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),

          // Descripción (admite texto mixto vía RichText)
          Text.rich(description, textAlign: TextAlign.center),
          const SizedBox(height: 18),

          // Botón de acción
          SizedBox(
            width: 117,
            height: 39,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF48A63),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
