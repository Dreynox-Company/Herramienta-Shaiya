# Revisión incremental 0.6.1+9: tecla física de vuelo

El laboratorio y el cliente Flutter comparten `ViewportMovementInput`.
El vuelo ahora alterna con la tecla ISO `<` situada junto a Z, identificada
por `PhysicalKeyboardKey.intlBackslash` (USB HID 0x70064). No depende del
carácter producido, así que también funciona al mantener Shift para correr.
No se utiliza Shift+coma de un teclado estadounidense como sustituto.

- Una pulsación alterna suelo/vuelo; mantenerla no repite la acción.
- Espacio conserva el salto, incluido al correr con Shift+Espacio.
- Ctrl, Alt/AltGr y Meta con esa tecla no activan vuelo.
- Los campos editables, diálogos, selectores y las ventanas inactivas no
  deben disparar acciones del visor; los eventos sintetizados se ignoran.
- Se mantiene el botón de vuelo de la interfaz.
- Se mantienen las comprobaciones de alas, personaje vivo, montura y
  compatibilidad de ANI. Cambiar la tecla no inventa clips para otros rigs.

Las pruebas del teclado usan paquetes de eventos con posiciones ISO y
caracteres diferentes. La integración Windows utiliza el código físico ISO
con un identificador lógico admitido por su simulador. No equivale a probar
un teclado físico conectado al PC del usuario.

## Alcance de esta entrega
Este incremento modifica entrada, ayuda, pruebas y números de compilación.
NO certifica descifrado SPK ni completa el rediseño del panel V3 o la revisión
visual de todas las alas. Esos trabajos siguen pendientes en esta rama.
El cliente original ps0032 y sus servicios no cambian de atajo: esta tecla
se implementa en nuestras dos aplicaciones Flutter.

## Compilar y probar en Windows

Abre la carpeta del proyecto en VS Code con las extensiones Flutter y Dart.
Ejecuta `COMPILAR_CONTROL_VUELO.cmd` desde un entorno con Flutter y Python.
El script usa la versión fijada en CI (Flutter 3.47.4), detiene la ejecución
si falla una etapa y no instala herramientas ni toca la biblioteca DATA.
Las pruebas nativas utilizan exclusivamente recursos sintéticos temporales.
No reemplaces el PE del juego original ni mezcles su DATA con la carpeta
`data` que requiere el motor Flutter.
