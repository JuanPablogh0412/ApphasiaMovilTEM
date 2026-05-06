import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../../data/services/api_service.dart';
import '../../../services/tem/narration_service.dart';
import '../../../services/register/register_tts_keys.dart';
import '../../widgets/guided_tour.dart';
import '../../widgets/mute_button.dart';
import '../../widgets/helper_banner.dart';
import '../register/register_viewmodel.dart';

class RegisterRoutineScreen extends StatefulWidget {
  const RegisterRoutineScreen({super.key});

  @override
  State<RegisterRoutineScreen> createState() => _RegisterRoutineScreenState();
}

class _RegisterRoutineScreenState extends State<RegisterRoutineScreen> {
  final TextEditingController _infoIA = TextEditingController();
  final ApiService apiService = ApiService();

  bool _isLoading = false;
  bool _showConfirmation = false;
  bool _isListening = false;
  bool _userStopped = false;
  bool _bannerVisible = true;
  String _confirmedText = '';
  String _lastPartial = '';

  // Claves para el spotlight del tour
  final GlobalKey _iaCardKey = GlobalKey();
  final GlobalKey _rutinaKey = GlobalKey();
  final GlobalKey _objetoKey = GlobalKey();

  final NarrationService _narration = NarrationService();

  List<Map<String, String>> rutinas = [];
  List<Map<String, String>> objetos = [];

  int? editingRutinaIndex;
  int? editingObjetoIndex;

  late stt.SpeechToText _speech;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _narration.init();
    Future.microtask(() async => await _initSpeech()).then((_) {
      if (mounted) _runTour();
    });
  }

  Future<void> _runTour() async {
    if (!mounted) return;
    await _narration.speakAndWait(RegisterTtsKeys.step4Intro);
    if (!mounted) return;
    await showGuidedTour(
      context: context,
      narration: _narration,
      steps: [
        GuidedTourStep(
          key: _iaCardKey,
          label:
              'Si puedes, habá aquí y la IA\nregistrará tus rutinas y objetos.',
          ttsKey: RegisterTtsKeys.step4VoiceOffer,
        ),
        GuidedTourStep(
          key: _rutinaKey,
          label:
              'Aquí puedes agregar tus rutinas diarias\n(levantarte, comer, caminar...)',
          ttsKey: RegisterTtsKeys.step4Rutinas,
        ),
        GuidedTourStep(
          key: _objetoKey,
          label:
              'Aquí puedes agregar objetos importantes para ti\n(teléfono, sillón, taza...)',
          ttsKey: RegisterTtsKeys.step4Objetos,
        ),
      ],
    );
  }

  @override
  void deactivate() {
    _narration.stop();
    super.deactivate();
  }

  @override
  void dispose() {
    _narration.dispose();
    _infoIA.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (err) => debugPrint('STT error: ${err.errorMsg}'),
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

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'notListening' && _isListening && !_userStopped) {
      if (_lastPartial.isNotEmpty) {
        _confirmedText = _confirmedText.isEmpty
            ? _lastPartial
            : '$_confirmedText $_lastPartial';
        _lastPartial = '';
      }
      _speech.listen(
        localeId: 'es_ES',
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(minutes: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          _lastPartial = result.recognizedWords;
          final full = _confirmedText.isEmpty
              ? result.recognizedWords
              : '$_confirmedText ${result.recognizedWords}';
          setState(() => _infoIA.text = full);
        },
      );
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      _userStopped = false;
      _confirmedText = _infoIA.text.trim();
      _lastPartial = '';
      setState(() => _isListening = true);
      _speech.listen(
        localeId: 'es_ES',
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(minutes: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          _lastPartial = result.recognizedWords;
          final full = _confirmedText.isEmpty
              ? result.recognizedWords
              : '$_confirmedText ${result.recognizedWords}';
          setState(() => _infoIA.text = full);
        },
      );
    }
  }

  void _stopListening() async {
    _userStopped = true;
    await _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _processWithIA(String text, String userId) async {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Por favor ingresa o graba información para procesar."),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await apiService.post("/profile/structure/", {
        "user_id": userId,
        "raw_text": text,
      });

      if (response.statusCode == 200) {
        final data = response.data["structured_profile"] ?? {};
        final rutinasData = data["rutinas"] ?? [];
        final objetosData = data["objetos"] ?? [];

        setState(() {
          rutinas = (rutinasData as List<dynamic>).map<Map<String, String>>((
            r,
          ) {
            final Map<String, dynamic> item = r as Map<String, dynamic>;
            return {
              "titulo": item["titulo"]?.toString() ?? "",
              "descripcion": item["descripcion"]?.toString() ?? "",
            };
          }).toList();

          objetos = (objetosData as List<dynamic>).map<Map<String, String>>((
            o,
          ) {
            final Map<String, dynamic> item = o as Map<String, dynamic>;
            return {
              "nombre": item["nombre"]?.toString() ?? "",
              "descripcion": item["descripcion"]?.toString() ?? "",
              "tipo_relacion": item["tipo_relacion"]?.toString() ?? "",
            };
          }).toList();

          _showConfirmation = true;
          editingRutinaIndex = null;
          editingObjetoIndex = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Información completada con IA ✅")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error del servidor: ${response.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error procesando con IA: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _agregarRutina() {
    setState(() {
      rutinas.add({"titulo": "", "descripcion": ""});
      editingRutinaIndex = rutinas.length - 1;
    });
  }

  void _eliminarRutina(int index) {
    setState(() {
      rutinas.removeAt(index);
      if (editingRutinaIndex == index) editingRutinaIndex = null;
    });
  }

  void _agregarObjeto() {
    setState(() {
      objetos.add({"nombre": "", "descripcion": "", "tipo_relacion": ""});
      editingObjetoIndex = objetos.length - 1;
    });
  }

  void _eliminarObjeto(int index) {
    setState(() {
      objetos.removeAt(index);
      if (editingObjetoIndex == index) editingObjetoIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final registerVM = Provider.of<RegisterViewModel>(context, listen: false);

    return Scaffold(
      // 🎨 Mismo fondo suave que RegisterFamilyScreen
      backgroundColor: const Color(0xFFFFF7F2),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
                    'Rutinas y Objetos',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  MuteButton(narration: _narration),
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
                    Icons.access_time_rounded,
                    color: Color(0xFFF48A63),
                    size: 46,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // --- Banner familiar ---
              if (_bannerVisible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: HelperBanner(
                    onDismiss: () => setState(() => _bannerVisible = false),
                  ),
                ),

              // --- Sección IA (tarjeta) ---
              Container(
                key: _iaCardKey,
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
                      'Pulsa para grabar o escribe un resumen sobre tus rutinas diarias y objetos importantes.',
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
                            onPressed: _isListening
                                ? _stopListening
                                : _startListening,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isListening
                                  ? Colors.redAccent
                                  : const Color(0xFFF48A63),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 20),
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
                              hintText: 'O escribe aquí tu información...',
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
                              _infoIA.text.trim(),
                              registerVM.userId,
                            ),
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

              // --- Rutinas ---
              Container(
                key: _rutinaKey,
                child: _buildEditableList(
                  title: "Rutinas",
                  items: rutinas,
                  editingIndex: editingRutinaIndex,
                  onAdd: _agregarRutina,
                  onDelete: _eliminarRutina,
                  onEdit: (i) {
                    setState(() {
                      editingRutinaIndex = editingRutinaIndex == i ? null : i;
                    });
                  },
                  isRutina: true,
                ),
              ),

              const SizedBox(height: 24),

              // --- Objetos ---
              Container(
                key: _objetoKey,
                child: _buildEditableList(
                  title: "Objetos",
                  items: objetos,
                  editingIndex: editingObjetoIndex,
                  onAdd: _agregarObjeto,
                  onDelete: _eliminarObjeto,
                  onEdit: (i) {
                    setState(() {
                      editingObjetoIndex = editingObjetoIndex == i ? null : i;
                    });
                  },
                  isRutina: false,
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                      onPressed: _isLoading
                          ? null
                          : () {
                              registerVM.updateRutinas(rutinas: rutinas);
                              registerVM.updateObjetos(objetos: objetos);
                              Navigator.pushReplacementNamed(
                                context,
                                '/register-summary',
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF48A63),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Finalizar registro",
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
    );
  }

  // --- Tarjetas de edición de rutinas y objetos (mismo estilo que familiares) ---
  Widget _buildEditableList({
    required String title,
    required List<Map<String, String>> items,
    required int? editingIndex,
    required VoidCallback onAdd,
    required Function(int) onDelete,
    required Function(int) onEdit,
    required bool isRutina,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título + botón agregar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, color: Color(0xFFF48A63)),
              label: const Text(
                "Agregar",
                style: TextStyle(
                  color: Color(0xFFF48A63),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              "Agrega tus $title aquí.",
              style: const TextStyle(color: Colors.black54, fontSize: 14),
            ),
          )
        else
          Column(
            children: List.generate(items.length, (index) {
              final item = items[index];
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
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8EBF3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isRutina
                                ? Icons.access_time_rounded
                                : Icons.inventory_2_rounded,
                            color: const Color(0xFFF48A63),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isRutina
                                ? (item["titulo"]?.isNotEmpty == true
                                      ? item["titulo"]!
                                      : "Sin título")
                                : (item["nombre"]?.isNotEmpty == true
                                      ? item["nombre"]!
                                      : "Sin nombre"),
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
                          onPressed: () => onEdit(index),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => onDelete(index),
                        ),
                      ],
                    ),

                    if (isEditing) ...[
                      const SizedBox(height: 12),
                      if (isRutina) ...[
                        _editableField(
                          label: "Título",
                          value: item["titulo"] ?? "",
                          onChanged: (v) => items[index]["titulo"] = v,
                        ),
                        _editableField(
                          label: "Descripción",
                          value: item["descripcion"] ?? "",
                          onChanged: (v) => items[index]["descripcion"] = v,
                        ),
                      ] else ...[
                        _editableField(
                          label: "Nombre del objeto",
                          value: item["nombre"] ?? "",
                          onChanged: (v) => items[index]["nombre"] = v,
                        ),
                        _editableField(
                          label: "Tipo de relación",
                          value: item["tipo_relacion"] ?? "",
                          onChanged: (v) => items[index]["tipo_relacion"] = v,
                        ),
                        _editableField(
                          label: "Descripción",
                          value: item["descripcion"] ?? "",
                          onChanged: (v) => items[index]["descripcion"] = v,
                        ),
                      ],
                    ],
                  ],
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _editableField({
    required String label,
    required String value,
    required Function(String) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: TextEditingController(text: value),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFE8EBF3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
