# TEM — Flujo Nivel 1 vs Nivel 2

## Resumen

| Aspecto | Nivel 1 | Nivel 2 |
|---------|---------|---------|
| Pasos por estímulo | 5 | 4 |
| Score máx/estímulo | 4 pts | 5 pts |
| Score máx/sesión (10 est.) | 40 pts | 50 pts |
| Metrónomo | Pasos 1-4 | Pasos 1-2 |
| Retroceso | No | Sí (P3→P2, P4→P3) |
| Pausa temporizada | No | 6 s (P3, P4) |
| Pregunta texto | Paso 5 | Paso 4 |

---

## Nivel 1 — 5 pasos

```
P1 Escucha         | Audio 2× con metrónomo          | Sin grabación  | — pts
P2 Unísono          | Audio + paciente juntos 4×      | Graba 4        | 0/1 pt
P3 Completion       | Audio silencia a mitad 4×        | Graba 4        | 0/1 pt
P4 Repetición       | Escucha 1× → repite solo        | Graba 1        | 0/1 pt
P5 Pregunta         | Pregunta en texto → responde     | Graba 1        | 0/1 pt
```

### Flujo FSM N1

```
Estímulo → P1 → [Continuar] → P2 → eval → {pass→P3 | 4×fail→abandon}
         → P3 → eval → {pass→P4 | fail→abandon}
         → P4 → eval → {pass→P5 | fail→abandon}
         → P5 → eval → {pass→siguiente | fail→abandon}
```

---

## Nivel 2 — 4 pasos

```
P1 Introducción              | Audio 2× con golpeteo         | Sin grabación | — pts
P2 Unísono c/ desvanecimiento| Audio + fade a mitad, 2+2×    | Graba 2-4     | 0/1 pt
P3 Repetición con pausa 6s   | Audio → 6s pausa → repite solo| Graba 1       | 0/1/2 pts
P4 Pregunta con pausa 6s     | 6s pausa → pregunta texto     | Graba 1       | 0/1/2 pts
```

### Flujo FSM N2

```
Estímulo → P1 → [Continuar]
         → P2 → eval → {pass(1pt)→P3 | 4×fail→abandon}
         → P3 → eval → {pass(2pts)→P4 | fail→retroceso_P2}
         → P4 → eval → {pass(2pts)→siguiente | fail→retroceso_P3}
```

### Mecánica de retroceso

Cuando P3 o P4 fallan, se ejecuta una secuencia de retroceso:

```
P3 falla → retroceso a P2:
  ├─ P2 falla → ABANDONA estímulo
  └─ P2 pasa  → vuelve a P3:
       ├─ P3 pasa → 1 pt (no 2)
       └─ P3 falla → 0 pts, avanza a P4

P4 falla → retroceso a P3:
  ├─ P3 falla → ABANDONA estímulo
  └─ P3 pasa  → vuelve a P4:
       ├─ P4 pasa → 1 pt (no 2)
       └─ P4 falla → 0 pts, fin del estímulo
```

**Regla clave**: Un éxito tras retroceso vale **1 punto** (no 2).
El backend Python retorna `clinical_score ∈ {0, 2}` para N2.
Flutter aplica la regla de protocolo: si `isRetroceso && clinical_score > 0 → 1 pt`.

---

## Puntuación (backend ↔ Flutter)

| Capa | Responsabilidad |
|------|----------------|
| **Backend Python** (`scorer.py`) | Evaluación acústica → `clinical_score`: N1={0,1}, N2={0,2} |
| **Flutter** (`_onContinuePressed`) | Regla de protocolo: retroceso caps score a 1 |
| **Flutter** (`TemSessionViewModel`) | Acumula `sessionScore`, FSM de pasos |

---

## Avance automático de nivel

Implementado en Cloud Function `on_session_completed` (trigger/main.py):

1. Se activa cuando `sesiones_TEM/{sessionId}.status` cambia a `completed`
2. Consulta las últimas 5 sesiones completadas del mismo nivel
3. Si **todas** tienen `scorePct ≥ 90%` → avanza `pacientes/{uid}/nivel_actual`
4. Nivel máximo: 3 (no avanza más)
5. El terapeuta puede sobreescribir desde la web

**Criterios MIT (Helm-Estabrooks et al., 1989)**:
- Avance: ≥90% en 5 sesiones consecutivas con estímulos variados
- Permanencia: media últimas 3 > media 3 anteriores

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `tem_session_viewmodel.dart` | `totalSteps` dinámico, `stepBack()`, retroceso, scores 0/1/2, `maxScorePerStimulus`, `hasPauseTimer` |
| `tem_exercise_screen.dart` | Bifurcación por nivel, `_runN2Step1-4()`, `_PauseProgressBar`, `_runPauseTimer()`, retroceso en `_onContinuePressed` |
| `tem_session_summary_screen.dart` | Score relativo: "X / Y pts (Z%)" |
| `session_manager.dart` | `closeSession` escribe `maxScoreSesion` + `scorePct` |
| `trigger/main.py` | Nueva función `on_session_completed` para avance automático |

## Diagrama de estados (FSM)

```
                    ┌─ Nivel 1 ─────────────────────────────────┐
                    │  P1 → P2 → P3 → P4 → P5 → siguiente     │
                    │       ↓         ↓         ↓               │
                    │    abandon   abandon   abandon             │
                    └───────────────────────────────────────────┘

                    ┌─ Nivel 2 ─────────────────────────────────┐
                    │  P1 → P2 → P3 ──→ P4 ──→ siguiente       │
                    │       ↓    ↑ ↓    ↑ ↓                    │
                    │    abandon │fail  │fail                   │
                    │            │      │                       │
                    │            └─P2─┘ └─P3─┘  (retroceso)    │
                    │              ↓       ↓                    │
                    │           abandon  abandon (si falla)     │
                    └───────────────────────────────────────────┘
```
