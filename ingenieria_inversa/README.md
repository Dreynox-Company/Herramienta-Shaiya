# Ingeniería inversa y cliente independiente

Este directorio tiene código ejecutable y evidencias reproducibles, no una
conversión automática de un PE en Dart. Hay dos líneas separadas: estudiar el
cliente original ps0032 y desarrollar un cliente nuevo reutilizando los formatos
verificados del editor. Los recursos gráficos originales se aportan localmente.

## Estructura

- `flutter_game/`: proyecto Flutter independiente, entrada propia y runner Windows
  que genera `game.exe`; no es el editor renombrado.
- `tools/inspect_client.py`: inventario PE estático, acotado y de solo lectura.
- `tools/pack_flight.dart`: empaqueta el par ANI HUMF masculino suministrado;
  rechaza jerarquías incompatibles. No modifica ANI originales.
- `tests/`: pruebas sintéticas del inventario y sus límites.
- `specs/PROTOCOL.md`: observaciones de A114/A110 y separación de hechos e hipótesis.
- `specs/FORMATS.md`: ubicación de lectores, escrituras y pruebas.
- `specs/ARCHITECTURE.md`: fronteras entre Flutter, editor y servicios nativos.

## Perfil original

SHA-256: `509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`.
Windows x86; recurso de versión `3,3,2,10`. El inventario conserva secciones,
importaciones, recursos, cadenas pertinentes y tres rangos desensamblados. Solo
con esa huella se usan direcciones del perfil. Otro PE permanece desconocido.

La entropía no prueba cifrado; las cadenas no prueban ejecución. No se han
recuperado símbolos ni todos los algoritmos, paquetes, IA, renderizador D3D9 o
variantes privadas de SAH/SAF. El informe completo del PE del usuario se incluye
en la entrega privada, no el binario propietario en el repositorio.

## Reproducir la inspección

```text
python -m venv .venv-re
.venv-re\Scripts\python -m pip install -r ingenieria_inversa\tools\requirements.txt
.venv-re\Scripts\python ingenieria_inversa\tools\inspect_client.py --client C:\Juegos\Shaiya\game.exe --out evidencia-nueva
.venv-re\Scripts\python -m unittest discover -s ingenieria_inversa\tests -v
```

No requiere administrador ni lanza, modifica, inyecta o transmite el EXE. El
informe se crea sin sobrescribir uno anterior. No se suben binarios ni DATA a CI.

## Cliente Flutter

Abre la raíz en el IDE y ejecuta `COMPILAR_CLIENTE_FLUTTER.cmd`, o sigue
`README_SUITE.md`. El código compartido está en `lib/offline_game/`. Distribuye
el nuevo `game.exe` con sus DLL y `data` del motor. No reemplaza el PE original.

Carga geometría, ANI y equipo originales; permite encuentros locales, progreso,
partidas y perfiles de escena. No es el MMORPG completo: misiones, todos los
hechizos, botín original, economía e IA no están reconstruidos exhaustivamente.
`LocalRules` contiene reglas nuestras explícitas. Los encuentros se añaden desde
el panel; no hay población automática completa de todos los mapas.

Cada ampliación necesita recurso autorizado, perfil de versión, lector acotado,
prueba de fallo, roundtrip cuando exista escritor y captura del recorrido nativo.
Un archivo desconocido queda inspeccionable sin inventar su significado. Una
pareja DDS/malla plausible no equivale a homologación UV visual. Prioridades:
biblioteca completa, población y habilidades parametrizadas, anclajes por recurso,
IA y botín, con criterios de aceptación separados.
