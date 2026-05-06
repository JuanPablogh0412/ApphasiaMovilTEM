/// Claves de Firebase Storage para los audios TTS del flujo de registro.
///
/// Ruta en Storage: `tts/{voice}/{key}.mp3`
/// Ejemplo: `tts/female/register_landing_welcome.mp3`
abstract class RegisterTtsKeys {
  // ── Landing ──────────────────────────────────────────────────────────────
  /// "Bienvenido a RehabilitIA. Tu compañero para recuperar el lenguaje."
  static const String landingWelcome = 'register_landing_welcome';

  /// "Toca Registrarse para comenzar, o Iniciar sesión si ya tienes cuenta."
  static const String landingCta = 'register_landing_cta';

  // ── Paso 1: Email / Contraseña ────────────────────────────────────────────
  /// "Vamos a crear tu cuenta. Si tienes un familiar cerca, es buen momento para pedirle ayuda."
  static const String step1Intro = 'register_step1_intro';

  /// "Escribe tu correo electrónico en este campo."
  static const String step1Email = 'register_step1_email';

  /// "Escribe una contraseña de al menos seis caracteres."
  static const String step1Password = 'register_step1_password';

  /// "Cuando termines, toca el botón Continuar."
  static const String step1Continue = 'register_step1_continue';

  // ── Paso 2: Datos personales ──────────────────────────────────────────────
  /// "¡Vamos bien! Ahora cuéntanos un poco sobre ti."
  static const String step2Intro = 'register_step2_intro';

  /// Oferta de usar el micrófono / IA en paso 2.
  static const String step2VoiceOffer = 'register_step2_voice_offer';

  /// "Escribe tu nombre completo."
  static const String step2Name = 'register_step2_name';

  /// "Toca aquí para seleccionar tu fecha de nacimiento."
  static const String step2Birthdate = 'register_step2_birthdate';

  /// "Escribe la ciudad donde vives."
  static const String step2City = 'register_step2_city';

  /// "Escribe la ciudad donde naciste."
  static const String step2BirthCity = 'register_step2_birth_city';

  // ── Paso 3: Familia ───────────────────────────────────────────────────────
  /// "Ahora hablemos de las personas que más quieres."
  static const String step3Intro = 'register_step3_intro';

  /// Oferta de usar el micrófono / IA en paso 3.
  static const String step3VoiceOffer = 'register_step3_voice_offer';

  /// "Toca este botón para agregar un familiar."
  static const String step3Add = 'register_step3_add';

  // ── Paso 4: Rutinas y objetos ─────────────────────────────────────────────
  /// "Ya casi terminamos. Cuéntanos sobre tu día a día."
  static const String step4Intro = 'register_step4_intro';

  /// "Aquí puedes agregar tus rutinas diarias."
  static const String step4Rutinas = 'register_step4_rutinas';

  /// "Aquí puedes agregar objetos importantes para ti."
  static const String step4Objetos = 'register_step4_objetos';

  /// Oferta de usar el micrófono / IA en paso 4.
  static const String step4VoiceOffer = 'register_step4_voice_offer';

  // ── Paso 5: Resumen ───────────────────────────────────────────────────────
  /// "Revisa tu información. Si todo está correcto, toca Finalizar."
  static const String step5Intro = 'register_step5_intro';

  /// "Toca este botón para completar tu registro."
  static const String step5Confirm = 'register_step5_confirm';
}
