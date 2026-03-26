import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../screens/register/register_viewmodel.dart';

class VnestSelectVerbScreen extends StatefulWidget {
  final String vnestContext;

  const VnestSelectVerbScreen({super.key, required this.vnestContext});

  @override
  State<VnestSelectVerbScreen> createState() => _VnestSelectVerbScreenState();
}

class _VnestSelectVerbScreenState extends State<VnestSelectVerbScreen> {
  // 🎨 Colores consistentes con Rehabilita
  final background = const Color(0xFFFFF7F2);
  final orange = const Color(0xFFF48A63);

  bool loading = false;
  bool loadingExercise = false;
  String? error;
  List<Map<String, dynamic>> verbs = [];
  String? selectedVerb;
  bool showExpandedInfo = false;

  @override
  void initState() {
    super.initState();
    fetchVerbs(); // directo desde Firestore
  }

  // ============================
  // 🔹 Resolver doc del paciente (uid/email/campo email)
  // ============================
  Future<String?> _resolvePacienteDocId({String? uid, String? email}) async {
    final col = FirebaseFirestore.instance.collection('pacientes');

    if (email != null && email.isNotEmpty) {
      final byEmailId = await col.doc(email).get();
      if (byEmailId.exists) return byEmailId.id;
    }

    if (uid != null && uid.isNotEmpty) {
      final byUid = await col.doc(uid).get();
      if (byUid.exists) return byUid.id;
    }

    if (email != null && email.isNotEmpty) {
      final q = await col.where('email', isEqualTo: email).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.id;
    }

    return null;
  }

  // ============================
  // 🔹 Verificar si un ejercicio está revisado
  // ============================
  Future<bool> _isEjercicioRevisado(String? idEjercicioGeneral) async {
    if (idEjercicioGeneral == null || idEjercicioGeneral.isEmpty) {
      return false;
    }

    try {
      final ejercicioDoc = await FirebaseFirestore.instance
          .collection('ejercicios')
          .doc(idEjercicioGeneral)
          .get();

      if (!ejercicioDoc.exists) {
        return false;
      }

      final data = ejercicioDoc.data();
      return (data?['revisado'] ?? false) == true;
    } catch (e) {
      return false;
    }
  }

  // ============================
  // 🔹 Obtener verbos + marcar highlight
  // ============================
  Future<void> fetchVerbs() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final registerVM = Provider.of<RegisterViewModel>(context, listen: false);
      final email = registerVM.userEmail;
      final uid = registerVM.userId;

      // 1️⃣ Traer ejercicios VNEST del contexto
      final vnestSnap = await FirebaseFirestore.instance
          .collection('ejercicios_VNEST')
          .where('contexto', isEqualTo: widget.vnestContext)
          .get();

      final allVnestList = vnestSnap.docs.map((d) {
        final m = d.data();
        return {
          ...m,
          '_id': d.id,
          'verbo': m['verbo'],
          'id_ejercicio_general': m['id_ejercicio_general'] ?? d.id,
        };
      }).where((e) => (e['verbo'] ?? '').toString().isNotEmpty).toList();

      // 2️⃣ Filtrar solo los que están revisados
      final vnestList = <Map<String, dynamic>>[];
      for (final ex in allVnestList) {
        final isRevisado = await _isEjercicioRevisado(
          ex['id_ejercicio_general']?.toString(),
        );
        if (isRevisado) {
          vnestList.add(ex);
        }
      }


      final Map<String, Map<String, dynamic>> verbsDict = {
        for (final ex in vnestList)
          ex['verbo']: {
            'verbo': ex['verbo'],
            'highlight': false,
            'count': 0,
            'id_ejercicio_general': ex['id_ejercicio_general'],
          }
      };

      // 3️⃣ Resolver paciente
      final pacienteDocId = await _resolvePacienteDocId(uid: uid, email: email);

      if (pacienteDocId != null) {
        // 4️⃣ Leer asignados pendientes del contexto VNEST
        final asignadosSnap = await FirebaseFirestore.instance
            .collection('pacientes')
            .doc(pacienteDocId)
            .collection('ejercicios_asignados')
            .where('tipo', isEqualTo: 'VNEST')
            .where('contexto', isEqualTo: widget.vnestContext)
            .where('personalizado', isEqualTo: true)
            .where('estado', isEqualTo: 'pendiente')
            .get();

        final pendientesIds = asignadosSnap.docs
            .map((d) => (d.data()['id_ejercicio'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet();

        if (pendientesIds.isNotEmpty) {
          final verbosPendientesCount = <String, int>{};
          for (final ex in vnestList) {
            final ids = {ex['_id'], ex['id_ejercicio_general']}
                .whereType<String>()
                .toSet();
            if (ids.any((id) => pendientesIds.contains(id))) {
              final verbo = ex['verbo'];
              if (verbo is String && verbo.isNotEmpty) {
                verbosPendientesCount[verbo] = (verbosPendientesCount[verbo] ?? 0) + 1;
              }
            }
          }
          for (final vb in verbosPendientesCount.keys) {
            if (verbsDict.containsKey(vb)) {
              verbsDict[vb]!['highlight'] = true;
              verbsDict[vb]!['count'] = verbosPendientesCount[vb];
            }
          }
        }
      }

      setState(() {
        verbs = verbsDict.values.toList();
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  // ============================
  // 🔹 Obtener ejercicio directamente desde Firestore
  // ============================
  Future<void> openExercise(String verbo) async {
    setState(() {
      loadingExercise = true;
      error = null;
    });

    try {
      final registerVM = Provider.of<RegisterViewModel>(context, listen: false);
      final userId = registerVM.userId;
      final fs = FirebaseFirestore.instance;

      final pacienteRef = fs.collection("pacientes").doc(userId);
      final asignadosRef = pacienteRef.collection("ejercicios_asignados");

      // ========== Helpers ==========
      Future<bool> isPersonalizedForVnestDoc(
          DocumentSnapshot<Map<String, dynamic>> vnDoc) async {
        final data = vnDoc.data() ?? {};
        final generalId = (data['id_ejercicio_general'] ?? '') as String;
        if (generalId.isEmpty) return (data['personalizado'] ?? false) == true;
        final base = await fs.collection('ejercicios').doc(generalId).get();
        if (!base.exists) return (data['personalizado'] ?? false) == true;
        final baseData = base.data() ?? {};
        return (baseData['personalizado'] ?? false) == true;
      }

      int priorityOf(Map<String, dynamic> a) {
        final p = a['prioridad'];
        if (p is int) return p;
        if (p is num) return p.toInt();
        return 999999;
      }

      // 1) Buscar asignados del contexto (tipo VNEST)
      final asignadosSnap = await asignadosRef
          .where("contexto", isEqualTo: widget.vnestContext)
          .where("tipo", isEqualTo: "VNEST")
          .get();

      final asignados = <Map<String, dynamic>>[];
      for (final d in asignadosSnap.docs) {
        final m = d.data();
        final exId = (m['id_ejercicio'] ?? '').toString();
        if (exId.isEmpty) continue;
        final vnDoc = await fs.collection('ejercicios_VNEST').doc(exId).get();
        if (!vnDoc.exists) continue;
        final vn = vnDoc.data() ?? {};
        if ((vn['verbo'] ?? '') != verbo) continue;

        final idEjercicioGeneral = vn['id_ejercicio_general']?.toString();
        final isRevisado = await _isEjercicioRevisado(idEjercicioGeneral);
        if (!isRevisado) continue;

        bool personalizado = (m['personalizado'] ?? false) == true;
        if (!personalizado) {
          personalizado = await isPersonalizedForVnestDoc(vnDoc);
        }

        asignados.add({
          ...m,
          '_vn': vn,
          '_vnId': vnDoc.id,
          '_personalizado': personalizado,
        });
      }

      // 2) Pendientes: personalizados primero, luego prioridad asc
      final pendientes = asignados.where((e) => e['estado'] == 'pendiente').toList()
        ..sort((a, b) {
          final ap = (a['_personalizado'] == true) ? 0 : 1;
          final bp = (b['_personalizado'] == true) ? 0 : 1;
          if (ap != bp) return ap - bp;
          return priorityOf(a).compareTo(priorityOf(b));
        });

      if (pendientes.isNotEmpty) {
        final chosen = pendientes.first;
        final vn = Map<String, dynamic>.from(chosen['_vn'] as Map);
        final vnId = chosen['_vnId'] as String;

        Navigator.pushNamed(context, '/vnest-action', arguments: {
          ...vn,
          'context': widget.vnestContext,
          'verbo': verbo,
          'id_ejercicio_general': vn['id_ejercicio_general'] ?? vnId,
        });
        return;
      }

      // 3) Buscar VNEST del verbo en el contexto (solo revisados)
      final allVnestSnap = await fs
          .collection('ejercicios_VNEST')
          .where('contexto', isEqualTo: widget.vnestContext)
          .where('verbo', isEqualTo: verbo)
          .get();

      final vnestRevisadosDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in allVnestSnap.docs) {
        final data = doc.data();
        final idEjercicioGeneral = data['id_ejercicio_general']?.toString();
        final isRevisado = await _isEjercicioRevisado(idEjercicioGeneral);
        if (isRevisado) {
          vnestRevisadosDocs.add(doc);
        }
      }

      if (vnestRevisadosDocs.isEmpty) {
        throw Exception("No se encontró ejercicio revisado de '$verbo' en este contexto.");
      }

      final asignadosIds =
          asignadosSnap.docs.map((d) => d.data()['id_ejercicio'].toString()).toSet();
      final noAsignadosDocs =
          vnestRevisadosDocs.where((d) => !asignadosIds.contains(d.id)).toList();

      Future<List<DocumentSnapshot<Map<String, dynamic>>>> sortPersonalizedFirst(
        List<DocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
        final withFlag = <Map<String, dynamic>>[];
        for (final d in docs) {
          withFlag.add({
            'doc': d,
            'personalizado': await isPersonalizedForVnestDoc(d),
          });
        }
        withFlag.sort((a, b) {
          final ap = (a['personalizado'] == true) ? 0 : 1;
          final bp = (b['personalizado'] == true) ? 0 : 1;
          return ap - bp;
        });
        return withFlag
            .map((e) => e['doc'] as DocumentSnapshot<Map<String, dynamic>>)
            .toList();
      }

      // 4) Si hay no asignados → personalizados primero
      if (noAsignadosDocs.isNotEmpty) {
        final ordered = await sortPersonalizedFirst(noAsignadosDocs);

        final chosenDoc = ordered.first;
        final chosenData = chosenDoc.data() ?? {};
        final idEjercicio = chosenDoc.id;
        final contexto = chosenData['contexto'] ?? widget.vnestContext;

        final allAsg = await asignadosRef.get();
        final prioridades = allAsg.docs
            .map((d) => d.data()['prioridad'])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList();
        final nextPriority =
            prioridades.isEmpty ? 1 : (prioridades.reduce((a, b) => a > b ? a : b) + 1);

        final personalizedFlag = await isPersonalizedForVnestDoc(chosenDoc);

        final existe = await asignadosRef.doc(idEjercicio).get();
        if (!existe.exists) {
          await asignadosRef.doc(idEjercicio).set({
            "id_ejercicio": idEjercicio,
            "contexto": contexto,
            "tipo": "VNEST",
            "estado": "pendiente",
            "prioridad": nextPriority,
            "ultima_fecha_realizado": null,
            "veces_realizado": 0,
            "fecha_asignacion": FieldValue.serverTimestamp(),
            "personalizado": personalizedFlag,
          });
        }

        Navigator.pushNamed(context, '/vnest-action', arguments: {
          ...chosenData,
          'context': widget.vnestContext,
          'verbo': verbo,
          'id_ejercicio_general':
              chosenData['id_ejercicio_general'] ?? idEjercicio,
        });
        return;
      }

      // 5) Completado más antiguo (personalizado primero)
      final completados = asignados.where((e) => e['estado'] == 'completado').toList()
        ..sort((a, b) {
          final ap = (a['_personalizado'] == true) ? 0 : 1;
          final bp = (b['_personalizado'] == true) ? 0 : 1;
          if (ap != bp) return ap - bp;
          final ta = a['ultima_fecha_realizado'];
          final tb = b['ultima_fecha_realizado'];
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return (ta as Timestamp).compareTo(tb as Timestamp);
        });

      if (completados.isNotEmpty) {
        final old = completados.first;
        final oldId = (old['id_ejercicio'] ?? '').toString();
        final oldVnDoc = await fs.collection('ejercicios_VNEST').doc(oldId).get();
        if (oldVnDoc.exists) {
          final vn = oldVnDoc.data() ?? {};
          Navigator.pushNamed(context, '/vnest-action', arguments: {
            ...vn,
            'context': widget.vnestContext,
            'verbo': verbo,
            'id_ejercicio_general':
                vn['id_ejercicio_general'] ?? oldVnDoc.id,
          });
          return;
        }
      }

      // 6) Fallback
      final fallback = vnestRevisadosDocs.first;
      final fb = fallback.data() ?? {};
      Navigator.pushNamed(context, '/vnest-action', arguments: {
        ...fb,
        'context': widget.vnestContext,
        'verbo': verbo,
        'id_ejercicio_general': fb['id_ejercicio_general'] ?? fallback.id,
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loadingExercise = false);
    }
  }

  // ============================
  // 🔹 INTERFAZ
  // ============================
  @override
  Widget build(BuildContext context) {
    final isLoading = loading || loadingExercise;
    final loadingText = loading
        ? "Cargando verbos…"
        : (loadingExercise ? "Abriendo ejercicio…" : "");

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: orange),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Selecciona un verbo",
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
          padding: const EdgeInsets.all(24),
          child: isLoading
              ? _buildLoading(loadingText)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInstructions(),
                    const SizedBox(height: 20),
                    if (error != null) _buildError(),
                    Expanded(
                      child: verbs.isEmpty
                          ? Center(
                              child: Text(
                                "No hay verbos disponibles para este contexto.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 15,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: verbs.length,
                              itemBuilder: (context, index) =>
                                  _buildVerbOption(verbs[index]),
                            ),
                    ),
                      const SizedBox(height: 16),
                      _buildNextButton(),
                    ],
                ),
        ),
      ),
    );
  }

  Widget _buildLoading(String text) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: orange,
              strokeWidth: 4,
            ),
            const SizedBox(height: 16),
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      );

  Widget _buildInstructions() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Contexto: ",
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                widget.vnestContext,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  "Elige un verbo (acción) para formar oraciones.",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => showExpandedInfo = !showExpandedInfo),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    showExpandedInfo ? Icons.info : Icons.info_outline,
                    color: orange,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          if (showExpandedInfo) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Vamos a formar oraciones completas usando este verbo. Por ejemplo, con el verbo COCINAR podemos construir: \"La mamá cocina pasta en la cocina\".",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                  if (_hasPersonalizedExercises()) ...[
                    const SizedBox(height: 10),
                    Divider(color: Colors.grey.shade300, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE57348),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              "!",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Ejercicios personalizados para ti",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );

  bool _hasPersonalizedExercises() {
    return verbs.any((v) => v['highlight'] == true && v['count'] > 0);
  }

  Widget _buildError() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error ?? "Error cargando verbos",
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: fetchVerbs,
                child: const Text(
                  "Reintentar",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );

  // ============================
  // 🔹 OPCIÓN DE VERBO
  // ============================
  Widget _buildVerbOption(Map<String, dynamic> verbData) {
    final verbo = (verbData["verbo"] ?? "").toString();
    final highlight = (verbData["highlight"] ?? false) == true;
    final count = (verbData["count"] ?? 0) as int;
    final isSelected = selectedVerb == verbo;

    return InkWell(
      onTap: () => setState(() => selectedVerb = verbo),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFE8DD)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? orange
                : highlight
                    ? const Color(0xFFFFD4C4)
                    : Colors.grey.shade300,
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: highlight
                    ? const Color(0xFFFFF0EB)
                    : const Color(0xFFFFE8DD),
                shape: BoxShape.circle,
              ),
              child: Icon(
                highlight ? Icons.lightbulb_rounded : Icons.play_arrow_rounded,
                color: orange,
                size: highlight ? 24 : 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                verbo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            if (highlight && count > 0)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFE57348),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================
  // 🔹 BOTÓN SIGUIENTE
  // ============================
  Widget _buildNextButton() {
    final isEnabled = selectedVerb != null && selectedVerb!.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEnabled && !loadingExercise
            ? () async {
                if (selectedVerb != null) {
                  await openExercise(selectedVerb!);
                }
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: orange,
          disabledBackgroundColor: orange.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
        child: Text(
          loadingExercise ? "Cargando…" : "Siguiente",
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
