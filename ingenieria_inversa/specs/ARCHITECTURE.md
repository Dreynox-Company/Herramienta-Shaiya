# Arquitectura de la suite

## Cliente independiente

`flutter_game/lib/main.dart` inicia `LocalGameApp`, no el editor. Su runner
genera `game.exe` propio y comparte las bibliotecas raíz. Cada sesión tiene un
`StudioScene`, recursos, reglas, progreso, guardado y referencias. Al salir se
guarda antes de cerrar la ruta. Las escenas emplean geometría y ANI de DATA.

El controlador existente temporiza alcance, impacto, animación y efectos.
`LocalRules` aporta recompensas y pociones explícitamente propias. Encuentros
manuales no equivalen a IA, población o misiones del servidor recuperadas.

## Edición compartida

El editor exporta JSON de escena; el juego observa el archivo elegido cada dos
segundos, valida límites/IDs/versión y difiere cambios en combate. Ante error
conserva/restaura el perfil anterior. No ejecuta código del JSON ni expone un
servicio remoto. Al volver del editor interno se recargan recursos guardados.
Un cambio de parámetro no crea una mecánica que el juego aún no implementa.

## Escritura

Guardar sobre SAH/SAF comprueba conflictos, prepara datos antes del índice y
mantiene información de recuperación hasta confirmar. El respaldo permanente es
opcional. Construir y extraer son operaciones separadas; no borran originales.
Los archivos desconocidos no desaparecen por carecer de nombre.

## Windows y vistas 3D

La dependencia fijada flutter_angle 0.4.2 elimina una tabla EGL estática al cerrar
una vista. `NativeView` libera normalmente texturas/contexto y restaura el enlace
en Windows para no invalidar otra vista activa. Las pruebas nativas ejercitan
cierre de previsualización y reconstrucción de otra sesión; no ocultan excepciones.

## Cliente original

`ShaiyaOffline.exe` selecciona una instalación completa con PE ps0032 conocido y
SAH/SAF. Mantiene usuarios/mundo SQLite por partida y arranca servicios loopback.
No parchea el PE ni añade lectura de carpeta DATA: eso pertenece al cliente
Flutter y al editor. Solo se detienen procesos hijos propios; un puerto ocupado
se informa sin terminar otros programas.

La entrega incluye fuente GPL correspondiente de los servicios, pines y
manifiestos. Los registros ocultan credenciales temporales. El estado nativo y
el estado Flutter permanecen separados.
