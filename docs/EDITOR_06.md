# Shaiya Studio 0.6 · Editor de recursos

## Flujo de trabajo
Abrir DATA o SAH/SAF desde la ventana principal. El botón centrado abre un espacio de edición separado del visor. La exploración y las pestañas conservan la búsqueda y selección de cada documento. Las listas virtualizadas muestran iconos obtenidos de DATA, no ilustraciones de sustitución. El botón Columnas permite habilitar campos; los bordes de cabecera ajustan anchuras.

Doble clic abre un formulario de registro independiente, desplazable, redimensionable y minimizable. Se agrupan los campos por función. `Aplicar` confirma el borrador en memoria; `Aceptar` además cierra el formulario; `Cancelar` descarta solo el borrador. `Guardar` / Ctrl+S escribe los documentos modificados en su origen. No se aceptan modificaciones simultáneas de la misma propiedad sin revisión. Ctrl+Z y Ctrl+Y no invalidan borradores silenciosamente.

Los catálogos admiten búsqueda de nombres/identificadores, clases y facciones interpretadas según la tabla. Los NPC mantienen el espacio de nombres tipo+ID; las traducciones se unen por clave, no por posición global. Los signos, Ñ y tildes se conservan con su codificación nativa.

## Vistas y relaciones
- Los formularios de MLT, ITM/IT2 y MON/MO2/MO4 exponen los campos reconocidos por los lectores originales, con índices, texturas, anclajes y animaciones. Los bloques sin significado verificado permanecen visibles y de solo lectura.
- Ver modelo / animaciones abre una vista 3D nativa con texturas originales, rotación, rueda, encuadre, malla y clips compatibles. La búsqueda de recursos no demuestra compatibilidad UV; se conserva la revisión visual del usuario.
- Los selectores de texturas y de iconos muestran los datos locales. Las opciones enumeradas no reinterpretan enteros arbitrarios como casillas.
- Objetos, botín y habilidades relacionados navega desde inventarios de NPC a objetos, desde Grade a los candidatos de botín y desde referencias de habilidad al catálogo correspondiente. Se muestran fuentes ambiguas; las relaciones no se inventan.
- SVMAP muestra múltiples posiciones de NPC, portales y áreas. El zoom y la imagen de minimapa ayudan a localizar; las coordenadas se modifican en el formulario validado. WLD no se modifica mediante este plano.
- INI/CFG/TXT/XML se editan conservando líneas, comentarios, BOM y finales de línea. UTF-16BE/LE, UTF-8 y Windows-1252 son reconocidos. Un XML sigue requiriendo semántica válida para el juego: el editor no deduce esquemas desconocidos.

## Guardado
Guardar sobre SAH/SAF mantiene los mismos archivos. Se agregan los recursos cambiados al final del SAF; el índice SAH solo pasa a apuntarlos después de validar y vaciar las escrituras. Se conservan nombres, metadatos y la envoltura SEED/XOR reconocida. Un diario acotado permite recuperar interrupciones y rechaza índices desconocidos. El SAF puede crecer tras guardados sucesivos; Guardar copia/reempaquetar compacta.

El respaldo es opcional. No se debe abrir simultáneamente el juego ni otro editor sobre el mismo archivo. Los proveedores Android que no ofrecen reemplazo/aleatoriedad nativos permanecen limitados a exportar copias.

Construir SAH/SAF desde DATA incluye archivos regulares de extensiones desconocidas y aplica los cambios confirmados en memoria. El destino debe estar fuera de DATA. Se rechazan enlaces, rutas inseguras y nombres duplicados sin distinguir mayúsculas.

Crear/duplicar/eliminar registros está habilitado en tablas DB completas con identificadores explícitos. No se renumeran tablas clásicas con índices implícitos. Las referencias desde otros documentos no se eliminan automáticamente. Las operaciones estructurales requieren exportación del archivo completo, no parches de campos.

## Alcance comprobable
Las evidencias de cada compilación identifican commit, árbol Git, pruebas y SHA-256 de todos los componentes. El informe de Windows distingue el renderizador Flutter del cliente game.exe. No se distribuyen recursos de juego ni fuentes tipográficas independientes. No se afirma compatibilidad universal con formatos protegidos desconocidos, reproducción homologada de efectos EFT, edición de toda la lógica del servidor o enlace inmediato con el cliente nativo.
