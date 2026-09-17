# Shaiya Studio 0.3.1 · Flutter nativo

Herramienta Windows y Android para explorar una biblioteca local DATA de Shaiya. Versión **0.3.1+5**. No utiliza HTML, WebView ni servidor local; el renderizador usa Dart y ANGLE.

## Probar los programas compilados

Usa los artefactos de una ejecución satisfactoria de GitHub Actions correspondiente a esta revisión:

- **Shaiya-Studio-Windows-x64**: extrae todo el ZIP y abre `herramienta_shaiya.exe`. Conserva sus DLL y la carpeta `data` de Flutter. No necesitas Flutter, Python ni Visual Studio para ejecutar este paquete.
- **Shaiya-Studio-Android-Pruebas**: contiene `app-debug.apk`, firmado para pruebas. Una instalación anterior firmada con otra clave puede impedir la actualización directa; conserva tus configuraciones antes de cambiar de instalación. No se desinstala nada automáticamente.

Pulsa **DATA** para seleccionar la biblioteca del juego descomprimida. **No reemplaces la carpeta `data` del ejecutable con DATA del juego.** Mantén los recursos en otra ubicación. Android utiliza el selector de carpetas del sistema y permiso de solo lectura.

## Cuerpos completos al cambiar de personaje

Integra la entrega 0.3 y corrige el cuerpo incompleto al cambiar de arquetipo. El agrupador reconoce `Trousers`, `Arm`, `Body` y otras variantes. Una fila de pantalón ausente no basta para considerar que el torso contiene el cuerpo entero: se comprueba la cobertura de la geometría y, cuando no hay evidencia, se restaura la pieza base.

**Base original · cuerpo completo** está disponible para todos los arquetipos. El rostro y el cabello elegidos se conservan al cambiar de equipo dentro del mismo arquetipo. Los conjuntos no introducen un casco automáticamente ni reutilizan cargas pendientes del conjunto anterior.

### Disponibilidad real de Nude

No se identificó un perfil completo Nude para ninguno de los 20 arquetipos de la biblioteca inspeccionada. Varias bases contienen ropa o armadura: no se presentan como desnudos ni se recolorean como piel.

El programa admite perfiles Nude de mallas y texturas compatibles que existan realmente en DATA, sin añadir una capa de censura. Un perfil incompleto se rechaza y conserva el cuerpo anterior. El esquema local opcional `shaiya-studio-bodies.json` está documentado en **docs/PERFILES_CUERPO.md**. El soporte del lector no significa que esta entrega incluya los recursos Nude solicitados.

## Funciones integradas

- Razas y arquetipos, conjuntos, piezas, rostro y cabello; guardado y recuperación de apariencia.
- Lectores 3DC, 3DO, ANI, MLT, IT2, MON, DDS y variantes originales; corrección del pie nulo de ocho bytes de armas y cielos y del tratamiento del alfa.
- WASD relativo a la cámara, caminar/correr con Shift, salto con Espacio, destino mediante clic y navegación con comprobación de obstáculos. Los buscadores no activan el movimiento.
- Anclajes originales de armas, armas dobles compatibles, alas vinculadas al torso, monturas y animación coordinada del jinete.
- Combate local: hasta 24 oponentes, selección por clic o Tab, ataques 1–4, enfriamiento y vida individual; los golpes pendientes conservan el objetivo original. Sonidos locales de ataque e impacto.
- Terreno exterior completo con detalle ajustable, geometrías DG, materiales/objetos compartidos, configuración ambiental y cielo. Los recursos sin traducción mantienen nombres alternativos estables.
- Interfaz en español: biblioteca e inspector plegables/redimensionables, contexto de búsqueda y flechas arriba/abajo; controles de ataques y animación separados del visor.

## Compilar las fuentes

Solo el desarrollo requiere Flutter 3.47.4, Python 3 y los SDK nativos. `pubspec.lock` fija las dependencias. Windows requiere las herramientas C++ de escritorio de Visual Studio. Android requiere su SDK/NDK, Java y CMake 3.31 o superior.

```powershell
.\COMPILAR.ps1 -Plataforma Windows -Ejecutar
.\COMPILAR.ps1 -Plataforma Android
.\COMPILAR.ps1 -Plataforma Windows -Integracion
```

También puedes usar `python tool/build.py --platform windows --run` o `--platform android`. El proceso se detiene si falla el análisis, las pruebas o la compilación; registra la ejecución en `.build-logs` y genera paquetes en `dist`. No modifica DATA ni instala herramientas o certificados por sí mismo.

No es necesario fusionar con main para probar los artefactos de la rama de revisión.

## Evidencia y alcance

La revisión contiene **94 pruebas automatizadas Dart/Flutter** y **7 pruebas de herramientas de entrega**. Cubren lectores, texturas, cuerpos completos, selectores, movimiento, objetivos de combate y publicación segura. La auditoría local comprobó 40 estados inicial/base de 20 arquetipos y la composición lógica de 1.355 conjuntos sin regiones corporales ausentes; no es una homologación visual de todos ellos.

El workflow añade una prueba en una **ventana Windows con recursos sintéticos propios**, seguida de compilación release y prueba de arranque del EXE. Solo se consideran aprobadas las verificaciones que demuestra la ejecución CI correspondiente. La compilación Android por sí sola no acredita una prueba en un teléfono físico.

Los nombres originales del paquete están principalmente en chino: las denominaciones alternativas no se presentan como traducciones oficiales. Lapisias y elementos son una previsualización configurable, no una reproducción homologada de cada nivel del cliente. El agua avanzada y el intérprete íntegro EFT no forman parte de esta revisión. El combate utiliza reglas del laboratorio, no las del servidor.

## Recursos y licencias

No se publican las partes RAR, modelos, texturas ni sonidos originales del usuario. Consulta `THIRD_PARTY_NOTICES.md` y las licencias de las dependencias. Los recursos se leen localmente y los registros y apariencias se guardan fuera de DATA.
