import 'package:flutter/material.dart';

/// Header personalizado para todas las pantallas TEM.
///
/// Reemplaza el AppBar genérico de Flutter con un diseño sobre el fondo
/// crema (#FFF7F2) de la app: flecha atrás sutil a la izquierda, título
/// centrado en Manrope, y un widget opcional (p. ej. SpeakingIndicator)
/// a la derecha.
///
/// Cuando se proporciona [backgroundColor], el header actúa como un
/// AppBar de color sólido: gestiona automáticamente el padding de la
/// barra de estado y muestra iconos y texto en blanco.
class TemPageHeader extends StatelessWidget {
  /// Texto que se muestra centrado en el header.
  final String title;

  /// Widget opcional en el extremo derecho (p. ej. SpeakingIndicator).
  /// Si es null se reserva el mismo ancho que el botón de volver para
  /// mantener el título perfectamente centrado.
  final Widget? trailing;

  /// Si es false no se muestra el botón de volver (útil en pantallas
  /// donde no se debe navegar hacia atrás, como el resumen de sesión).
  final bool showBack;

  /// Callback al presionar la flecha. Por defecto llama Navigator.pop.
  final VoidCallback? onBack;

  /// Color de fondo del header. Cuando no es null el widget incluye el
  /// padding de la status bar y usa iconos/texto blancos para contraste.
  final Color? backgroundColor;

  const TemPageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.showBack = true,
    this.onBack,
    this.backgroundColor,
  });

  static const double _buttonSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final hasColor = backgroundColor != null;
    final fgColor = hasColor ? Colors.white : Colors.black87;
    final titleColor = hasColor ? Colors.white : const Color(0xFF2D2D2D);
    // Cuando hay color de fondo extendemos el header hasta la status bar
    final topPadding = hasColor ? MediaQuery.of(context).viewPadding.top : 0.0;

    return Container(
      color: backgroundColor,
      padding: EdgeInsets.fromLTRB(8, topPadding + 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Botón volver (o espacio vacío para mantener centrado el título)
          SizedBox(
            width: _buttonSize,
            height: _buttonSize,
            child: showBack
                ? IconButton(
                    onPressed: onBack ?? () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: fgColor,
                    iconSize: 28,
                    tooltip: 'Volver',
                  )
                : null,
          ),

          // Título centrado
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
            ),
          ),

          // Trailing (o espacio vacío simétrico al botón)
          SizedBox(
            width: _buttonSize,
            height: _buttonSize,
            child: trailing != null ? Center(child: trailing) : null,
          ),
        ],
      ),
    );
  }
}
