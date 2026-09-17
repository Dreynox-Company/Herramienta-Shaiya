# Shaiya Studio 0.3.1 · Herramienta Shaiya

Aplicación **Flutter nativa para Windows y Android** que lee una biblioteca local DATA. No usa HTML, WebView ni un servidor. La biblioteca original permanece en el equipo y no se modifica ni se sube.

## Esta entrega

Este paquete contiene **las fuentes integradas de la revisión 0.3.1+5**, las dependencias fijadas, pruebas y scripts de compilación/publicación. **No contiene un nuevo EXE ni APK de Windows/Android**. Tampoco afirma que esta revisión ya se haya publicado en GitHub.

La base remota consultada es `58d23b3a24c089a95f1ba143c6ae32f7fb3cdbfe`, rama `feat/flutter-native-studio` de `Dreynox-Company/Herramienta-Shaiya`. Se conserva el historial y se facilita un publicador con comprobación de base, integridad y árbol limpio. Nunca fusiona con `main` ni hace force-push.

## Obtener Windows y Android sin instalar Flutter localmente

Extrae las fuentes en una carpeta nueva y ejecuta **OBTENER_EXE_Y_APK.cmd** con Git y Python 3 disponibles. Solicita escribir **PUBLICAR** porque utiliza tu sesión Git habitual para publicar las fuentes en una rama nueva y autoriza el uso de GitHub Actions y una versión preliminar pública.

El iniciador crea un clon aislado, exige la base remota verificada, no hace force-push ni modifica main, y nunca copia DATA. La compilación ocurre en los runners Windows y Android de GitHub. Solo descarga resultados si la ejecución correspondiente a ese commit termina correctamente, publica ambos paquetes y sus hashes coinciden. Deja los resultados en `dist/<commit>/`.

**Esta automatización aún no se ha ejecutado remotamente para esta revisión.** Sus validadores y caminos de error tienen pruebas locales; no constituyen un EXE/APK ya construido. Requiere que tu Git pueda autenticar el push y que tu repositorio permita Actions/publicación de prereleases. Puede consumir minutos de tu cuenta. Si se interrumpe la espera, muestra un comando de reanudación que no vuelve a publicar.

## Empezar en Windows

Con Flutter, Python 3 y las herramientas C++ de escritorio de Visual Studio instaladas:

```powershell
.\COMPILAR.ps1 -Plataforma Windows -Ejecutar
```

También puedes abrir `ABRIR_WINDOWS.cmd`. El script genera los runners oficiales, conserva el código de la aplicación, resuelve las dependencias fijadas, ejecuta análisis y pruebas y compila. Solo después de un resultado correcto crea `dist/Shaiya_Studio_0_3_1_Windows.zip`.

Para Android, con el SDK/NDK y CMake 3.31 o superior ya instalados:

```powershell
.\COMPILAR.ps1 -Plataforma Android
```

Se genera un APK de **prueba** con la clave de depuración de la máquina. No es un paquete firmado para distribución comercial. La configuración de CI incluida usa Flutter 3.47.4, la versión utilizada para analizar y probar las fuentes.

Consulta **INSTRUCCIONES.md** para publicar en tu repositorio, conectar DATA y solucionar requisitos del entorno. No hace falta volver a comprimir los recursos del juego.

## Funciones integradas

- **Cuerpo base original para los 20 arquetipos:** incluye todas las piezas base de torso, piernas, brazos y pies. No convierte las prendas originales en piel. Solo presenta un perfil Nude original cuando existen todas sus referencias explícitas; no se ha identificado tal perfil completo en la biblioteca inspeccionada.
- **Corregida la ausencia de piernas al cambiar de personaje:** nombres Panda `Trousers`/`Arm` se agrupan correctamente. Un metadato ausente no basta para ocultar cuerpo; se verifica la geometría, y ante duda se conserva la pieza base.
- Catálogos de razas/arquetipos, apariencia y equipo; cambio de conjuntos por sustitución completa de slots. Rostro y cabello seleccionados se conservan. Los conjuntos no insertan un casco automáticamente; los trajes no heredan selecciones de otro conjunto. Las partes base solo se omiten si la malla del torso demuestra cobertura de esa región.
- Protección opcional de identidad para trajes que incorporan una cabeza: oculta en la vista los triángulos de cabeza detectados por sus pesos y altura, sin editar el archivo original. Se puede desactivar para inspeccionar el traje completo.
- Lectura de armas/cúpulas 3DO con la terminación original de ocho bytes nulos. Se mantienen las comprobaciones de límites y se rechazan terminaciones desconocidas. El modo IT2 `-1` es opaco: no desaparece el arma por un canal alfa de brillo.
- Armas en sus anclajes originales, animaciones por familia, doble equipo cuando la tabla define ambos anclajes. Alas vinculadas al torso y monturas con sus clips y calibración por vehículo durante la sesión.
- Movimiento respecto a la cámara, caminar/correr, salto original a pie, destino con clic, comprobación de suelo y obstáculos, ruta acotada alrededor de paredes. No se desliza un actor sin un clip compatible.
- Hasta 24 oponentes, selección con clic o Tab, vida individual y ataques vinculados al objetivo del momento del ataque. Cambiar de selección no transfiere el daño. Sonidos originales por familia y MON, con mezcla mediante un grupo limitado de reproductores.
- Mapas exteriores completos y mazmorras DG, cúpula/cielo, puntos de aparición, áreas y opciones ambientales ENV. Todos los objetos compatibles del escenario se instancian; el terreno lejano usa nivel de detalle ajustable. Los objetos repetidos comparten recursos y se ocultan fuera del encuadre mediante sus límites reales. Las banderas VANI conservan su animación de vértices.
- Nombres recuperados de SData, información original visible y denominaciones alternativas estables en español. Nunca se descarta un recurso solamente porque le falte un nombre. Las etiquetas españolas no se presentan como una traducción oficial universal del cliente.
- Previsualización de recetas de partículas SEFF con controles de nivel de mejora y elemento. **La correspondencia automática nivel/elemento → efecto exacto del cliente no está homologada**. El programa identifica esta función como previsualización y permite escoger la receta.
- Paneles compactos plegables/redimensionables, catálogos con selección y búsqueda conservadas, flechas arriba/abajo, barra de ataques y línea temporal separadas del área 3D. Capturas, apariencia guardada y diagnóstico local.

## Controles

Haz clic en el área 3D para darle el foco. **WASD** camina siguiendo la cámara; **Shift + dirección** corre; **Espacio** salta a pie. Arrastra para girar y usa la rueda o pellizco para acercar. Un clic en el suelo marca destino; un clic sobre un mob lo selecciona. **Tab** recorre objetivos, **1–4** activa los ataques disponibles, **R** reinicia el combate y **Esc** cancela el destino. El teclado no mueve al personaje mientras escribes en un buscador.

En un selector de recursos, **↑ / ↓** recorre opciones e **Intro** abre el catálogo. Los controles táctiles de caminar/correr/saltar permanecen disponibles.

## Validación de 0.3.1

- Análisis de las fuentes: sin incidencias.
- **99 pruebas Dart/Flutter**: incorpora 14 regresiones nuevas de regiones corporales, selección base, nombres Panda, identidad, sesiones antiguas y perfiles Nude completos/incompletos.
- **22 pruebas Python**: integridad, preservación de fuentes y entrega remota atada al commit correcto; rechazo de otra revisión, resultados incompletos, rutas inseguras y publicación no autorizada.
- **60 comprobaciones nativas sobre 20 arquetipos originales**: render de su cuerpo base, integridad del inicio y conservación del actor anterior al inyectar un fallo de textura. Se ejecutan con el renderizador Dart/ANGLE real y EGL/GLES3 en un framebuffer de prueba, no en una ventana Windows ni un Android físico.
- **1.354 conjuntos resueltos con mallas originales**, 2.708 verificaciones de preservación de cara/cabello y 317 restauraciones de piernas ausentes en la selección del catálogo. Una malla `elmr_constan_upper.3dc` fue rechazada por un valor no finito; permanece localizable con su diagnóstico. No es una homologación visual de los 1.354 conjuntos.
- El defecto de Panda sin piernas se reprodujo con las fuentes 0.3 entregadas, sin modificarlas, y se contrastó con las fuentes 0.3.1 usando las mismas texturas y cámara.

Las pruebas históricas de mapas, armas, salto y objetivos de 0.3 están documentadas en `docs/REVISION_0_3.md`; no se presentan como una nueva compilación de sus plataformas. **Windows/Android de 0.3.1 siguen pendientes de ejecutar el workflow o el compilador local.**

## Límites que no se ocultan

No es el cliente completo de Shaiya ni ejecuta un servidor. No están implementados el renderizado avanzado del agua, todas las secuencias EFT, todas las clases de partículas ni una correspondencia oficial completa de lapisias y elementos. La navegación es una simulación local y no la lógica exacta del servidor. Las colisiones y el piso se apoyan en las geometrías legibles; no se garantiza la transitabilidad de cada mapa de cada episodio. Algunos recursos contienen datos dañados o variantes no interpretadas y se notifican.

No todos los trajes, monturas y cuerpos se han revisado visualmente entre sí. El ajuste de las alas/jinete y la protección de cabeza integrada tienen controles de inspección. Los nombres chinos/coreanos recuperados se conservan como referencia; los nombres españoles desconocidos reciben una etiqueta alternativa, no una atribución falsa.

## Seguridad de la biblioteca

**No sustituyas la carpeta `data` que acompaña al ejecutable Flutter por DATA del juego.** Son carpetas distintas. Mantén tu biblioteca, por ejemplo, en `C:\Juegos\Shaiya\1\Proyecto Shaiya\DATA`, y selecciónala dentro del programa. En Android se usa SAF con acceso de solo lectura. Los archivos de apariencia, capturas y diagnóstico se guardan por separado.

## Código y licencias

Referencias de formatos: Parsec, Matias G. Ramirez, licencia MIT. Renderizador Dart: three_js y flutter_angle. Los avisos aplicables están en `THIRD_PARTY_NOTICES.md` y las dependencias en `pubspec.lock`. No se redistribuyen mallas, texturas, sonidos o fuentes del juego.
