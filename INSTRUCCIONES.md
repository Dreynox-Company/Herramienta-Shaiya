# Instalar, compilar y publicar · revisión 0.3

## 1. Qué descargar y dónde extraerlo

Extrae el ZIP de fuentes en una carpeta nueva, fuera de tu biblioteca DATA y fuera de un clon con cambios pendientes. Este paquete es un proyecto Flutter listo para compilar, **no un EXE/APK precompilado**. El proceso de compilación sí necesita descargar dependencias y herramientas ya autorizadas por tu SDK; el uso de los recursos en la aplicación es local.

Ejemplo de separación:

```text
C:\Proyectos\Shaiya-Studio-0.3\        Fuentes de esta entrega
C:\Juegos\Shaiya\1\Proyecto Shaiya\DATA\  Recursos originales
```

No copies tus cinco partes RAR al repositorio. La aplicación selecciona su carpeta ya extraída.

## 2. Compilar y abrir en Windows

Requisitos instalados: Flutter con su `bin` en PATH, Python 3 y Visual Studio con las herramientas C++ para escritorio Windows. Ejecuta `flutter doctor -v` para comprobar tu entorno. La versión de Flutter usada para las pruebas es 3.47.4; `pubspec.lock` fija las dependencias resueltas.

Desde la carpeta extraída, abre PowerShell:

```powershell
.\COMPILAR.ps1 -Plataforma Windows -Ejecutar
```

O abre `ABRIR_WINDOWS.cmd`. Su uso de `ExecutionPolicy Bypass` afecta solo al proceso iniciado, no cambia la política permanente de Windows. También puedes evitar PowerShell y ejecutar:

```powershell
py -3 tool\build.py --platform windows --run
```

El proceso se detiene ante un fallo y guarda el registro en `.build-logs`. No borra DATA, no instala software por sí mismo, no cambia ajustes globales y no crea un ZIP de entrega si falla el análisis, una prueba o la compilación.

Al terminar correctamente:

```text
build\windows\x64\runner\Release\herramienta_shaiya.exe
dist\Shaiya_Studio_0_3_Windows.zip
```

Conserva junto al EXE sus DLL y la carpeta `data` de Flutter. No ejecutes únicamente una copia aislada del EXE.

Dentro del programa pulsa **DATA** y selecciona tu carpeta original.

### Prueba adicional de la ventana nativa

```powershell
.\COMPILAR.ps1 -Plataforma Windows -Integracion
```

Esta opción abre el programa y prueba movimiento, selección de arma, salto, montura, alas y combate utilizando recursos sintéticos propios. No necesita tus modelos del juego. Es una prueba adicional, no una afirmación de que todos los recursos originales sean compatibles.

## 3. Generar Android

Requiere Android SDK/NDK, Java según tu instalación Flutter y CMake 3.31 o superior. El script detecta CMake en PATH o en las carpetas de SDK conocidas y solo ajusta el entorno del proceso de compilación.

```powershell
.\COMPILAR.ps1 -Plataforma Android
# Alternativa:
py -3 tool\build.py --platform android
```

Salida tras éxito:

```text
dist\Shaiya_Studio_0_3_Android_PRUEBAS.apk
```

El APK está firmado con la clave **de depuración de tu máquina**, no con una clave comercial. Puede no reemplazar un APK anterior firmado por GitHub Actions con otra clave. No desinstales una versión con configuraciones que necesites sin conservarlas antes; el script no desinstala aplicaciones ni altera el teléfono.

La biblioteca DATA debe estar extraída en una carpeta accesible del dispositivo. Selecciónala con el selector de Android. No se solicita acceso general a todo el almacenamiento.

## 4. Publicar en tu repositorio

Esta entrega no ha sido publicada automáticamente. El publicador se ejecuta únicamente cuando tú lo lanzas, usando tu propia sesión Git. Requiere un clon limpio cuyo `origin` sea exactamente `Dreynox-Company/Herramienta-Shaiya` y una identidad Git ya configurada.

```powershell
.\PUBLICAR_GITHUB.ps1 -Repositorio "C:\Proyectos\Herramienta-Shaiya"
```

Solicita escribir **PUBLICAR**. Comprueba SHA-256 de las fuentes y que `feat/flutter-native-studio` siga exactamente en la base `58d23b3a24c089a95f1ba143c6ae32f7fb3cdbfe`. Si la rama cambió desde la entrega, **se detiene** para no sobrescribir trabajo posterior.

Crea una rama nueva `feat/studio-03-integration`, añade exclusivamente las fuentes del manifiesto, crea el commit y lo envía sin force-push. No fusiona con `main`, no borra ramas y no hace stash de tus cambios. Las credenciales las gestiona Git; no se buscan ni se copian tokens.

Para crear solamente el commit local:

```powershell
.\PUBLICAR_GITHUB.ps1 -Repositorio "C:\Proyectos\Herramienta-Shaiya" -SoloLocal
```

La corrección de `.gitignore` hace que solo DATA en la raíz se ignore. `lib/data` es **código del programa**, por lo que se conserva e incluye en la publicación.

Al publicar una rama `feat/...`, el workflow incluido ejecuta pruebas y compila Windows y Android. Comprueba los resultados de esa nueva ejecución antes de dar sus binarios por válidos; los artefactos viejos de la versión 0.2 no contienen estas correcciones.

## 5. Cargar escenarios y equipo

Los mapas se eligen por su denominación visible y detalles. Se incluyen entradas sin traducción conocida mediante nombres alternativos estables. Apulune, Cloron y la cancha de fútbol se relacionan con los metadatos y la geometría del paquete inspeccionado; los IDs no se interpretan como una lista universal de todos los servidores.

Las texturas y edificios se comparten entre objetos repetidos. Un escenario grande puede tardar en prepararse; la selección anterior se conserva hasta que el escenario nuevo queda listo. Calidad ligera/equilibrada/alta regula detalle del terreno, no elimina entradas del catálogo. Los recursos incompatibles se registran en Diagnóstico.

El rostro y cabello no cambian al seleccionar un conjunto. La protección de identidad puede ocultar las partes integradas de una cabeza en un traje. Desactívala al inspeccionar el traje original íntegro o si necesitas revisar un recorte.

## 6. Alcance y pruebas

Se entregan por separado el informe de 85 pruebas automatizadas y 14 comprobaciones de renderizado original mediante EGL/GLES. No son una compilación ni una prueba física de esta versión en Windows/Android. Los scripts anteriores permiten realizar esas verificaciones en tu entorno; no afirman resultados antes de ejecutarse.

Los controles de lapisia y elementos son una **previsualización configurable de efectos**, no una reproducción homologada de cada nivel del cliente oficial. El agua avanzada y el intérprete completo de EFT siguen fuera de esta revisión. Los mensajes del programa lo indican, sin ocultar recursos ni simular falsamente que se han interpretado.
