# R27 — SPK en el espacio de trabajo, cámara e identidad ShStudio

Base: a0c3ec5785551535afa74140f46664a1468f9c10 (R26).

## Fallos y correcciones

El panel principal dependía de un arquetipo Character completo. Montar un SPK
parcial por Entry ID podía funcionar en Library y aun así no exponer los recursos
en los paneles de trabajo. La pestaña Recursos es ahora independiente del rig.
El botón SPK monta el espacio de trabajo directamente; el explorador especializado
sigue disponible para AutoPerfil y el diagnóstico.

ResourceIndex enumera TODOS los registros de recurso, incluidos los bloqueados,
sin extraerlos ni leer sus payloads al construir el índice. La lista se filtra por
nombre/ruta/Entry ID y formato. Los nombres inferidos llevan ? y no se convierten
en rutas confirmadas. Indexar tipos es explícito, cancelable y conserva solamente
metadatos; ningún tipo almacenado autoriza eludir AES-GCM. Las vistas leen bajo
demanda con un presupuesto de 64 MiB, que no sustituye una auditoría completa.

MLT/ITM/MON y las tablas auto-descriptivas conservan el alias físico del Entry ID,
aunque su extensión sea .bin. Se detecta el formato y se exige el parser completo
antes de ofrecer edición estructurada. Las mallas crudas pueden verse sin una
textura asociada, utilizando un material neutro explícito. Se puede seleccionar
una textura manual para la vista. No se escribe esa elección como enlace nativo.

En catálogos con ruta sin confirmar se puede activar, EXPLÍCITAMENTE, una vista
provisional que resuelve referencias por pistas de ruta exactas y únicas. No se
confirman nombres, no se modifican catálogos por ello y no se inventan asociaciones
ambiguas. Una DATA de referencia permite confirmar bytes mediante SHA-256. La
salida propia de extracción SPK con _SPK_MANIFEST.json no sirve como prueba circular
de los nombres que fueron inferidos al extraer.

El visor ahora recibe punteros mediante una superficie Listener por encima del
renderizador (IgnorePointer en la superficie de render). No hay dos reconocedores
de arrastre compitiendo por el mismo gesto. Izquierdo orbita; derecho, medio o
Shift+izquierdo desplazan; rueda acerca/aleja; F/Home encuadran. El foco, cancelación,
touch y trackpad quedan separados del actor principal. No cambia la malla ni DATA.

## Persistencia

Se reautentica el recurso base incluso al leer un overlay. Se comprueban el índice,
Entry ID, hash base, tamaño y hash editado. La segunda edición conserva el hash del
recurso ORIGINAL y compara el hash esperado del borrador contra la versión actual.
Los payloads editados se publican por contenido en _versions; cambiar un nombre
confirmado no pierde la edición, que sigue vinculada al Entry ID. El manifiesto
se guarda con control de versión y respaldo. Un fallo no autoriza cargar bytes
sin confirmar ni borra un manifiesto ajeno. Las escrituras de una instancia se
serializan; conflictos externos se notifican y no se consideran guardados válidos.
DATA.SPK nunca se sobrescribe. Repack completo conserva sus controles existentes.

## Marca

Se utiliza el material enviado por el usuario. El icono embebido contiene sus
frames PNG originales de 16, 32, 48, 64 y 128 px, sin volver a comprimirlos. El
paquete final incluye ambos PNG originales y el ICO HQ completo en Extras/Branding.
El runner Windows carga el ICO HQ de esa carpeta; la interfaz carga los PNG de la
misma carpeta, con el emblema embebido como respaldo. No depende de servicios web.

## Pruebas y límites

Las pruebas nuevas cubren punteros de ratón reales, DPR y offset del visor,
competencia de gestos, cancelación, zoom, desplazamiento y touch; índice parcial
sin Character; edición repetida y reapertura; cambio de alias; tampering del SPK,
overlay y manifiesto; y cancelación de indexación. Windows construye un contenedor
sintético con índice AES-GCM/Zstandard y lo abre con SpkArchiveSource.open antes de
montarlo, seleccionarlo en el panel, renderizarlo y guardar dos ediciones.

Esto NO es aceptación sobre el SPK real de 50.135 recursos del usuario. El inventario
aportado proviene de R22, registra simples legibles pero 1.467 fragmentos bloqueados,
ninguna ruta confirmada y ninguna auditoría integral. No se declara recuperado ese
contenido ni cerrado el repack aceptado por game.exe. Tampoco se añade un game.exe
offline con vuelo nativo en esta revisión. Se mantienen los suplementos Flight V3
para Studio de la entrega anterior, sin retargeting implícito al rig de las alas.

El editor de recursos no sustituye un modelador de vértices. Los cambios de tablas
no publican automáticamente al servidor. Exportar los borradores antes de cerrar.
