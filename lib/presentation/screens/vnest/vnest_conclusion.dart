import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../register/register_viewmodel.dart';

class VnestConclusionScreen extends StatelessWidget {
  final Map<String, dynamic> exercise;

  const VnestConclusionScreen({super.key, required this.exercise});

  // ================================
  // 🔹 Completar ejercicio directamente en Firestore
  // ================================
  Future<void> _completeExercise(BuildContext context) async {
    final registerVM = Provider.of<RegisterViewModel>(context, listen: false);
    final userId = registerVM.userId;
    final firestore = FirebaseFirestore.instance;

    final idEjercicio = exercise['id_ejercicio_general'] ?? "";
    final contexto = exercise['context'] ?? exercise['contexto'] ?? "";

    try {
      final pacienteRef = firestore.collection("pacientes").doc(userId);
      final ejerciciosRef = pacienteRef.collection("ejercicios_asignados");

      final query = await ejerciciosRef
          .where("id_ejercicio", isEqualTo: idEjercicio)
          .where("contexto", isEqualTo: contexto)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first.reference;
        await doc.update({
          "estado": "completado",
          "ultima_fecha_realizado": FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Ejercicio completado con éxito")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Ejercicio no encontrado en tus asignaciones."),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error al completar: $e")),
      );
    }
  }

  // ================================
  // Utils de texto
  // ================================
  String capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String decapitalize(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  String conjugatePresentIndicative(String sujeto, String verbo) {
    if (verbo.endsWith("ar")) return "${verbo.substring(0, verbo.length - 2)}a";
    if (verbo.endsWith("er")) return "${verbo.substring(0, verbo.length - 2)}e";
    if (verbo.endsWith("ir")) return "${verbo.substring(0, verbo.length - 2)}e";
    return verbo;
  }

  // ================================
  // Oración final coloreada
  // ================================
  Widget buildColoredSentence(Map<String, dynamic> data) {
    final who = data['who'] ?? '';
    final what = data['what'] ?? '';
    final verbo = data['verbo'] ?? '';
    final where = data['where'] ?? '';
    final why = data['why'] ?? '';
    final when = data['when'] ?? '';

    final orange = const Color(0xFFF48A63);
    final green = Colors.green.shade700;

    final verboConjugado = conjugatePresentIndicative(who, verbo);

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: [
          if (who.isNotEmpty)
            TextSpan(
              text: "${capitalize(who)} ",
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (verboConjugado.isNotEmpty)
            TextSpan(
              text: "${decapitalize(verboConjugado)} ",
              style: TextStyle(
                color: orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (what.isNotEmpty)
            TextSpan(
              text: "${decapitalize(what)} ",
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (where.isNotEmpty)
            TextSpan(
              text: "${decapitalize(where)} ",
              style: TextStyle(
                color: green,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (why.isNotEmpty)
            TextSpan(
              text: "${decapitalize(why)} ",
              style: TextStyle(
                color: green,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (when.isNotEmpty)
            TextSpan(
              text: decapitalize(when),
              style: TextStyle(
                color: green,
                fontWeight: FontWeight.w600,
              ),
            ),
          const TextSpan(
            text: ".",
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ================================
  // BUILD
  // ================================
  @override
  Widget build(BuildContext context) {
    final background = const Color(0xFFFEF9F4);
    final orange = const Color(0xFFF48A63);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 30),
              Icon(Icons.celebration_rounded, color: orange, size: 60),
              const SizedBox(height: 10),
              Text(
                "¡Felicidades!",
                style: TextStyle(
                  color: orange,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Has completado el ejercicio VNeST",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),

              // --- Resumen ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Resumen del ejercicio",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        "Contexto", exercise['context'] ?? exercise['contexto'] ?? "—"),
                    _buildInfoRow(
                        "Pareja", "${exercise['who'] ?? ""} + ${exercise['what'] ?? ""}"),
                    _buildInfoRow("Verbo trabajado", exercise['verbo'] ?? ""),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- Oración final destacada ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: orange.withOpacity(0.3), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Oración final",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: orange,
                      ),
                    ),
                    const SizedBox(height: 10),
                    buildColoredSentence(exercise),
                  ],
                ),
              ),

              const Spacer(),

              // --- Botón CTA ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _completeExercise(context);
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/menu', (route) => false);
                  },
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  label: const Text(
                    "Empezar de nuevo",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              "$label:",
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
