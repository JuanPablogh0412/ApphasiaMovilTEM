import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/register/register_viewmodel.dart';
import '../../../services/auth_service.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final background = const Color(0xFFFFF7F2); // Fondo suave
  final orange = const Color(0xFFF48A63); // Naranja cálido

  int _currentIndex = 0;
  int completedCount = 0;
  String lastExercise = "-";

  @override
  void initState() {
    super.initState();
    _fetchProgress();
  }

  Future<void> _fetchProgress() async {
    final registerVM = Provider.of<RegisterViewModel>(context, listen: false);
    final userId = registerVM.userId;

    try {
      final ref = FirebaseFirestore.instance
          .collection('pacientes')
          .doc(userId)
          .collection('ejercicios_asignados');

      final snap = await ref.get();
      final completed = snap.docs
          .where((d) => d['estado'] == 'completado')
          .toList();

      setState(() {
        completedCount = completed.length;
        if (completed.isNotEmpty) {
          final last = completed.last.data();
          lastExercise = last['contexto'] ?? '-';
        }
      });
    } catch (e) {
      debugPrint("❌ [Menu] Error al cargar progreso: $e");
    }
  }

  final List<Widget> _pages = [];

  @override
  Widget build(BuildContext context) {
    _pages
      ..clear()
      ..addAll([_buildTherapies(), _buildPersonalize(), _buildProfile()]);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(child: _pages[_currentIndex]),

      // --- Bottom nav más "real" ---
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.white,
          selectedItemColor: orange,
          unselectedItemColor: Colors.grey.shade400,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.psychology_rounded),
              label: "Terapias",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.build_rounded),
              label: "Personalizar",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: "Perfil",
            ),
          ],
        ),
      ),
    );
  }

  // ===================================================
  //             APP BAR REUTILIZABLE (logo + pop)
  // ===================================================
  Widget _topBar() {
    return Row(
      children: [
        // Logo Rehabilita
        Image.asset('assets/icons/brain_logo.png', height: 32),
        const SizedBox(width: 8),
        Text(
          'RehabilitIA',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: orange,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        // Logout button with double confirmation
        GestureDetector(
          onTap: () => _showLogoutConfirmation(context),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
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
    );
  }

  // ===================================================
  //                   HEADER
  // ===================================================
  Widget _header(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  // ===================================================
  //                    TERAPIAS
  // ===================================================
  Widget _buildTherapies() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            const SizedBox(height: 24),
            _header(
              "¡Bienvenido!",
              "Selecciona la terapia con la que quieres practicar hoy",
            ),
            _therapyCard(
              title: "Terapia VNeST",
              description:
                  "Conecta sujeto, verbo y objeto para fortalecer la producción del lenguaje.",
              icon: Icons.hub_rounded,
              onTap: () => Navigator.pushNamed(context, '/vnest'),
            ),
            const SizedBox(height: 20),
            _therapyCard(
              title: "Recuperación Espaciada",
              description:
                  "Repite conceptos a intervalos crecientes para reforzar la memoria.",
              icon: Icons.access_time_rounded,
              onTap: () => Navigator.pushNamed(context, '/sr'),
            ),
            const SizedBox(height: 20),
            _therapyCard(
              title: "Entonación Melódica",
              description:
                  "Entona diferentes palabras junto a su pronunciación e imagen para recuperar el habla.",
              icon: Icons.music_note_rounded,
              onTap: () => Navigator.pushNamed(context, '/tem-home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _therapyCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Ícono en circulito con pop de color
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE8DD),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Color(0xFFF48A63), size: 28),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 0,
              ),
              child: const Text(
                "Comenzar",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================
  //                  PERSONALIZAR
  // ===================================================
  Widget _buildPersonalize() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _topBar(),
          const SizedBox(height: 24),
          const Text(
            "Personaliza tu práctica",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Iconito en círculo suave
          Container(
            width: 110,
            height: 110,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE8DD),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.edit_rounded, color: orange, size: 44),
          ),

          const SizedBox(height: 26),
          const Text(
            "Crea ejercicios a tu medida",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            "Diseña actividades adaptadas a tu vida diaria para mantener la motivación y el progreso.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.pushNamed(context, '/personalize-exercises'),
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 0,
              ),
              child: const Text(
                "Empezar a personalizar",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ===================================================
  //              TARJETA DE PROGRESO
  // ===================================================
  Widget _progressCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "Progreso de ejercicios",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: completedCount > 0 ? 1.0 : 0.0,
                  color: orange,
                  strokeWidth: 9,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              Text(
                completedCount.toString(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Última terapia: $lastExercise",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ===================================================
  //                     PERFIL
  // ===================================================
  Widget _buildProfile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            const SizedBox(height: 24),
            _header("Mi Perfil", "Tu progreso y configuración personal"),
            _progressCard(),
            const SizedBox(height: 32),
            Center(
              child: Text(
                "Más opciones de perfil próximamente",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================================================
  //           LOGOUT CONFIRMATION DIALOG
  // ===================================================
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
                backgroundColor: orange,
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
      // Clear login state and navigate to landing
      await authService.clearLoginState();

      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    }
  }
}
