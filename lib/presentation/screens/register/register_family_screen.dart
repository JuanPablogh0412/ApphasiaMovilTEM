import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../../data/services/api_service.dart';
import 'register_viewmodel.dart';

class RegisterFamilyScreen extends StatefulWidget {
  const RegisterFamilyScreen({super.key});

  @override
  State<RegisterFamilyScreen> createState() => _RegisterFamilyScreenState();
}

class _RegisterFamilyScreenState extends State<RegisterFamilyScreen> {
  final TextEditingController _infoIA = TextEditingController();
  final ApiService apiService = ApiService();

  List<Map<String, String>> familiares = [];
  final List<String> parentescos = [
    'Cónyuge/Pareja',
    'Hijo/a',
    'Padre/Madre',
    'Hermano/a',
    'Otro',
  ];

  // === SPEECH TO TEXT ===
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isLoading = false;
  bool _showConfirmation = false;
  String recognizedText = "";

  int? editingIndex;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    Future.microtask(() async => await _initSpeech());
  }

  Future<void> _initSpeech() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      await _speech.initialize(
        onStatus: (val) => print('Speech status: $val'),
        onError: (val) => print('Speech error: $val'),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Por favor habilita el micrófono para usar reconocimiento de voz.",
          ),
        ),
      );
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: 'es_ES',
        onResult: (result) {
          setState(() {
            recognizedText = result.recognizedWords;
            _infoIA.text = recognizedText;
          });
        },
      );
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _agregarFamiliar() {
    setState(() {
      familiares.add({
        'nombre': '',
        'tipo_relacion': parentescos.first,
        'descripcion': '',
      });
      editingIndex = familiares.length - 1;
    });
  }

  void _eliminarFamiliar(int index) {
    setState(() {
      familiares.removeAt(index);
      if (editingIndex == index) editingIndex = null;
    });
  }

  Future<void> _processWithIA(String text, String userId) async {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Por favor ingresa o graba información para procesar."),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await apiService.post(
        "/profile/structure/",
        {
          "user_id": userId,
          "raw_text": text,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data["structured_profile"] ?? {};
        final familiaData = data["familia"] ?? [];

        setState(() {
          familiares = (familiaData as List<dynamic>).map<Map<String, String>>(
            (f) {
              final Map<String, dynamic> item = f as Map<String, dynamic>;
              return {
                "nombre": item["nombre"]?.toString() ?? "",
                "tipo_relacion": item["tipo_relacion"]?.toString() ?? "Otro",
                "descripcion": item["descripcion"]?.toString() ?? "",
              };
            },
          ).toList();
          _showConfirmation = true;
          editingIndex = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Información familiar completada con IA ✅")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error del servidor: ${response.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error procesando con IA: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registerVM = Provider.of<RegisterViewModel>(context, listen: false);

    return Scaffold(
      // 🎨 Fondo suave como en RegisterPersonal
      backgroundColor: const Color(0xFFFFF7F2),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Barra superior ---
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: Colors.grey.shade700,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Text(
                      'Información Familiar',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
                const SizedBox(height: 20),

                // --- Icono central ---
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EBF3),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.family_restroom_rounded,
                      color: Color(0xFFF48A63),
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // --- Sección IA (tarjeta) ---
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Rellena automáticamente con IA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pulsa para grabar o escribe un resumen sobre tus familiares para completar los campos de abajo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed:
                                  _isListening ? _stopListening : _startListening,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isListening
                                    ? Colors.redAccent
                                    : const Color(0xFFF48A63),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                elevation: 0,
                              ),
                              child: Icon(
                                _isListening
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                size: 26,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: _infoIA,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText:
                                    'O escribe aquí tu información familiar...',
                                filled: true,
                                fillColor: const Color(0xFFF5F7FB),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () => _processWithIA(
                                _infoIA.text.trim(), registerVM.userId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF48A63),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Procesar con IA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                if (_showConfirmation) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: const Text(
                      "✅ Revisa que la información detectada sea correcta antes de continuar.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // --- Divider ---
                const Row(
                  children: [
                    Expanded(child: Divider(thickness: 1)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'O rellena manualmente',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                    Expanded(child: Divider(thickness: 1)),
                  ],
                ),
                const SizedBox(height: 16),

                // --- Tarjetas de familiares ---
                if (familiares.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.group_outlined,
                          size: 60,
                          color: Colors.orange.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Aún no has agregado familiares",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Puedes añadirlos manualmente o usar la IA para detectarlos.",
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: List.generate(familiares.length, (index) {
                      final f = familiares[index];
                      final isEditing = editingIndex == index;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: isEditing
                                ? Colors.orange.shade200
                                : Colors.grey.shade200,
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8EBF3),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person_rounded,
                                    color: Color(0xFFF48A63),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    f["nombre"]?.isNotEmpty == true
                                        ? f["nombre"]!
                                        : "Sin nombre",
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    isEditing
                                        ? Icons.check_circle_rounded
                                        : Icons.edit_rounded,
                                    color: isEditing
                                        ? const Color(0xFFF48A63)
                                        : Colors.grey,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      editingIndex = isEditing ? null : index;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _eliminarFamiliar(index),
                                ),
                              ],
                            ),
                            if (isEditing) ...[
                              const SizedBox(height: 12),
                              TextField(
                                decoration: InputDecoration(
                                  labelText: "Nombre",
                                  filled: true,
                                  fillColor: const Color(0xFFE8EBF3),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                controller: TextEditingController(
                                  text: f["nombre"],
                                ),
                                onChanged: (v) => f["nombre"] = v,
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: f["tipo_relacion"] ?? parentescos.first,
                                items: parentescos
                                    .map(
                                      (p) => DropdownMenuItem(
                                        value: p,
                                        child: Text(p),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) =>
                                    f["tipo_relacion"] = val ?? parentescos.first,
                                decoration: InputDecoration(
                                  labelText: "Parentesco",
                                  filled: true,
                                  fillColor: const Color(0xFFE8EBF3),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: "Descripción (opcional)",
                                  filled: true,
                                  fillColor: const Color(0xFFE8EBF3),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                controller: TextEditingController(
                                  text: f["descripcion"],
                                ),
                                onChanged: (v) => f["descripcion"] = v,
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ),

                const SizedBox(height: 20),

                // --- Botón agregar familiar ---
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _agregarFamiliar,
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: const Text(
                      'Agregar familiar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF48A63),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // --- Botones inferiores ---
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8EBF3),
                          side: BorderSide.none,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Atrás',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          registerVM.updateFamilia(familiares: familiares);
                          Navigator.pushNamed(context, '/register-routine');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF48A63),
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Siguiente',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
