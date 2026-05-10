import 'package:aphasia_mobile/presentation/screens/register/register_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../../data/services/api_service.dart';
import '../../../services/tem/narration_service.dart';
import '../../../services/register/register_tts_keys.dart';
import '../../widgets/guided_tour.dart';
import '../../widgets/helper_banner.dart';
import '../../widgets/mute_button.dart';

class RegisterPersonalScreen extends StatefulWidget {
  const RegisterPersonalScreen({super.key});

  @override
  State<RegisterPersonalScreen> createState() => _RegisterPersonalScreenState();
}

class _RegisterPersonalScreenState extends State<RegisterPersonalScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _fechaCtrl = TextEditingController();
  final TextEditingController _lugarCtrl = TextEditingController();
  final TextEditingController _ciudadCtrl = TextEditingController();
  final TextEditingController _infoIA = TextEditingController();

  final ApiService apiService = ApiService();
  bool _isLoading = false;
  bool _bannerVisible = true;

  // Claves para el spotlight del tour
  final GlobalKey _iaCardKey = GlobalKey();
  final GlobalKey _nombreKey = GlobalKey();
  final GlobalKey _fechaKey = GlobalKey();
  final GlobalKey _lugarKey = GlobalKey();
  final GlobalKey _ciudadKey = GlobalKey();

  final NarrationService _narration = NarrationService();

  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _doListenScheduled = false;
  String _confirmedText = '';
  String _currentPartial = '';
  int _sttSession = 0;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _narration.init();
    Future.microtask(() async {
      await _initSpeech();
      if (mounted) _runTour();
    });
  }

  Future<void> _runTour() async {
    if (!mounted) return;
    await _narration.speakAndWait(RegisterTtsKeys.step2Intro);
    if (!mounted) return;
    await showGuidedTour(
      context: context,
      narration: _narration,
      steps: [
        GuidedTourStep(
          key: _iaCardKey,
          label:
              'Si tienes ayuda o puedes hacerlo tú,\nhabá aquí y la IA llenará los campos.',
          ttsKey: RegisterTtsKeys.step2VoiceOffer,
        ),
        GuidedTourStep(
          key: _nombreKey,
          label: 'Escribe aquí tu nombre completo',
          ttsKey: RegisterTtsKeys.step2Name,
        ),
        GuidedTourStep(
          key: _fechaKey,
          label: 'Toca aquí para seleccionar tu fecha de nacimiento',
          ttsKey: RegisterTtsKeys.step2Birthdate,
        ),
        GuidedTourStep(
          key: _lugarKey,
          label: 'Escribe la ciudad donde naciste',
          ttsKey: RegisterTtsKeys.step2BirthCity,
        ),
        GuidedTourStep(
          key: _ciudadKey,
          label: 'Escribe la ciudad donde vives actualmente',
          ttsKey: RegisterTtsKeys.step2City,
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
    _nombreCtrl.dispose();
    _fechaCtrl.dispose();
    _lugarCtrl.dispose();
    _ciudadCtrl.dispose();
    _infoIA.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (err) => debugPrint(
          '[STT-ERROR] ${err.errorMsg} permanent=${err.permanent}',
        ),
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
    debugPrint(
      '[STT-STATUS] status="$status" isListening=$_isListening session=$_sttSession scheduled=$_doListenScheduled',
    );
    if (!mounted) return;
    if ((status == 'notListening' || status == 'done') &&
        _isListening &&
        !_doListenScheduled) {
      _doListenScheduled = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        _doListenScheduled = false;
        if (_isListening) _doListen();
      });
    }
  }

  void _doListen() {
    if (!mounted || !_isListening) return;
    final mySession = ++_sttSession;
    debugPrint(
      '[STT-LISTEN] iniciando sesión $mySession confirmedText="$_confirmedText"',
    );
    _speech.listen(
      localeId: 'es_ES',
      pauseFor: const Duration(seconds: 30),
      listenFor: const Duration(minutes: 60),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
      ),
      onResult: (result) {
        debugPrint(
          '[STT-RESULT] session=$mySession/cur=$_sttSession final=${result.finalResult} words="${result.recognizedWords}"',
        );
        if (!mounted || mySession != _sttSession) {
          debugPrint(
            '[STT-RESULT] ⚠️ callback obsoleto ignorado sesión $mySession vs $_sttSession',
          );
          return;
        }
        if (result.finalResult) {
          if (result.recognizedWords.isNotEmpty) {
            _confirmedText = _confirmedText.isEmpty
                ? result.recognizedWords
                : '$_confirmedText ${result.recognizedWords}';
          }
          _currentPartial = '';
        } else {
          _currentPartial = result.recognizedWords;
        }
        final display = _confirmedText.isEmpty
            ? _currentPartial
            : _currentPartial.isEmpty
            ? _confirmedText
            : '$_confirmedText $_currentPartial';
        setState(() => _infoIA.text = display);
      },
    );
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (!available) return;
    _confirmedText = _infoIA.text.trim();
    _currentPartial = '';
    _isListening = true;
    setState(() {});
    debugPrint('[STT-START] confirmedText="$_confirmedText"');
    _doListen();
  }

  void _stopListening() {
    debugPrint('[STT-STOP] invalidando sesión $_sttSession');
    _isListening = false;
    _doListenScheduled = false;
    ++_sttSession;
    setState(() {});
    _speech.stop();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() {
        _fechaCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _processWithIA(String text, String userId) async {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Por favor ingresa información para procesar."),
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
        final personal = data["personal"] ?? {};

        setState(() {
          _nombreCtrl.text = personal["nombre"] ?? "";
          _fechaCtrl.text = personal["fecha_nacimiento"] ?? "";
          _lugarCtrl.text = personal["lugar_nacimiento"] ?? "";
          _ciudadCtrl.text = personal["ciudad_residencia"] ?? "";
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

  @override
  Widget build(BuildContext context) {
    final registerVM = Provider.of<RegisterViewModel>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F2),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: Colors.grey.shade700,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Text(
                      'Datos Personales',
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
                      Icons.person_outline_rounded,
                      color: Color(0xFFF48A63),
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // --- Tarjeta IA, más "card" y suave ---
                Container(
                  key: _iaCardKey,
                  padding: const EdgeInsets.all(18),
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
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pulsa el botón o escribe un breve resumen sobre ti. La IA completará los campos de abajo.',
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
                          // --- Botón mic ---
                          ElevatedButton(
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
                              padding: const EdgeInsets.all(18),
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
                          const SizedBox(width: 12),
                          // --- Campo texto IA ---
                          Expanded(
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

                      // --- Botón procesar con IA ---
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
                const SizedBox(height: 24),

                // --- Banner familiar ---
                if (_bannerVisible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: HelperBanner(
                      onDismiss: () => setState(() => _bannerVisible = false),
                    ),
                  ),

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

                // --- Formulario ---
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInputField(
                        label: 'Nombre completo',
                        controller: _nombreCtrl,
                        placeholder: 'Introduce tu nombre completo',
                        fieldKey: _nombreKey,
                      ),
                      _buildDateField(
                        label: 'Fecha de nacimiento',
                        controller: _fechaCtrl,
                        placeholder: 'DD/MM/AAAA',
                        onTap: () => _selectDate(context),
                        fieldKey: _fechaKey,
                      ),
                      _buildInputField(
                        label: 'Lugar de nacimiento',
                        controller: _lugarCtrl,
                        placeholder: 'Ej: Madrid, España',
                        fieldKey: _lugarKey,
                      ),
                      _buildInputField(
                        label: 'Ciudad de residencia',
                        controller: _ciudadCtrl,
                        placeholder: 'Ej: Bogotá, Colombia',
                        fieldKey: _ciudadKey,
                      ),
                    ],
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
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            registerVM.updatePersonal(
                              nombre: _nombreCtrl.text,
                              fechaNacimiento: _fechaCtrl.text,
                              lugarNacimiento: _lugarCtrl.text,
                              ciudadResidencia: _ciudadCtrl.text,
                            );
                            Navigator.pushNamed(context, '/register-family');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF48A63),
                          padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    Key? fieldKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: fieldKey,
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: placeholder,
            filled: true,
            fillColor: const Color(0xFFE8EBF3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (value) => value == null || value.isEmpty
              ? 'Este campo es obligatorio'
              : null,
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    required VoidCallback onTap,
    Key? fieldKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        key: fieldKey,
        child: TextFormField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          decoration: InputDecoration(
            labelText: label,
            hintText: placeholder,
            filled: true,
            fillColor: const Color(0xFFE8EBF3),
            suffixIcon: const Icon(
              Icons.calendar_today,
              color: Color(0xFFF48A63),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (value) =>
              value == null || value.isEmpty ? 'Selecciona una fecha' : null,
        ),
      ),
    );
  }
}
