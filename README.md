# Herramienta Shaiya · Flutter nativo

Aplicación para Windows y Android que lee una biblioteca local DATA de Shaiya. **No usa HTML, JavaScript, WebView ni un servidor local.** El renderizador es el port Dart `three_js` sobre ANGLE; la interfaz y los lectores de formatos son Dart/Flutter.

## Ejecutar

Descarga los artefactos de un flujo de GitHub Actions que haya terminado correctamente. El ZIP de Windows contiene el EXE, sus DLL y la carpeta `data` de Flutter; conserva todos esos componentes. El APK Android es de prueba, firmado con clave de depuración, no una distribución de producción.

**No mezcles la carpeta `data` del ejecutable Flutter con la carpeta `DATA` del juego.** Mantén la biblioteca en otra ubicación. Selecciónala mediante el botón DATA. Android emplea el selector de carpetas del sistema (SAF) y permiso de solo lectura.

Para desarrollar con Flutter estable, Python 3 y las herramientas nativas de la plataforma:

```shell
python tool/prepare.py
flutter pub get
flutter test
flutter run -d windows
# En un dispositivo Android conectado:
flutter run -d <id-del-dispositivo>
```

`tool/prepare.py` genera los runners oficiales y coloca el puente Android SAF. No reemplaza lib/main.dart. Windows requiere Visual Studio con las herramientas de compilación C++ para escritorio.

## Implementación incluida

- Indexado local sin modificar DATA; resolución de rutas sin ambigüedad entre texturas con el mismo nombre.
- Catálogos de razas/arquetipos, MLT, armaduras, rostro, cabello y animaciones ANI; cambio de conjunto por sustitución completa de slots, con publicación atómica de la escena.
- Materiales de color original y decodificación DDS DXT1/3/5 y RGB. El canal de brillo de un registro Glow no se interpreta como transparencia.
- Piezas base cuando se retira equipo. **No se inventa un cuerpo desnudo:** `body001` también designa armaduras y trajes integrales. El recurso base puede conservar ropa.
- Catálogos de armas IT2 y anclaje original por arquetipo; criaturas, alas y monturas MON con animaciones disponibles; ajustes manuales de encaje del jinete y las alas.
- Laboratorio de combate con alcance, impacto único, enfriamiento, vida, respuesta de la criatura y sonidos asociados. Sus reglas son una simulación local, no las fórmulas del servidor.
- Selección de texturas originales para impactos, preescucha de sonido y música; no se afirma reproducir todas las secuencias EFT.
- Lectura de sectores de mapas exteriores WLD, alturas y objetos SMOD cercanos. Cámara orbital, zoom táctil, WASD, control táctil de desplazamiento, pausa, velocidad y recorrido temporal.
- Guardado local de apariencia, captura PNG y diagnóstico. Interfaz en español con identificadores originales de archivo para trazabilidad.

## Límites explícitos de esta revisión

Los menús enumeran registros encontrados, no combinaciones visualmente homologadas. Hay archivos dañados o variantes no interpretadas en la biblioteca. Se conservan los diagnósticos en vez de sustituirlos silenciosamente por material negro. No está implementado el cliente del juego, el combate multijugador, las colisiones con edificios, el agua, la mezcla avanzada de terreno, las mazmorras DG ni el intérprete completo EFT. Los anclajes de alas y jinete incluyen calibración manual y no se han validado para cada criatura/arquetipo. La selección automática de golpes es genérica; no equivale todavía a una tabla completa de habilidades por clase y arma.

El análisis estático y las pruebas automatizadas no sustituyen una prueba gráfica en un PC y un Android reales. Solo se consideran compilados los artefactos de una ejecución CI verde. Los recursos de juego no se incluyen en este repositorio público.

## Pruebas y auditoría

```shell
flutter test --reporter expanded
flutter analyze
# Auditor independiente de solo lectura:
dart run tool/audit_assets.dart /ruta/DATA informe.json
```

Las pruebas usan archivos sintéticos y cubren límites binarios, DDS/transparencia, selección de conjuntos, resolución de rutas y eventos de combate. La auditoría local de la biblioteca proporcionada se documenta separadamente de las pruebas de la interfaz.

## Referencias de formatos

Los lectores se contrastan con la documentación y el código del proyecto Parsec de Matías Ramírez (licencia MIT): https://github.com/matigramirez/Parsec. No se redistribuyen recursos del juego. El motor de renderizado Dart: https://github.com/Knightro63/three_js. Consulte las licencias de las dependencias en pubspec.lock.
