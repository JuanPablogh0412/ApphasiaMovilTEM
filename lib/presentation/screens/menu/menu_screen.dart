import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/register/register_viewmodel.dart';
import '../../../services/auth_service.dart';
import '../../../services/tem/narration_service.dart';
import '../../widgets/mute_button.dart';

const _bgColor = Color(0xFFFFF7F2);
const _accentColor = Color(0xFFF48A63);

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final NarrationService _narration = NarrationService();
  String _nombre = '';

  @override
  void initState() {
    super.initState();
    _narration.init();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final registerVM = Provider.of<RegisterViewModel>(context, listen: false);
    final userId = registerVM.userId;
    if (userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('pacientes')
          .doc(userId)
          .get();
      final nombre = doc.data()?['nombre'] as String? ?? '';
      if (mounted) setState(() => _nombre = nombre);
    } catch (e) {
      debugPrint('❌ [Menu] Error al cargar nombre: $e');
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              narration: _narration,
              onLogout: () => _showLogoutConfirmation(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),
                    Text(
                      _nombre.isNotEmpty ? 'Hola, $_nombre' : 'Hola',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '¿Qué practicamos hoy?',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 36),
                    _TherapyCard(
                      title: 'VNeST',
                      label: 'Verbos y frases',
                      icon: Icons.hub_rounded,
                      circleColor: const Color(0xFFFFE8DD),
                      iconColor: _accentColor,
                      onTap: () => Navigator.pushNamed(context, '/vnest'),
                    ),
                    const SizedBox(height: 16),
                    _TherapyCard(
                      title: 'Recuperación Espaciada',
                      label: 'Memoria',
                      icon: Icons.access_time_rounded,
                      circleColor: const Color(0xFFDCEEFF),
                      iconColor: const Color(0xFF5B9BD5),
                      onTap: () => Navigator.pushNamed(context, '/sr'),
                    ),
                    const SizedBox(height: 16),
                    _TherapyCard(
                      title: 'Entonación Melódica',
                      label: 'Pronunciación',
                      icon: Icons.music_note_rounded,
                      circleColor: const Color(0xFFD6F2E0),
                      iconColor: const Color(0xFF4CAF50),
                      onTap: () => Navigator.pushNamed(context, '/tem-home'),
                    ),
                    const SizedBox(height: 24),
                    _SecondaryCard(
                      onTap: () => Navigator.pushNamed(
                          context, '/personalize-exercises'),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    final authService = AuthService();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            '¿Cerrar sesión?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          content: const Text(
            '¿Estás seguro de que deseas cerrar sesión?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Cerrar sesión',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await authService.clearLoginState();
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    }
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({required this.narration, required this.onLogout});

  final NarrationService narration;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Image.asset('assets/icons/brain_logo.png', height: 32),
          const SizedBox(width: 8),
          const Text(
            'RehabilitIA',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _accentColor,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          MuteButton(narration: narration),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onLogout,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.logout_rounded,
                size: 20,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta de terapia ───────────────────────────────────────────────────────
class _TherapyCard extends StatelessWidget {
  const _TherapyCard({
    required this.title,
    required this.label,
    required this.icon,
    required this.circleColor,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String label;
  final IconData icon;
  final Color circleColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 38),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tarjeta secundaria (Personalizar) ────────────────────────────────────────
class _SecondaryCard extends StatelessWidget {
  const _SecondaryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFEEE8FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF7C6FCD),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personalizar ejercicios',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Crear actividades propias',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
