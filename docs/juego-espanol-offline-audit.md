# Juego.zip: compatibilidad española y base de partidas locales

## Estado de esta revisión

Es una revisión de desarrollo sobre las fuentes verificadas de Shaiya Studio 0.5.0, commit `c457c6b172e76f1b453776d8c861cf705b15cdfe`. No es una entrega del editor 0.6 terminado ni un cliente Shaiya convertido a juego offline. No se incluye un EXE nuevo. La revisión modifica el lector de nombres y añade almacenamiento local reutilizable; el servidor de juego y el menú de partidas del cliente original no están conectados.

## Cambios implementados

- `ClientLocale`: reconoce SPN/SPA/ESP/ES/SPAIN/SPANISH; respeta BOM UTF-8 y UTF-16 LE/BE en archivos de texto y utiliza Windows-1252 para los campos occidentales de las tablas españolas del cliente auditado. Una codificación elegida expresamente en el editor prevalece sobre la selección automática.
- `GameNames`: prioriza las tablas SPN de objetos, monstruos, habilidades y habilidades de NPC. La selección no cruza las tablas de la raíz con las de BinarySData. Los tipos de datos y los nombres se relacionan por sus claves, no por el orden de enumeración de los archivos.
- La biblioteca ya no excluye TXT/CSV durante el indexado, incluidos los TXT de mapas y mensajes. El filtro Android también incorpora ambas extensiones, pero no ha sido compilado ni probado en un teléfono en esta revisión.
- Las áreas del laboratorio consultan el TXT español correspondiente al mapa. Se conservan nombres originales y marcadores del juego; no se corrigen automáticamente errores de traducción presentes en los recursos.
- Se distinguen los espacios de nombres `systemmessage` y `systemmessage2`. Los IDs de mensaje con variantes contradictorias se conservan como conflictos inspeccionables; no se escoge una versión arbitrariamente ni se descarta el resto del archivo.
- `SaveStore`: crear, listar, cargar, guardar por revisiones, enviar a papelera y restaurar partidas Luz/Furia. Incluye Unicode en los nombres locales, huella del conjunto de datos, control de revisión, bloqueo entre escritores, validación del JSON, límite de 8 MiB por instantánea, comprobación SHA-256 y escrituras temporales antes de confirmar cada revisión. Las instantáneas anteriores no se sobrescriben. Los cortes se probaron mediante fallos inyectados; no es una certificación de resistencia a toda pérdida de energía o sistema de archivos.

`SaveStore` no genera por sí mismo personajes nativos ni valida todas las reglas de juego. El estado JSON debe proceder de un motor local compatible. Guardar JSON de prueba no equivale a guardar una partida real de game.exe. No hay conexión a un servidor externo, ejecución de SQL ni modificación del EXE en este módulo.

## Comprobaciones realizadas

- 282 pruebas Dart/Flutter aprobadas en el motor de pruebas Linux, incluyendo 21 pruebas del almacén de partidas y 19 del nuevo lector de idioma/catálogos.
- 27 pruebas Python aprobadas, cinco específicas del cambio de idioma del cliente.
- Análisis estático sin incidencias en los módulos y pruebas examinados.
- 198 archivos SData/SVMAP de Juego.zip auditados: 181 con esquema completo reconocido; 17 con interpretación parcial o desconocida. Los 198 conservan sus bytes al exportar sin cambios. En 44 se editó y releyó un campo de texto de prueba; eso no valida cada campo de cada registro.
- Integración del catálogo sobre la DATA real: 28.142 relaciones de objetos/nombres, 793 modelos de monstruos asociados a sus nombres, 12.060 habilidades, 774 habilidades de NPC, 145 WLD indexados y 73 archivos de áreas españolas.
- Se resuelven 2.294 mensajes del catálogo principal y 51 del secundario. Tres IDs del principal tienen dos textos distintos; se conservan ambas variantes.

La indexación de WLD es lectura de metadatos, no una prueba visual de todos esos mundos. Tampoco se certifican todas las alas/monturas ni el funcionamiento de todas las combinaciones en el cliente nativo.

## Hallazgos del cliente nativo

`game.exe` es un PE32 x86 de 5.352.488 bytes; el recurso de versión contiene `3,3,2,10`. Su SHA-256 es:

`509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`

Su código de arranque, directorio de importaciones y referencias a tablas son legibles mediante análisis estático. Esto no demuestra que todos sus subsistemas estén desofuscados. Se localizaron Direct3D9 y Winsock, referencias a Login.wld y a errores de conexión con el servidor. No se ejecutó ni alteró game.exe. La existencia de una tabla de certificado en el PE no ha sido validada criptográficamente.

Se verificó que el campo LANGUAGE de config.ini carga una variable consultada por la rutina de selección de sufijos. En este ejecutable concreto los valores 1 a 6 corresponden a GER, FRC, ITA, USA, BRZ y SPN. La configuración suministrada tiene LANGUAGE=4; para SPN corresponde 6. Las direcciones y el extracto desensamblado están en el informe técnico privado, no son una receta universal para cualquier versión.

`tool/configure_spanish_client.py` exige la huella exacta del EXE auditado. Por defecto solo inspecciona. Con `--apply` actualiza exclusivamente config.ini, preserva el resto del texto, crea un respaldo y comprueba que el origen no cambió antes de confirmar. Se probó contra una copia experimental del cliente. El archivo original se conserva intacto. Cambiar LANGUAGE no crea modo offline ni traduce cadenas que no tienen traducción en DATA.

También se encontró una comparación con el argumento `start`. La documentación pública de Imgeneus describe el inicio de su cliente de prueba contra una dirección local y dos servicios separados (Login y World). Esa documentación es referencia externa, no prueba de compatibilidad de este EXE con ese servidor. No se probaron los argumentos de credenciales ni el protocolo mediante ejecución del cliente.

Referencias técnicas externas:
- PE/COFF, Microsoft: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
- Imgeneus, proyecto de referencia: https://github.com/aosyatnik/Imgeneus
- Configuración local documentada por ese proyecto: https://github.com/aosyatnik/Imgeneus/blob/master/INSTALL.md

No se ha importado código del emulador al repositorio ni se redistribuyen sus dependencias. Su compatibilidad, licencia y compilación deben evaluarse antes de integrarlo.

## Qué contiene y qué falta en el paquete

Juego.zip contiene 7.411 archivos; 7.393 están bajo DATA. Su manifiesto de exportación describe un conjunto anterior de 47.398 recursos. La comparación encuentra 6.230 presentes con el mismo SHA-256, 41.168 omitidos y 1.163 adicionales. Esto es coherente con la omisión intencionada de archivos pesados; no se presenta como corrupción del ZIP.

33.530 rutas ausentes también aparecen en el listado del RAR anterior y 31.313 tienen el mismo tamaño. Ni la ruta ni el tamaño prueban que sean idénticas: no se ha mezclado ese contenido automáticamente con la nueva DATA. La restauración debe verificarse por SHA-256 y compatibilidad del conjunto antes de cargarlo.

Las extensiones `DBWing*`, `DBGodPower*`, `TitleData` y otras están presentes, pero varias no usan el esquema DB tradicional. Permanecen señaladas como no interpretadas o parciales. Su presencia no demuestra que este game.exe implemente todas esas mecánicas ni que haya nuevas razas jugables.

Hay dos SQL de objetos que empiezan con eliminaciones sobre Items/Items2. Se inspeccionaron como archivos; no se ejecutaron. No constituyen por sí solos una base completa con cuentas, personajes, estado de mundos y servicios de juego.

## Trabajo pendiente para el juego offline real

El flujo objetivo es: gestor de partidas -> cargar el estado local -> iniciar servicios compatibles solo en loopback -> abrir el cliente nativo contra esa sesión -> guardar un estado consistente al salir. El cliente puede conservar su renderizado y recursos sin recurrir a un parche ciego de autenticación.

Faltan verificar el protocolo con este binario, integrar la lógica local de mundo/combate/loot y sus reglas, conectar las partidas a ese estado autoritativo, sustituir o anteponer la pantalla de partidas al arranque y probar el juego real en Windows sin conexiones externas. También faltan reconstruir los recursos necesarios y comprobar las animaciones visualmente. No se ha simulado una respuesta de login válida para aparentar que el mundo funciona.

## Reproducción

Con el SDK Flutter del proyecto y las dependencias resueltas:

```text
flutter test
python -m unittest discover -s tool/tests -v
dart run tool/audit_spanish_client.dart CARPETA_JUEGO informe.json
python tool/configure_spanish_client.py CARPETA_JUEGO
```

Para una aplicación explícita del idioma, el último comando admite `--apply`; conserva un respaldo. No es necesario aplicarlo para utilizar los nombres españoles en el laboratorio.

El almacén de partidas se puede ejercitar sin red ni ejecutable de juego:

```text
dart run tool/local_games.dart CARPETA_PARTIDAS create --title "Prueba Luz" --faction luz --corpus HASH_DEL_CONJUNTO
dart run tool/local_games.dart CARPETA_PARTIDAS list
```

Son operaciones de almacenamiento. Hasta integrar el motor local no deben presentarse como partidas jugables del cliente nativo.
