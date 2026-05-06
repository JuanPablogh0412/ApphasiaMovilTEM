import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/tem/narration_service.dart';
import '../../widgets/helper_banner.dart';
import '../../widgets/mute_button.dart';
import 'register_viewmodel.dart';

const _bgColor = Color(0xFFFFF7F2);
const _accentColor = Color(0xFFF48A63);

class RegisterMainScreen extends StatefulWidget {
  final bool showSuccess;
  const RegisterMainScreen({super.key, this.showSuccess = false});

  @override
  State<RegisterMainScreen> createState() => _RegisterMainScreenState();
}

class _RegisterMainScreenState extends State<RegisterMainScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _bannerVisible = true;

  static final _emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+(\.[\w\-]+)+$');

  final NarrationService _narration = NarrationService();

  @override
  void initState() {
    super.initState();
    if (!widget.showSuccess) {
      _narration.init();
    }
  }

  @override
  void dispose() {
    _narration.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // ── Header con logo y botón mute ────────────────────────
              Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Image.asset(
                      'assets/icons/brain_logo.png',
                      height: 70,
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: widget.showSuccess
                        ? null
                        : MuteButton(narration: _narration),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Expanded(
                child: widget.showSuccess
                    ? _buildSuccessContent(context)
                    : _buildIntroContent(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Registro (intro) ──────────────────────────────────────────────────────
  Widget _buildIntroContent(BuildContext context) {
    final registerVM = Provider.of<RegisterViewModel>(context, listen: false);

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Registro de paciente',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            Text(
              'Completa tu correo y contraseña para continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),

            const SizedBox(height: 20),

            // Banner de ayuda familiar
            if (_bannerVisible)
              HelperBanner(
                onDismiss: () => setState(() => _bannerVisible = false),
              ),

            const SizedBox(height: 28),

            // ── Campo email ─────────────────────────────────────────────
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Ingresa tu correo electrónico.';
                if (!_emailRegex.hasMatch(v))
                  return 'Correo no válido (ej: nombre@dominio.com).';
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Correo electrónico',
                hintText: 'ejemplo@correo.com',
                filled: true,
                fillColor: const Color(0xFFE8EBF3),
                labelStyle: TextStyle(color: Colors.grey.shade700),
                hintStyle: TextStyle(color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 1.5,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 1.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Campo contraseña ────────────────────────────────────────
            TextFormField(
              controller: _passwordCtrl,
              obscureText: !_showPassword,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                if ((value?.length ?? 0) < 6)
                  return 'La contraseña debe tener al menos 6 caracteres.';
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Contraseña',
                hintText: 'Mínimo 6 caracteres',
                filled: true,
                fillColor: const Color(0xFFE8EBF3),
                labelStyle: TextStyle(color: Colors.grey.shade700),
                hintStyle: TextStyle(color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 1.5,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 1.5,
                  ),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                    color: _accentColor,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Botón Continuar ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;

                  final email = _emailCtrl.text.trim();
                  final password = _passwordCtrl.text.trim();
                  registerVM.setAuthData(email: email, password: password);
                  Navigator.pushNamed(context, '/register-personal');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Continuar',
                  style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Enlace a login
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text(
                  '¿Ya tienes cuenta? Inicia sesión',
                  style: TextStyle(
                    color: _accentColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Registro exitoso ──────────────────────────────────────────────────────
  Widget _buildSuccessContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: Color(0xFFE8EBF3),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: _accentColor, size: 60),
        ),
        const SizedBox(height: 24),

        const Text(
          '¡Registro completado!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Tu cuenta ha sido creada con éxito.\nYa puedes comenzar tus ejercicios.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),

        const SizedBox(height: 40),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/menu'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Ir a ejercicios',
              style: TextStyle(
                fontSize: 18,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
