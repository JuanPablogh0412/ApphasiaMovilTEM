import 'dart:math';
import 'package:flutter/material.dart';

/// =============================
///  Modelo para opción-explicación
/// =============================
class ExpansionPair {
  final String opcion;
  final String explicacion;
  const ExpansionPair(this.opcion, this.explicacion);
}

/// =============================
///  Funciones compartidas (texto)
/// =============================
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String decapitalize(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

String conjugatePresentIndicative(String sujeto, String verbo) {
  if (verbo.endsWith("ar")) return "${verbo.substring(0, verbo.length - 2)}a";
  if (verbo.endsWith("er") || verbo.endsWith("ir")) {
    return "${verbo.substring(0, verbo.length - 2)}e";
  }
  return verbo;
}

/// =============================
///  Construcción de oración coloreada (agrandada)
/// =============================
Widget buildColoredSentence({
  required String who,
  required String verbo,
  required String what,
  String? where,
  String? why,
  String? when,
  String? correctDonde,
  String? correctPorque,
  String? correctCuando,
  required Color verbColor,
  double fontSize = 16,
  double lineHeight = 1.3,
}) {
  final whereCorrect = where != null && where == correctDonde;
  final whyCorrect = why != null && why == correctPorque;
  final whenCorrect = when != null && when == correctCuando;

  TextStyle base(Color color, {FontWeight weight = FontWeight.w600}) =>
      TextStyle(color: color, fontWeight: weight, fontSize: fontSize, height: lineHeight);

  return RichText(
    textAlign: TextAlign.center,
    text: TextSpan(
      children: [
        TextSpan(text: "${capitalize(who)} ", style: base(Colors.black87)),
        TextSpan(
          text: "${decapitalize(conjugatePresentIndicative(who, verbo))} ",
          style: base(verbColor),
        ),
        TextSpan(text: "${decapitalize(what)} ", style: base(Colors.black87)),
        if (where != null)
          TextSpan(
            text: "${decapitalize(where)} ",
            style: base(whereCorrect ? Colors.green.shade700 : Colors.red.shade700),
          ),
        if (why != null)
          TextSpan(
            text: "${decapitalize(why)} ",
            style: base(whyCorrect ? Colors.green.shade700 : Colors.red.shade700),
          ),
        if (when != null)
          TextSpan(
            text: decapitalize(when),
            style: base(whenCorrect ? Colors.green.shade700 : Colors.red.shade700),
          ),
        TextSpan(text: ".", style: base(Colors.black87)),
      ],
    ),
  );
}

/// =============================
///  Helpers para priorizar PERSONALIZADO
/// =============================
Map<String, dynamic> _asMap(dynamic v) =>
    (v is Map) ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List _asList(dynamic v) => (v is List) ? v : const [];

Map<String, dynamic> _pickExpansiones(
  Map<String, dynamic> ex,
  String who,
  String what,
) {
  // 1) Plano 'expansiones'
  final rootExp = _asMap(ex['expansiones']);
  if (rootExp.isNotEmpty) return rootExp;

  // 2) Plano 'personalizado'
  final pers = _asMap(ex['personalizado']);
  if (pers.isNotEmpty) return pers;

  // 3) paresPersonalizados
  final paresPers = _asList(ex['paresPersonalizados']);
  if (paresPers.isNotEmpty) {
    final match = paresPers.cast<Map>().firstWhere(
      (p) => p['sujeto'] == who && p['objeto'] == what,
      orElse: () => paresPers.first as Map,
    );
    final exp = _asMap(match['expansiones']);
    if (exp.isNotEmpty) return exp;
  }

  // 4) pares (base)
  final paresBase = _asList(ex['pares']);
  if (paresBase.isNotEmpty) {
    final match = paresBase.cast<Map>().firstWhere(
      (p) => p['sujeto'] == who && p['objeto'] == what,
      orElse: () => paresBase.first as Map,
    );
    final exp = _asMap(match['expansiones']);
    if (exp.isNotEmpty) return exp;
  }

  return <String, dynamic>{};
}

/// Crea la lista de pares (opción/explicación) desde una sección
List<ExpansionPair> _makePairsFrom(Map<String, dynamic> seccion) {
  final ops = List<String>.from(_asList(seccion['opciones']));
  final exps = List<String>.from(_asList(seccion['explicaciones']));
  final pairs = <ExpansionPair>[];
  for (var i = 0; i < ops.length; i++) {
    pairs.add(ExpansionPair(ops[i], i < exps.length ? exps[i] : ""));
  }
  pairs.shuffle(Random());
  return pairs;
}

/// =============================
///  WIDGET BASE REUTILIZABLE (un paso)
/// =============================
class VnestStepScreen extends StatelessWidget {
  final int step;
  final String title;
  final IconData icon;
  final Color accent;
  final List<ExpansionPair> pairs;
  final String? selectedValue;
  final String? correctValue;
  final void Function(String) onSelect;
  final VoidCallback onNext;
  final String? feedback;
  final String who;
  final String verbo;
  final String what;
  final String? where;
  final String? why;
  final String? when;
  final String? correctDonde;
  final String? correctPorque;
  final String? correctCuando;

  const VnestStepScreen({
    super.key,
    required this.step,
    required this.title,
    required this.icon,
    required this.accent,
    required this.pairs,
    required this.selectedValue,
    required this.correctValue,
    required this.onSelect,
    required this.onNext,
    required this.feedback,
    required this.who,
    required this.verbo,
    required this.what,
    this.where,
    this.why,
    this.when,
    this.correctDonde,
    this.correctPorque,
    this.correctCuando,
  });

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFFFF7F2);

    final selectedPair = pairs.firstWhere(
      (p) => p.opcion == selectedValue,
      orElse: () => const ExpansionPair("", ""),
    );

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: accent),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Expansión de Oraciones",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            children: [
              // Paso
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Paso $step de 5",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Barra de progreso (similar estilo)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: step / 5,
                  color: accent,
                  backgroundColor: Colors.grey.shade300.withOpacity(0.4),
                  minHeight: 8,
                ),
              ),

              const SizedBox(height: 18),

              // Instrucciones
              _buildInstructionsBox(step),

              const SizedBox(height: 18),

              // Tarjetas ¿Quién? Verbo ¿Qué?
              _headerCards(accent),

              const SizedBox(height: 24),

              // Contenido scrollable
              Expanded(
                child: ListView(
                  children: [
                    _questionSection(selectedPair),
                    if (selectedPair.explicacion.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 18),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300.withOpacity(0.4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          selectedPair.explicacion,
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ),
                  ],
                ),
              ),

              // Feedback de validación
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    feedback!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // Oración construida
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8DD),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: buildColoredSentence(
                  who: who,
                  verbo: verbo,
                  what: what,
                  where: where,
                  why: why,
                  when: when,
                  verbColor: accent,
                  correctDonde: correctDonde,
                  correctPorque: correctPorque,
                  correctCuando: correctCuando,
                  fontSize: 16,
                  lineHeight: 1.3,
                ),
              ),

              // Botones Anterior / Siguiente
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Anterior",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        disabledBackgroundColor: accent.withOpacity(0.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Siguiente",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
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

  Widget _buildInstructionsBox(int step) {
    String text = "";
    switch (step) {
      case 2:
        text = "Elige ¿Dónde? (lugar)";
        break;
      case 3:
        text = "Elige ¿Por qué? (razón)";
        break;
      case 4:
        text = "Elige ¿Cuándo? (tiempo)";
        break;
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        color: Colors.grey.shade800,
        height: 1.4,
      ),
    );
  }

  Widget _headerCards(Color accent) {
    final verboConjugado = conjugatePresentIndicative(who, verbo);

    Widget wordCard(String label, String text, {bool isVerb = false}) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: isVerb ? accent.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isVerb ? accent : Colors.grey.shade300,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isVerb ? accent : Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isVerb ? accent : Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        wordCard("¿Quién?", capitalize(who)),
        wordCard("Verbo", verboConjugado, isVerb: true),
        wordCard("¿Qué?", decapitalize(what)),
      ],
    );
  }

  Widget _questionSection(ExpansionPair selectedPair) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título + icono
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withOpacity(0.15),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Opciones
        ...pairs.map((p) {
          final isSelected = selectedValue == p.opcion;
          final isCorrect = isSelected && p.opcion == correctValue;
          final isWrong = isSelected && p.opcion != correctValue;

          Color borderColor = Colors.grey.shade300;
          Color bgColor = Colors.white;
          Color textColor = Colors.black87;

          if (isSelected) {
            borderColor = accent;
            bgColor = const Color(0xFFFFE8DD);
          }
          if (isCorrect) {
            borderColor = Colors.green.shade600;
            bgColor = Colors.green.shade50;
            textColor = Colors.green.shade900;
          } else if (isWrong) {
            borderColor = Colors.red.shade600;
            bgColor = Colors.red.shade50;
            textColor = Colors.red.shade900;
          }

          return GestureDetector(
            onTap: () => onSelect(p.opcion),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.opcion,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                  if (isCorrect)
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                  if (isWrong)
                    const Icon(Icons.cancel_rounded, color: Colors.red, size: 20),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// =============================================================
/// 🟠 PANTALLA 1 — ¿DÓNDE?
/// =============================================================
class VnestWhereScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const VnestWhereScreen({super.key, required this.data});

  @override
  State<VnestWhereScreen> createState() => _VnestWhereScreenState();
}

class _VnestWhereScreenState extends State<VnestWhereScreen> {
  // 🎨 misma paleta que VnestSelectContextScreen
  final orange = const Color(0xFFF48A63);

  List<ExpansionPair> dondePairs = [];
  String? correctDonde;
  String? selectedWhere;
  String? feedback;
  late String verbo;
  late String who;
  late String what;

  @override
  void initState() {
    super.initState();
    final ex = Map<String, dynamic>.from(widget.data);
    verbo = ex['verbo'] ?? '';
    who = ex['who'] ?? '';
    what = ex['what'] ?? '';

    final expansiones = _pickExpansiones(ex, who, what);
    final donde = _asMap(expansiones['donde']);

    correctDonde = donde['opcion_correcta'];
    dondePairs = _makePairsFrom(donde);
  }

  void handleNext() {
    if (selectedWhere == null) {
      setState(() => feedback = "Selecciona una opción antes de continuar.");
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VnestWhyScreen(
          data: {
            ...widget.data,
            'where': selectedWhere,
            'correctDonde': correctDonde,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VnestStepScreen(
      step: 2,
      title: "¿Dónde?",
      icon: Icons.location_on_rounded,
      accent: orange,
      pairs: dondePairs,
      selectedValue: selectedWhere,
      correctValue: correctDonde,
      onSelect: (v) => setState(() {
        selectedWhere = v;
        feedback = null;
      }),
      onNext: handleNext,
      feedback: feedback,
      who: who,
      verbo: verbo,
      what: what,
      where: selectedWhere,
      correctDonde: correctDonde,
    );
  }
}

/// =============================================================
/// 🟢 PANTALLA 2 — ¿POR QUÉ?
/// =============================================================
class VnestWhyScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const VnestWhyScreen({super.key, required this.data});

  @override
  State<VnestWhyScreen> createState() => _VnestWhyScreenState();
}

class _VnestWhyScreenState extends State<VnestWhyScreen> {
  final orange = const Color(0xFFF48A63);

  List<ExpansionPair> porquePairs = [];
  String? correctPorque;
  String? selectedWhy;
  String? feedback;
  late String verbo;
  late String who;
  late String what;
  String? selectedWhere;
  String? correctDonde;

  @override
  void initState() {
    super.initState();
    final ex = Map<String, dynamic>.from(widget.data);
    verbo = ex['verbo'] ?? '';
    who = ex['who'] ?? '';
    what = ex['what'] ?? '';

    selectedWhere = ex['where'];
    correctDonde = ex['correctDonde'];

    final expansiones = _pickExpansiones(ex, who, what);
    final porque = _asMap(expansiones['por_que']); // importante: 'por_que'

    correctPorque = porque['opcion_correcta'];
    porquePairs = _makePairsFrom(porque);
  }

  void handleNext() {
    if (selectedWhy == null) {
      setState(() => feedback = "Selecciona una opción antes de continuar.");
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VnestWhenScreen(
          data: {
            ...widget.data,
            'where': selectedWhere,
            'why': selectedWhy,
            'correctDonde': correctDonde,
            'correctPorque': correctPorque,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VnestStepScreen(
      step: 3,
      title: "¿Por qué?",
      icon: Icons.psychology_alt_rounded,
      accent: orange,
      pairs: porquePairs,
      selectedValue: selectedWhy,
      correctValue: correctPorque,
      onSelect: (v) => setState(() {
        selectedWhy = v;
        feedback = null;
      }),
      onNext: handleNext,
      feedback: feedback,
      who: who,
      verbo: verbo,
      what: what,
      where: selectedWhere,
      why: selectedWhy,
      correctDonde: correctDonde,
      correctPorque: correctPorque,
    );
  }
}

/// =============================================================
/// 🟣 PANTALLA 3 — ¿CUÁNDO?
/// =============================================================
class VnestWhenScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const VnestWhenScreen({super.key, required this.data});

  @override
  State<VnestWhenScreen> createState() => _VnestWhenScreenState();
}

class _VnestWhenScreenState extends State<VnestWhenScreen> {
  final orange = const Color(0xFFF48A63);

  List<ExpansionPair> cuandoPairs = [];
  String? correctCuando;
  String? selectedWhen;
  String? feedback;
  late String verbo;
  late String who;
  late String what;
  String? selectedWhere;
  String? selectedWhy;
  String? correctDonde;
  String? correctPorque;

  @override
  void initState() {
    super.initState();
    final ex = Map<String, dynamic>.from(widget.data);
    verbo = ex['verbo'] ?? '';
    who = ex['who'] ?? '';
    what = ex['what'] ?? '';

    selectedWhere = ex['where'];
    selectedWhy = ex['why'];
    correctDonde = ex['correctDonde'];
    correctPorque = ex['correctPorque'];

    final expansiones = _pickExpansiones(ex, who, what);
    final cuando = _asMap(expansiones['cuando']);

    correctCuando = cuando['opcion_correcta'];
    cuandoPairs = _makePairsFrom(cuando);
  }

  void handleNext() {
    if (selectedWhen == null) {
      setState(() => feedback = "Selecciona una opción antes de continuar.");
      return;
    }

    final whereCorrect = selectedWhere == correctDonde;
    final whyCorrect = selectedWhy == correctPorque;
    final whenCorrect = selectedWhen == correctCuando;

    if (!whereCorrect || !whyCorrect || !whenCorrect) {
      setState(() {
        feedback = "Debes seleccionar correctamente las tres opciones antes de continuar.";
      });
      return;
    }

    Navigator.pushNamed(
      context,
      '/vnest-phase3',
      arguments: {
        ...widget.data,
        'where': selectedWhere,
        'why': selectedWhy,
        'when': selectedWhen,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return VnestStepScreen(
      step: 4,
      title: "¿Cuándo?",
      icon: Icons.access_time_rounded,
      accent: orange,
      pairs: cuandoPairs,
      selectedValue: selectedWhen,
      correctValue: correctCuando,
      onSelect: (v) => setState(() {
        selectedWhen = v;
        feedback = null;
      }),
      onNext: handleNext,
      feedback: feedback,
      who: who,
      verbo: verbo,
      what: what,
      where: selectedWhere,
      why: selectedWhy,
      when: selectedWhen,
      correctDonde: correctDonde,
      correctPorque: correctPorque,
      correctCuando: correctCuando,
    );
  }
}
