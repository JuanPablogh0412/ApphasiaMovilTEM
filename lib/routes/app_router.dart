import 'package:aphasia_mobile/presentation/screens/personalization/personalize_exercises_screen.dart';
import 'package:aphasia_mobile/presentation/viewmodels/tem/tem_session_viewmodel.dart';
import 'package:aphasia_mobile/services/tem/recording_service.dart';
import 'package:aphasia_mobile/services/tem/session_manager.dart';
import 'package:aphasia_mobile/services/tem/stimulus_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../presentation/screens/register/register_main_screen.dart';
import '../presentation/screens/register/register_personal_screen.dart';
import '../presentation/screens/register/register_family_screen.dart';
import '../presentation/screens/register/register_routine_screen.dart';
import '../presentation/screens/register/register_summary_screen.dart';
import '../presentation/screens/login/login_screen.dart';
import '../presentation/screens/menu/menu_screen.dart';
import '../presentation/screens/landing/landing_screen.dart';
import '../presentation/screens/sr/sr_exersices.dart';
import '../presentation/screens/vnest/vnest_conclusion.dart';
import '../presentation/screens/vnest/vnest_selectcontext.dart';
import '../presentation/screens/vnest/vnest_actionselection.dart';
import '../presentation/screens/vnest/vnest_sentenceevaluation.dart';
import '../presentation/screens/vnest/vnest_sentenceexpansion.dart';
import '../presentation/screens/vnest/vnest_selectverb.dart';
import '../presentation/screens/splash/splash_screen.dart';
import '../presentation/screens/tem/tem_home_screen.dart';
import '../presentation/screens/tem/tem_exercise_screen.dart';
import '../presentation/screens/tem/tem_calibration_screen.dart';
import '../presentation/screens/tem/tem_session_summary_screen.dart';
import '../presentation/screens/tem/tem_history_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/splash':
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      // --- Landing ---
      case '/':
        return MaterialPageRoute(builder: (_) => const LandingScreen());

      // --- Registro ---
      case '/register-main':
        return MaterialPageRoute(builder: (_) => const RegisterMainScreen());

      case '/register-personal':
        return MaterialPageRoute(
          builder: (_) => const RegisterPersonalScreen(),
        );

      case '/register-family':
        return MaterialPageRoute(builder: (_) => const RegisterFamilyScreen());

      case '/register-routine':
        return MaterialPageRoute(builder: (_) => const RegisterRoutineScreen());

      case '/register-main-success':
        return MaterialPageRoute(
          builder: (_) => const RegisterMainScreen(showSuccess: true),
        );
      case '/register-summary':
        return MaterialPageRoute(builder: (_) => const RegisterSummaryScreen());

      // --- Login y Menú ---
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case '/menu':
        return MaterialPageRoute(builder: (_) => const MenuScreen());

      // --- VNEST Fase 0: Selección de contexto ---
      case '/vnest':
        return MaterialPageRoute(
          builder: (_) => const VnestSelectContextScreen(),
        );

      // --- VNEST Fase 1: Selección de verbo ---
      case '/vnest-verb':
        {
          final args = settings.arguments as Map<String, dynamic>?;
          if (args == null ||
              args['context'] == null ||
              args['context'] is! String) {
            return _errorRoute(
              "Faltan los datos del contexto (args['context']).",
            );
          }
          return MaterialPageRoute(
            builder: (_) => VnestSelectVerbScreen(
              vnestContext: args['context'] as String, // <-- nombre correcto
            ),
          );
        }

      // --- VNEST Fase 1: Selección de acción (¿quién? y ¿qué?) ---
      case '/vnest-action':
        final args = settings.arguments as Map<String, dynamic>?;
        if (args == null) {
          return _errorRoute("FaltaRn los datos del ejercicio (args nulos)");
        }
        return MaterialPageRoute(
          builder: (_) => VnestActionSelectionScreen(exercise: args),
        );

      // --- VNEST Fase 2: Expansión de Oración (3 pantallas) ---
      case '/vnest-phase2':
        final args = Map<String, dynamic>.from(settings.arguments as Map);
        return MaterialPageRoute(builder: (_) => VnestWhereScreen(data: args));

      case '/vnest-why':
        final args = Map<String, dynamic>.from(settings.arguments as Map);
        return MaterialPageRoute(builder: (_) => VnestWhyScreen(data: args));

      case '/vnest-when':
        final args = Map<String, dynamic>.from(settings.arguments as Map);
        return MaterialPageRoute(builder: (_) => VnestWhenScreen(data: args));

      case '/vnest-phase3':
        final args = Map<String, dynamic>.from(settings.arguments as Map);
        return MaterialPageRoute(
          builder: (_) => VnestSentenceEvaluationScreen(exercise: args),
        );

      case '/vnest-phase4':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => VnestConclusionScreen(exercise: args),
        );

      case '/sr':
        return MaterialPageRoute(builder: (_) => const SRExercisesScreen());

      // --- TEM: Terapia de Entonación Melódica ---
      case '/tem-home':
        {
          final repo = StimulusRepository();
          return MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => TemSessionViewModel(
                repository: repo,
                sessionManager: SessionManager(repository: repo),
                recordingService: RecordingService(),
              ),
              child: const TemHomeScreen(),
            ),
          );
        }

      case '/tem-exercise':
        {
          final args = (settings.arguments as Map<String, dynamic>?) ?? {};
          return MaterialPageRoute(
            builder: (_) => TemExerciseScreen.withArgs(args: args),
          );
        }

      case '/tem-calibration':
        return MaterialPageRoute(builder: (_) => const TemCalibrationScreen());

      case '/tem-session-summary':
        {
          final args = (settings.arguments as Map<String, dynamic>?) ?? {};
          return MaterialPageRoute(
            builder: (_) => TemSessionSummaryScreen.withArgs(args: args),
          );
        }

      case '/tem-history':
        return MaterialPageRoute(builder: (_) => const TemHistoryScreen());

      case '/personalize-exercises':
        return MaterialPageRoute(
          builder: (_) => const PersonalizeExercisesScreen(),
        );

      // --- Fallback (ruta no encontrada) ---
      default:
        return _errorRoute('Página no encontrada: ${settings.name}');
    }
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.redAccent,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
