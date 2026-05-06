import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/tem/narration_service.dart';
import '../../../services/register/register_tts_keys.dart';
import '../../widgets/helper_banner.dart';
import '../../widgets/mute_button.dart';

const _kLandingWelcomed = 'landing_welcomed';
const _bgColor = Color(0xFFFFF7F2);
const _accentColor = Color(0xFFF48A63);

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final NarrationService _narration = NarrationService();
  bool _bannerVisible = true;

  @override
  void initState() {
    super.initState();
    _narration.init().then((_) => _autoPlayWelcome());
  }

  Future<void> _autoPlayWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_kLandingWelcomed) ?? false;
    if (!seen) {
      await prefs.setBool(_kLandingWelcomed, true);
      if (!mounted) return;
      await _narration.speakAndWait(RegisterTtsKeys.landingWelcome);
      if (!mounted) return;
      await _narration.speakAndWait(RegisterTtsKeys.landingCta);
    }
  }

  @override
  void dispose() {
    _narration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Contenido principal ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Logo en círculo suave
                  Center(
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFEBE4),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(22),
                      child: Image.asset('assets/icons/brain_logo.png'),
                    ),
                  ),

                  const Spacer(),

                  // Título
                  const Text(
                    'RehabilitIA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 38,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w800,
                      color: _accentColor,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Subtítulo
                  Text(
                    'Tu compañero para recuperar\nel lenguaje, paso a paso.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade600,
                      height: 1.55,
                    ),
                  ),

                  const Spacer(),

                  // Banner de ayuda familiar (dismissible)
                  if (_bannerVisible)
                    HelperBanner(
                      onDismiss: () => setState(() => _bannerVisible = false),
                    ),

                  const SizedBox(height: 24),

                  // Botón principal: Registrarse
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/register-main'),
                      icon: const Icon(Icons.person_add_rounded, size: 22),
                      label: const Text(
                        'Registrarse',
                        style: TextStyle(
                          fontSize: 18,
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Botón secundario: Iniciar Sesión (outlined)
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accentColor,
                        side: const BorderSide(color: _accentColor, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text(
                        'Iniciar Sesión',
                        style: TextStyle(
                          fontSize: 18,
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),

            // ── Botón mute (esquina superior derecha) ───────────────────────
            Positioned(
              top: 4,
              right: 4,
              child: MuteButton(narration: _narration),
            ),
          ],
        ),
      ),
    );
  }
}
