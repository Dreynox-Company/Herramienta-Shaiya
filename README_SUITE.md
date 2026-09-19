# Shaiya Suite: tres productos explícitos

## Abrir en el IDE
Abre `Shaiya-Suite.code-workspace` en VS Code, o la raíz en Android Studio.
Herramienta: `lib/main.dart`, Flutter 3.47.4 / Dart 3.13.3 y `pubspec.lock`.
Cliente independiente: `ingenieria_inversa/flutter_game`, dependencia local al
paquete raíz. Su punto de entrada es otro: no renombra el EXE de la herramienta.
Se genera su propio runner Windows y binario `game.exe`.

### Compilación
En Windows, Visual Studio con C++ de escritorio y Flutter en PATH:
```
python tool/prepare.py --platforms windows
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build windows --release
```
Para el cliente Flutter ejecuta `COMPILAR_CLIENTE_FLUTTER.cmd` o:
```
python tool/prepare_local_game.py --platforms windows
cd ingenieria_inversa/flutter_game
flutter pub get --enforce-lockfile
flutter build windows --release
```
No ejecutes únicamente el EXE aislado: entrega sus DLL y `data` de Flutter.
Esa `data` pertenece al runtime, NO es la biblioteca DATA original del juego.

## Qué comparten el editor y el cliente Flutter
Los lectores de recursos de `lib/core` y `lib/data`, renderizado de mallas
3DC/3DO, materiales, animaciones, archivos de mundo y los anclajes. El cliente
puede cargar carpeta DATA o SAH/SAF. Guarda partidas independientes, permite
recorrer escenarios y crear encuentros locales con los modelos originales.
Sus reglas de progreso/oro/pociones NO son una recuperación del servidor.
Se identifican explícitamente en `lib/offline_game/progress.dart`.

### Enlace real de edición
El icono de enlace de la barra del laboratorio **exporta un perfil de escena**.
Desde el cliente, usa «Importar escena» para seleccionar ese JSON. El cliente
lo revisa cada dos segundos, difiere su aplicación durante el combate, valida
IDs y límites y conserva el perfil anterior ante fallo. Incluye coordenadas,
equipo, alas, anclajes del jinete y cámara. Es un contrato nuestro, no un
formato que el game.exe original ya reconozca.
La edición de tablas dentro del cliente abre el mismo editor 0.6. Al volver,
recarga lo guardado y reconstruye las referencias. No convierte automáticamente
cualquier cambio de tabla en una regla de IA o habilidad implementada.

### Límites actuales del juego propio
Reconstrucción jugable de laboratorio, no el MMORPG completo. Los encuentros
se añaden desde el panel: no se promete población completa, misiones, todos los
hechizos, clima, IA de todos los monstruos, economía o multijugador. Los archivos
que no se entienden siguen siendo inspeccionables: no se interpretan inventando
campos. Las pruebas nativas usan recursos sintéticos propios y no certifican
cada combinación del material original.

## Cliente original ps0032
`native-offline` y `runtime` adaptan servicios .NET independientes. No son código
Dart descompilado del original. El binario original tiene huella
`509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`.
Su carga de archivos SAH/SAF no se ha cambiado a carpeta DATA. El selector de
carpeta/archivo corresponde al editor y al cliente Flutter. No confundirlos.
Las fuentes correspondientes a los servicios adaptados se entregan aparte
bajo su licencia GPL; se conservan la referencia upstream y manifiestos.
Los recursos DATA y el EXE propietario no se suben al repositorio.

## Ingeniería inversa
Consulta `ingenieria_inversa/README.md`, el perfil verificable del PE, las
notas de protocolo y el inventario de lectores. Los hechos comprobados,
las inferencias y las reglas creadas están separados. Un `.exe` no se transforma
automáticamente en su código fuente original ni en un proyecto Flutter completo.

## Pruebas
`flutter test`: lectores, transacciones, idiomas, movimiento, interfaz y partidas.
`python -m unittest discover -s tool/tests -v`: herramientas y empaquetado.
Para pruebas reales de ventana en Windows:
```
python tool/make_native_fixture.py C:\Temp\ShaiyaFixture
set SHAIYA_FIXTURE_PATH=C:\Temp\ShaiyaFixture
set SHAIYA_QA_PATH=C:\Temp\ShaiyaQA
flutter test integration_test/native_studio_test.dart -d windows
flutter test integration_test/local_game_test.dart -d windows
```
El material sintético nunca sustituye ni se mezcla con tu biblioteca original.
