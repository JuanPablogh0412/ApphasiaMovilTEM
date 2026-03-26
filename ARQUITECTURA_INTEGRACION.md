# 🏗️ Guía de Arquitectura e Integración - RehabilitIA Mobile

**Versión:** 1.0.0  
**Fecha:** Marzo 2026  
**Propósito:** Documento técnico para integración y desarrollo de componentes externos

---

## 📋 Tabla de Contenidos

1. [Información General del Proyecto](#información-general-del-proyecto)
2. [Arquitectura del Sistema](#arquitectura-del-sistema)
3. [Estructura de Directorios](#estructura-de-directorios)
4. [Patrones y Convenciones](#patrones-y-convenciones)
5. [Gestión de Estado](#gestión-de-estado)
6. [Servicios y APIs](#servicios-y-apis)
7. [Base de Datos (Firestore)](#base-de-datos-firestore)
8. [Flujos de Navegación](#flujos-de-navegación)
9. [Puntos de Integración](#puntos-de-integración)
10. [Configuración y Despliegue](#configuración-y-despliegue)

---

## 📱 Información General del Proyecto

### Identificación
- **Nombre Técnico:** `aphasia_mobile`
- **Nombre Comercial:** RehabilitIA
- **Framework:** Flutter 3.41+ / Dart 3.9+
- **Propósito:** Aplicación móvil de rehabilitación del lenguaje para personas con afasia

### Plataformas Soportadas
- ✅ Android (principal)
- ✅ iOS
- ✅ Web
- ✅ Windows
- ✅ macOS
- ✅ Linux

### Dependencias Críticas
```yaml
flutter: sdk
firebase_core: ^4.1.1          # Backend principal
firebase_auth: ^6.1.0          # Autenticación
cloud_firestore: ^6.0.2        # Base de datos
provider: ^6.0.5               # State management
dio: ^5.4.0                    # HTTP client
speech_to_text: ^7.3.0         # Reconocimiento de voz
google_sign_in: ^7.2.0         # Auth con Google
shared_preferences: ^2.5.3     # Persistencia local
```

---

## 🏛️ Arquitectura del Sistema

### Patrón Arquitectónico

**Arquitectura en Capas — MVVM + Repository + Service Pattern**

```
┌─────────────────────────────────────────────────────────────┐
│                 PRESENTATION LAYER                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Screens (StatelessWidget / StatefulWidget)           │   │
│  │  • Solo construyen UI y reaccionan a input            │   │
│  │  • Leen estado del ViewModel (Consumer/listen:true)  │   │
│  │  • NO instancian Firebase, Firestore ni Http          │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────┐   │
│  │ ViewModels (ChangeNotifier + Provider)               │   │
│  │  • Contienen TODA la lógica de negocio del módulo    │   │
│  │  • Orquestan servicios inyectados por constructor    │   │
│  │  • RegisterViewModel: datos de registro multi-paso  │   │
│  │  • TemSessionViewModel: FSM + orquestación TEM      │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                   ↓  (ViewModel llama servicios)
┌─────────────────────────────────────────────────────────────┐
│                   SERVICE LAYER                             │
│  - AuthService: sesión + persistencia                       │
│  - ApiService: REST con backend externo                     │
│  - SpeechService: reconocimiento de voz                     │
│  - StimulusRepository: Firestore + Storage (TEM)           │
│  - RhythmEngine: audio + metrónomo + visemas (TEM)         │
│  - RecordingService: grabación WAV + upload (TEM)          │
│  - SessionManager: selección anti-perseveración (TEM)     │
│  Los servicios importan SOLO desde Data/Models              │
└─────────────────────────────────────────────────────────────┘
                   ↓  (Servicios leen modelos)
┌─────────────────────────────────────────────────────────────┐
│                    DATA LAYER                               │
│  Models (lib/data/models/)                                  │
│  • Clases de datos puras — sin dependencias de Flutter UI  │
│  • No importan ninguna capa superior                       │
│  • Ejemplo TEM: Viseme, LipTimeline, LipModel             │
│  Fuentes externas:                                          │
│  • Firebase Firestore / Auth / Storage                    │
│  • Backend REST (afasia.virtual.uniandes.edu.co)          │
│  • Cloud Run TEM (FastAPI + Parselmouth)                  │
│  • SharedPreferences                                       │
└─────────────────────────────────────────────────────────────┘
```

**Regla de dependencias (estricta):**
```
Presentation → Services → Data/Models
Presentation → Data/Models  (solo lectura de modelos)
❌ Prohibido: Service importa desde presentation/
❌ Prohibido: Model importa desde services/ o presentation/
```

> **Estado de adherencia:** Los módulos VNEST, SR y Registro tienen lógica de datos acoplada a las vistas (deuda técnica existente). **El módulo TEM cumple la arquitectura limpia desde Sprint 0 y sirve como modelo de referencia.**

### Características Arquitectónicas

| Aspecto | Implementación |
|---------|----------------|
| **State Management** | Provider + ChangeNotifier. Un ViewModel por módulo. |
| **Inyección de Dependencias** | Manual por constructor (sin DI framework). |
| **Navegación** | Navigator centralizado en `AppRouter`. |
| **Networking** | Dio (REST backend) + Firebase SDK (Firestore/Storage/Auth). |
| **Persistencia** | Firestore (datos clínicos) + SharedPreferences (sesión local). |
| **Modelos de datos** | `lib/data/models/` — clases puras sin dependencias de Flutter. |
| **Testing** | Tests unitarios incrementales. Objetivo: ≥80 al finalizar Sprint 3. |

---

## 📂 Estructura de Directorios

### Árbol Completo

```
Mobile-App-RehabilitIA/
├── lib/                                    [CÓDIGO FUENTE DART]
│   ├── main.dart                           [Entry point, setup Provider]
│   ├── firebase_options.dart               [Config Firebase auto-generada]
│   │
│   ├── data/                               [⭐ CAPA DE DATOS]
│   │   ├── models/                         [Modelos puros — sin Flutter UI]
│   │   │   └── tem/
│   │   │       ├── lip_viseme.dart         [Clase Viseme + tabla Visemes]
│   │   │       ├── lip_timeline.dart       [LipTimeline, LipEvent, syllabify()]
│   │   │       └── lip_model.dart          [Geometría paramétrica labios/lengua]
│   │   └── services/                       [Acceso a fuentes externas]
│   │       ├── api_service.dart            [Export condicional móvil/web]
│   │       ├── api_service_mobile.dart     [HTTP Dio para móvil]
│   │       ├── api_service_web.dart        [HTTP Dio para web]
│   │       └── speech_service.dart         [Speech-to-text]
│   │
│   ├── services/                           [⭐ CAPA DE SERVICIOS]
│   │   ├── auth_service.dart               [Auth Firebase + SharedPrefs]
│   │   └── tem/                            [Servicios del módulo TEM]
│   │       ├── stimulus_repository.dart    [Acceso Firestore/Storage]
│   │       ├── rhythm_engine.dart          [Audio + metrónomo + visemas]
│   │       ├── recording_service.dart      [Grabación WAV 16kHz + upload]
│   │       └── session_manager.dart        [Selección anti-perseveración]
│   │
│   ├── routes/                             [NAVEGACIÓN]
│   │   └── app_router.dart                 [Rutas centralizadas]
│   │
│   └── presentation/                       [⭐ CAPA DE PRESENTACIÓN]
│       ├── viewmodels/                     [ViewModels por módulo]
│       │   └── tem/
│       │       └── tem_session_viewmodel.dart  [Orquesta sesión TEM (FSM)]
│       └── screens/                        [Pantallas — solo UI]
│           ├── splash/
│           ├── landing/
│           ├── login/
│           ├── register/
│           │   └── register_viewmodel.dart     [deuda técnica: en screens/]
│           ├── menu/
│           ├── vnest/
│           ├── sr/
│           └── tem/
│               ├── lip_animation/              [Widgets de animación labial]
│               ├── tem_home_screen.dart        [Launcher de sesión]
│               ├── tem_exercise_screen.dart
│               ├── tem_calibration_screen.dart
│               ├── tem_session_summary_screen.dart
│               └── tem_history_screen.dart
```

---

## 📁 Descripción Detallada de Directorios

### `lib/presentation/screens/`
**Propósito:** Contiene toda la interfaz de usuario  
**Patrón:** Cada módulo funcional en su carpeta  
**Convención de nombrado:** `{feature}_{type}_screen.dart`

#### Módulos Existentes:

**`splash/`**
- Pantalla de carga inicial
- Verifica autenticación
- Redirige a `/login` o `/menu`

**`landing/`**
- Pantalla de bienvenida
- Opciones: Iniciar Sesión / Registrarse

**`login/`**
- Autenticación con Firebase
- Email + Password
- Integración con `AuthService`

**`register/`** ⭐ **IMPORTANTE**
- **Contiene el único ViewModel del proyecto**
- Proceso multi-paso (5 pantallas)
- `register_viewmodel.dart`: Estado global compartido
- Flujo: Main → Personal → Family → Routine → Summary

**`menu/`**
- Dashboard principal
- 3 tabs: Terapias / Personalizar / Perfil
- Bottom navigation bar

**`vnest/`**
- Ejercicios VNEST (6 pantallas)
- Flujo secuencial de 5 fases
- Comunicación entre pantallas vía `arguments`

**`sr/`**
- Ejercicios de repetición espaciada
- Reconocimiento de voz integrado
- Algoritmo de Spaced Repetition

**`personalization/`**
- Generación de ejercicios personalizados
- Consume API backend

### `lib/services/`
**Propósito:** Lógica de negocio de la aplicación  
**Acceso:** Instanciación directa en widgets

**`auth_service.dart`**
- Gestiona sesión de usuario
- Wrapper de Firebase Auth
- Persistencia en SharedPreferences
- Métodos principales:
  ```dart
  Future<bool> isUserLoggedIn()
  Future<String?> getUserId()
  Future<void> saveLoginState(String userId, String email)
  Future<void> clearLoginState()
  ```

### `lib/data/services/`
**Propósito:** Acceso a fuentes de datos externas  
**Patrón:** Export condicional para móvil/web

**`api_service.dart`**
- Punto de entrada único
- Exporta `api_service_mobile.dart` o `api_service_web.dart`

**`api_service_mobile.dart`**
- Cliente HTTP con Dio
- **IMPORTANTE:** Desactiva verificación SSL
- Base URL: `https://afasia.virtual.uniandes.edu.co/api`
- Métodos: `post()`, `get()`

**`speech_service.dart`**
- Wrapper de `speech_to_text`
- Locale: `es_ES`
- Requiere permisos de micrófono

### `lib/routes/`
**Propósito:** Navegación centralizada

**`app_router.dart`**
- Todas las rutas definidas en `generateRoute()`
- Patron: `case '/route': return MaterialPageRoute(...)`
- Paso de argumentos: `settings.arguments`

---

## 🎨 Patrones y Convenciones

### Convenciones de Código

#### Nombrado de Archivos
```
{feature}_{type}.dart
Ejemplos:
- login_screen.dart
- auth_service.dart
- register_viewmodel.dart
```

#### Nombrado de Clases
```dart
{Feature}{Type}
Ejemplos:
- LoginScreen extends StatefulWidget
- AuthService
- RegisterViewModel extends ChangeNotifier
```

#### Nombrado de Rutas
```dart
'/feature'              // Pantalla principal
'/feature-subfeature'   // Sub-pantallas
'/feature-main-success' // Variantes

Ejemplos:
'/login'
'/register-main'
'/register-personal'
'/vnest'
'/vnest-verb'
'/vnest-action'
```

### Estructura de Pantallas

**Patrón Estándar:**
```dart
class FeatureScreen extends StatefulWidget {
  const FeatureScreen({super.key});

  @override
  State<FeatureScreen> createState() => _FeatureScreenState();
}

class _FeatureScreenState extends State<FeatureScreen> {
  // 1. Definir colores constantes
  final background = const Color(0xFFFFF7F2);
  final orange = const Color(0xFFF48A63);

  // 2. Variables de estado
  bool loading = false;
  String? error;

  // 3. Inicialización
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 4. Métodos de lógica
  Future<void> _loadData() async {
    setState(() => loading = true);
    // ... lógica
    setState(() => loading = false);
  }

  // 5. Build UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: _buildAppBar(),
      body: loading ? _buildLoading() : _buildContent(),
    );
  }

  // 6. Métodos de construcción de UI
  Widget _buildAppBar() { ... }
  Widget _buildContent() { ... }
}
```

### Paleta de Colores

**Colores Principales:**
```dart
// Definir en cada pantalla como constantes
final background = const Color(0xFFFFF7F2);  // Fondo suave
final orange = const Color(0xFFF48A63);      // Naranja principal
final purple = const Color(0xFF7C3AED);      // Púrpura (personalización)
final darkText = const Color(0xFF222222);    // Texto oscuro
```

**Theme Global (main.dart):**
```dart
ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
  fontFamily: 'Poppins',
)
```

---

## 🔄 Gestión de Estado

### Provider Setup (main.dart)

```dart
runApp(
  ChangeNotifierProvider(
    create: (_) => RegisterViewModel(),
    child: const RehabilitaApp(),
  ),
);
```

### Único ViewModel Global

**`RegisterViewModel`**

**Ubicación:** `lib/presentation/screens/register/register_viewmodel.dart`

**Responsabilidades:**
- Almacenar datos del usuario autenticado
- Datos del proceso de registro
- Estado compartido entre pantallas

**Propiedades:**
```dart
// Autenticación
String userId;
String userEmail;
String email;
String password;

// Datos personales
String nombre;
String fechaNacimiento;
String lugarNacimiento;
String ciudadResidencia;

// Relaciones
List<Map<String, String>> familiares;
List<Map<String, String>> rutinas;
List<Map<String, String>> objetos;
```

**Métodos Principales:**
```dart
void setAuthData({required String email, required String password})
void updatePersonal({...})
void updateFamilia({...})
void updateRutinas({...})
void updateObjetos({...})
void setUserId(String id)
void reset()
Map<String, dynamic> buildProfileData()
```

### Acceso al ViewModel

```dart
// Lectura sin escuchar cambios (más común)
final registerVM = Provider.of<RegisterViewModel>(context, listen: false);

// Lectura con reactividad
final registerVM = Provider.of<RegisterViewModel>(context, listen: true);

// Usando Consumer (alternativa)
Consumer<RegisterViewModel>(
  builder: (context, viewModel, child) {
    return Text(viewModel.nombre);
  },
)
```

### Estado Local

**Cada pantalla gestiona su propio estado local:**
```dart
class _ScreenState extends State<Screen> {
  bool loading = false;
  String? error;
  List<dynamic> data = [];

  void _updateState() {
    setState(() {
      // Actualizar variables
    });
  }
}
```

---

## 🌐 Servicios y APIs

### AuthService

**Ubicación:** `lib/services/auth_service.dart`

**Funciones:**
- Verificar estado de autenticación
- Persistir sesión (SharedPreferences + Firebase)
- Obtener datos del usuario actual
- Cerrar sesión

**API Pública:**
```dart
class AuthService {
  Future<bool> isUserLoggedIn()
  Future<String?> getUserId()
  Future<String?> getUserEmail()
  Future<void> saveLoginState(String userId, String email)
  Future<void> clearLoginState()
  User? getCurrentUser()
}
```

**Uso:**
```dart
final authService = AuthService();
final isLogged = await authService.isUserLoggedIn();
if (isLogged) {
  final userId = await authService.getUserId();
}
```

### ApiService

**Ubicación:** `lib/data/services/api_service.dart`

**Backend:** `https://afasia.virtual.uniandes.edu.co/api`

**Configuración:**
```dart
Dio(BaseOptions(
  baseUrl: 'https://afasia.virtual.uniandes.edu.co/api',
  connectTimeout: Duration(seconds: 30),
  receiveTimeout: Duration(seconds: 120),
))
```

**⚠️ IMPORTANTE:** Desactiva verificación SSL para desarrollo

**API Pública:**
```dart
class ApiService {
  Future<Response> post(String endpoint, Map<String, dynamic> data)
  Future<Response> get(String endpoint)
}
```

**Uso:**
```dart
final apiService = ApiService();
final response = await apiService.post('/ejercicios/personalizar', {
  'contexto': 'Educación',
  'verbo': 'Estudiar',
  'userId': userId,
});
```

### SpeechService

**Ubicación:** `lib/data/services/speech_service.dart`

**Funcionalidad:** Reconocimiento de voz en español

**API Pública:**
```dart
class SpeechService {
  Future<bool> initialize()
  Future<void> startListening(Function(String) onResult)
  Future<void> stopListening()
  bool get isListening
}
```

**Uso:**
```dart
final speechService = SpeechService();
await speechService.initialize();
await speechService.startListening((recognizedText) {
  print('Usuario dijo: $recognizedText');
});
```

---

## 🗄️ Base de Datos (Firestore)

### Esquema de Colecciones

```
Firestore
├── ejercicios/                              [Ejercicios generales]
│   └── {ejercicioId}
│       ├── titulo: string
│       ├── tipo: 'VNEST' | 'SR'
│       ├── revisado: boolean                [Control de calidad]
│       └── fecha_creacion: timestamp
│
├── ejercicios_VNEST/                        [Ejercicios VNEST específicos]
│   └── {ejercicioVNESTId}
│       ├── id_ejercicio_general: string     [FK a ejercicios]
│       ├── contexto: string
│       ├── verbo: string
│       ├── pares: Array<{sujeto, objeto}>
│       ├── oraciones: Array<{donde, porque, cuando}>
│       └── revisado: boolean (denormalizado)
│
├── ejercicios_SR/                           [Ejercicios Spaced Repetition]
│   └── {ejercicioSRId}
│       ├── id_ejercicio_general: string
│       ├── pregunta: string
│       ├── rta_correcta: string
│       └── contexto: string
│
├── contextos/                               [Contextos disponibles]
│   └── {contextoId}
│       ├── contexto: string (nombre)
│       └── descripcion: string
│
└── pacientes/                               [Perfiles de pacientes]
    └── {userId}  (Firebase Auth UID)
        ├── email: string
        ├── nombre: string
        ├── fecha_nacimiento: string
        ├── lugar_nacimiento: string
        ├── ciudad_residencia: string
        ├── familiares: Array<{nombre, relacion}>
        ├── rutinas: Array<{actividad, frecuencia}>
        ├── objetos: Array<{nombre, descripcion}>
        │
        └── ejercicios_asignados/            [Subcolección]
            └── {asignacionId}
                ├── id_ejercicio: string     [ID del ejercicio específico]
                ├── tipo: 'VNEST' | 'SR'
                ├── contexto: string
                ├── personalizado: boolean
                ├── estado: 'pendiente' | 'completado'
                ├── fecha_asignacion: timestamp
                └── fecha_completado: timestamp?
```

### Reglas de Acceso

**Paciente puede:**
- ✅ Leer su propio documento en `pacientes/{userId}`
- ✅ Leer ejercicios asignados a él
- ✅ Actualizar estado de ejercicios asignados
- ✅ Leer colecciones públicas (ejercicios, contextos)

**Paciente NO puede:**
- ❌ Crear/eliminar ejercicios base
- ❌ Modificar ejercicios de otros usuarios
- ❌ Cambiar campo `revisado`

### Queries Comunes

**Obtener ejercicios asignados pendientes:**
```dart
await FirebaseFirestore.instance
  .collection('pacientes')
  .doc(userId)
  .collection('ejercicios_asignados')
  .where('estado', isEqualTo: 'pendiente')
  .get();
```

**Obtener ejercicios VNEST de un contexto:**
```dart
await FirebaseFirestore.instance
  .collection('ejercicios_VNEST')
  .where('contexto', isEqualTo: 'Educación')
  .where('revisado', isEqualTo: true)
  .get();
```

**Marcar ejercicio como completado:**
```dart
await FirebaseFirestore.instance
  .collection('pacientes')
  .doc(userId)
  .collection('ejercicios_asignados')
  .doc(asignacionId)
  .update({
    'estado': 'completado',
    'fecha_completado': FieldValue.serverTimestamp(),
  });
```

---

## 🧭 Flujos de Navegación

### Mapa de Navegación

```
/splash (SplashScreen)
  └─▶ Verifica autenticación
      ├─▶ Si autenticado: /menu
      └─▶ Si no: /login

/ (LandingScreen)
  ├─▶ Botón "Iniciar Sesión" → /login
  └─▶ Botón "Registrarse" → /register-main

/register-main
  └─▶ /register-personal
      └─▶ /register-family
          └─▶ /register-routine
              └─▶ /register-summary
                  └─▶ [Crear cuenta Firebase]
                      └─▶ /register-main-success
                          └─▶ /login

/login
  └─▶ [Autenticación exitosa]
      └─▶ /menu

/menu (MenuScreen)
  ├─▶ Tab 1: Terapias
  │   ├─▶ Botón VNEST → /vnest
  │   └─▶ Botón SR → /sr
  ├─▶ Tab 2: Personalizar → /personalize-exercises
  └─▶ Tab 3: Perfil → [Logout] → /login

/vnest (Fase 0: Selección de contexto)
  └─▶ /vnest-verb (Fase 1a: Selección de verbo)
      └─▶ /vnest-action (Fase 1b: Quién/Qué)
          └─▶ /vnest-phase2 (Fase 2: Dónde)
              └─▶ /vnest-why (Fase 2: Por qué)
                  └─▶ /vnest-when (Fase 2: Cuándo)
                      └─▶ /vnest-phase3 (Fase 3: Evaluación)
                          └─▶ /vnest-phase4 (Fase 4: Conclusión)
                              └─▶ /menu

/sr
  └─▶ [Completar ejercicios] → /menu

/personalize-exercises
  └─▶ [Generar ejercicio] → Asigna a Firestore → /menu
```

### Paso de Argumentos Entre Rutas

**Ejemplo: VNEST**
```dart
// Desde vnest_selectverb.dart
Navigator.pushNamed(context, '/vnest-action', arguments: {
  'verbo': selectedVerb,
  'pares': ejercicioPares,
  'oraciones': ejercicioOraciones,
  'context': vnestContext,
  'id_ejercicio_general': ejercicioId,
});

// En app_router.dart
case '/vnest-action':
  final args = settings.arguments as Map<String, dynamic>?;
  return MaterialPageRoute(
    builder: (_) => VnestActionSelectionScreen(exercise: args),
  );

// En vnest_actionselection.dart
class VnestActionSelectionScreen extends StatefulWidget {
  final Map<String, dynamic> exercise;
  const VnestActionSelectionScreen({required this.exercise});
}
```

---

## 🔌 Puntos de Integración

### Para Integrar Nuevas Funcionalidades

#### 1. Agregar una Nueva Pantalla

**Pasos:**
1. Crear archivo en `lib/presentation/screens/{feature}/`
2. Definir ruta en `lib/routes/app_router.dart`
3. Agregar navegación desde pantalla existente

**Ejemplo:**
```dart
// 1. Crear: lib/presentation/screens/reports/report_screen.dart
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final background = const Color(0xFFFFF7F2);
  final orange = const Color(0xFFF48A63);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(title: const Text('Reporte')),
      body: Center(child: Text('Contenido del reporte')),
    );
  }
}

// 2. Agregar en app_router.dart
case '/report':
  return MaterialPageRoute(builder: (_) => const ReportScreen());

// 3. Navegar desde otra pantalla
ElevatedButton(
  onPressed: () => Navigator.pushNamed(context, '/report'),
  child: const Text('Ver Reporte'),
)
```

#### 2. Agregar un Nuevo Servicio

**Pasos:**
1. Crear clase en `lib/services/` o `lib/data/services/`
2. Definir métodos públicos
3. Usar en widgets directamente

**Ejemplo:**
```dart
// lib/services/analytics_service.dart
class AnalyticsService {
  Future<Map<String, dynamic>> getPatientProgress(String userId) async {
    final snapshot = await FirebaseFirestore.instance
      .collection('pacientes')
      .doc(userId)
      .collection('ejercicios_asignados')
      .get();
    
    final completed = snapshot.docs
      .where((doc) => doc['estado'] == 'completado')
      .length;
    
    return {
      'total': snapshot.docs.length,
      'completed': completed,
      'pending': snapshot.docs.length - completed,
    };
  }
}

// Uso en widget
final analyticsService = AnalyticsService();
final progress = await analyticsService.getPatientProgress(userId);
```

#### 3. Extender el ViewModel

**Si necesitas estado global adicional:**

```dart
// Opción A: Agregar al RegisterViewModel existente
class RegisterViewModel extends ChangeNotifier {
  // Propiedades existentes...
  
  // Nueva funcionalidad
  Map<String, dynamic>? currentExercise;
  
  void setCurrentExercise(Map<String, dynamic> exercise) {
    currentExercise = exercise;
    notifyListeners();
  }
}

// Opción B: Crear ViewModel adicional (requiere MultiProvider)
// En main.dart
runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RegisterViewModel()),
      ChangeNotifierProvider(create: (_) => ExerciseViewModel()),
    ],
    child: const RehabilitaApp(),
  ),
);
```

#### 4. Agregar Nueva Colección Firestore

**Pasos:**
1. Diseñar esquema de datos
2. Crear índices necesarios en Firebase Console
3. Configurar reglas de seguridad
4. Implementar queries en la app

**Ejemplo:**
```dart
// Crear nueva colección: estadisticas
await FirebaseFirestore.instance
  .collection('estadisticas')
  .doc(userId)
  .set({
    'ejercicios_completados_hoy': 5,
    'racha_dias': 7,
    'ultima_sesion': FieldValue.serverTimestamp(),
  });

// Leer datos
final stats = await FirebaseFirestore.instance
  .collection('estadisticas')
  .doc(userId)
  .get();
```

#### 5. Integrar Nueva API Externa

**Pasos:**
1. Extender `ApiService` o crear servicio específico
2. Definir endpoints
3. Manejar respuestas

**Ejemplo:**
```dart
// lib/data/services/recommendation_api_service.dart
class RecommendationApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api-recomendaciones.example.com',
  ));
  
  Future<List<String>> getRecommendedExercises(String userId) async {
    final response = await _dio.get('/recommendations/$userId');
    return (response.data as List).cast<String>();
  }
}
```

### Hooks de Integración Disponibles

**Eventos del ciclo de vida:**
```dart
// Después de login exitoso
// Ubicación: login_screen.dart, línea ~145
// Agregar lógica adicional aquí

// Después de completar ejercicio
// Ubicación: sr_exersices.dart, vnest_conclusion.dart
// Llamar servicios de analytics/gamificación

// Al cerrar sesión
// Ubicación: menu_screen.dart (botón logout)
// Limpiar caché adicional
```

---

## ⚙️ Configuración y Despliegue

### Variables de Entorno

**No usa variables de entorno explícitas**, todo está hardcodeado:

```dart
// Backend API
const apiBaseUrl = 'https://afasia.virtual.uniandes.edu.co/api';

// Firebase (auto-configurado en firebase_options.dart)
```

**Para modificar:**
1. Cambiar en `lib/data/services/api_service_mobile.dart` y `api_service_web.dart`
2. Regenerar `firebase_options.dart` con FlutterFire CLI

### Configuración Firebase

**Android:**
```
android/app/google-services.json
```

**iOS:**
```
ios/Runner/GoogleService-Info.plist
```

**Web:**
Configurado en `lib/firebase_options.dart`

### Build y Despliegue

**Android:**
```bash
flutter build apk --release
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ios --release
```

**Web:**
```bash
flutter build web --release
```

**Docker:**
```bash
docker build -t rehabilitia-mobile .
docker run -p 8080:80 rehabilitia-mobile
```

### Requisitos Mínimos

**Desarrollo:**
- Flutter SDK 3.41+
- Dart SDK 3.9+
- Android Studio / Xcode (para emuladores)
- VS Code + Flutter extension

**Android:**
- Min SDK: 21 (Android 5.0)
- Target SDK: 34 (Android 14)

**iOS:**
- iOS 12.0+

---

## 🎯 Guías de Integración por Caso de Uso

### Caso 1: Agregar Nuevo Tipo de Ejercicio

**Ejemplo: Ejercicios de Memoria (ME)**

1. **Crear colección Firestore:**
```
ejercicios_ME/
  └── {ejercicioMEId}
      ├── id_ejercicio_general: string
      ├── imagen_url: string
      ├── opciones: Array<string>
      └── respuesta_correcta: string
```

2. **Crear pantalla:**
```
lib/presentation/screens/me/
  └── me_exercises_screen.dart
```

3. **Agregar ruta:**
```dart
// app_router.dart
case '/me':
  return MaterialPageRoute(builder: (_) => const MEExercisesScreen());
```

4. **Agregar al menú:**
```dart
// menu_screen.dart
_buildCard(
  title: 'Ejercicios de Memoria',
  icon: Icons.memory,
  onTap: () => Navigator.pushNamed(context, '/me'),
)
```

### Caso 2: Integrar Dashboard de Estadísticas

**Componentes necesarios:**

1. **Servicio de Analytics:**
```dart
// lib/services/analytics_service.dart
class AnalyticsService {
  Future<Map<String, dynamic>> getStatistics(String userId) async { ... }
}
```

2. **Pantalla de estadísticas:**
```dart
// lib/presentation/screens/stats/stats_screen.dart
```

3. **Agregar tab en MenuScreen:**
```dart
// Modificar `_pages` en menu_screen.dart
_pages.addAll([
  _buildTherapies(),
  _buildPersonalize(),
  _buildStats(),      // Nueva tab
  _buildProfile(),
]);
```

### Caso 3: Conectar con Sistema de Supervisión (Terapeutas)

**Arquitectura sugerida:**

```
Backend de Terapeutas (Separado)
         ↓
    Firestore (Compartido)
         ↓
   App Móvil (Pacientes)
```

**Puntos de conexión:**

1. **Lectura de asignaciones:**
```dart
// Terapeutas escriben en:
pacientes/{userId}/ejercicios_asignados/

// Pacientes leen automáticamente desde screens VNEST/SR
```

2. **Escritura de resultados:**
```dart
// Pacientes escriben en:
pacientes/{userId}/ejercicios_asignados/{asignacionId}
  - estado: 'completado'
  - fecha_completado
  - puntaje?

// Terapeutas monitorean con listeners
```

3. **Sincronización en tiempo real:**
```dart
// En cualquier pantalla
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
    .collection('pacientes')
    .doc(userId)
    .collection('ejercicios_asignados')
    .where('estado', isEqualTo: 'pendiente')
    .snapshots(),
  builder: (context, snapshot) {
    // UI reactiva a cambios
  },
)
```

---

## 📚 Recursos Adicionales

### Documentación Relevante

- **Flutter:** https://docs.flutter.dev/
- **Firebase Flutter:** https://firebase.flutter.dev/
- **Provider:** https://pub.dev/packages/provider
- **Dio:** https://pub.dev/packages/dio

### Comandos Útiles

```bash
# Obtener dependencias
flutter pub get

# Limpiar build
flutter clean

# Ver dispositivos disponibles
flutter devices

# Ejecutar en modo debug
flutter run

# Ejecutar en web
flutter run -d chrome

# Generar APK
flutter build apk

# Analizar código
flutter analyze

# Formatear código
dart format lib/

# Ver estructura de árbol de widgets
flutter devtools
```

### Herramientas Recomendadas

- **VS Code Extensions:**
  - Flutter
  - Dart
  - Awesome Flutter Snippets
  - Pubspec Assist

- **Debugging:**
  - Flutter DevTools
  - Firebase Console
  - Android Studio Logcat

---

## ✅ Checklist de Integración

Antes de integrar nuevos componentes, verifica:

- [ ] ¿La nueva funcionalidad requiere estado global? → Evaluar ViewModel
- [ ] ¿Necesita persistencia? → Firestore o SharedPreferences
- [ ] ¿Comunicación con backend externo? → Extender ApiService
- [ ] ¿Nueva pantalla? → Agregar en `screens/` + `app_router.dart`
- [ ] ¿Requiere autenticación? → Usar AuthService
- [ ] ¿Acceso a datos del usuario? → RegisterViewModel.userId/userEmail
- [ ] ¿Sigue la paleta de colores? → background, orange, purple
- [ ] ¿Usa Material 3? → ThemeData.useMaterial3
- [ ] ¿Maneja estados de carga? → loading, error variables
- [ ] ¿Tiene manejo de errores? → try-catch con feedback UI

---

## 🚨 Advertencias Importantes

### ⚠️ Limitaciones Conocidas

1. **Un solo ViewModel global:** No escala bien para apps grandes
2. **Sin testing robusto:** Solo tests básicos incluidos
3. **Lógica en widgets:** Dificulta testing unitario
4. **Sin inyección de dependencias:** Servicios instanciados manualmente
5. **SSL deshabilitado:** Solo para desarrollo, ajustar para producción

### 🔒 Consideraciones de Seguridad

1. **API Keys en código:** firebase_options.dart está en control de versiones
2. **Reglas Firestore:** Revisar permisos de lectura/escritura
3. **Validación cliente-servidor:** No confiar solo en validación cliente
4. **Datos sensibles:** No guardar contraseñas en SharedPreferences

### 🔧 Deuda Técnica Identificada

1. Refactorizar widgets monolíticos (especialmente VNEST screens)
2. Implementar tests unitarios e integración
3. Extraer lógica de negocio de StatefulWidgets
4. Implementar manejo global de errores
5. Agregar logging estructurado
6. Implementar CI/CD

---

## 📞 Contacto y Soporte

**Proyecto:** Tesis - Pontificia Universidad Javeriana  
**Institución:** Universidad de los Andes (Backend)  
**Contexto:** 8vo Semestre - Febrero 2026

---

**Última actualización:** 1 de Marzo de 2026  
**Versión del documento:** 1.0.0
