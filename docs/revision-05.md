# Revisión 0.5.0 · editor de datos y anclajes

## Datos originales y límites de autoridad
La biblioteca del juego permanece abierta en modo lectura. El editor no se conecta a una base de datos ni publica cambios en un servidor. Alterar una copia del cliente no demuestra que cambie una regla de combate, un precio efectivo o el botín del servidor. El administrador debe sincronizar las fuentes que utiliza SU servidor y comprobar el resultado en un entorno de pruebas.

El editor muestra todos los campos definidos por cada esquema reconocido, con nombre original, tipo, valor y explicación disponible. No atribuye funciones a bytes desconocidos: los conserva, señala su intervalo y permite inspección/exportación. Un bloque sin interpretar no equivale a una implementación completa de ese formato.

## Segunda pantalla
Botón centrado en la barra superior del visor. Abre una página dedicada dentro de la misma ventana nativa; no es un segundo proceso ni una ventana del sistema operativo.
Biblioteca SData/SVMAP, búsqueda, filtros por categoría, clase y facción cuando el esquema proporciona esos campos; campos agrupados, edición individual y por lote, comparación de cambios, deshacer/rehacer, parches JSON, CSV y exportación verificada.
Los filtros por códigos no inventan la correspondencia de un cliente personalizado. Se conservan los nombres/códigos originales además de las etiquetas españolas.

## Monstruos, botín, oro y tiendas
DBMonsterData utiliza sus columnas reales: en el paquete examinado son 114, incluidos Money1/Money2 y 18 pares Item/ItemDropRate. No se reduce a un número fijo de espacios. Los campos de botín pueden representar grados o grupos; no se presentan necesariamente como un ItemID ni como porcentajes normalizados sin confirmar el contrato del servidor.
Item.SData incluye sus precios de compra/venta, requisitos y atributos según versión. DBItemData y otras tablas binarias exponen todos sus encabezados reales. Cash contiene los espacios originales de artículos. NPC permite vendedores y vínculos a ubicaciones SVMAP. La tabla extendida de misiones de este cliente conserva sus registros de 313 bytes como bloques no interpretados: no se edita su interior atribuyéndole recompensas arbitrarias.
Importar CSV de servidor permite revisar y editar sus columnas sin conexión a SQL. Su exportación es CSV UTF-8; no es un despliegue ni una migración SQL.

## Números y texto
Los enteros con signo admiten negativos dentro del rango exacto del tipo. Los enteros sin signo rechazan negativos ANTES de modificar el documento. Se valida desbordamiento, valores finitos y precisión; no hay conversión silenciosa de -1 a 4294967295. Precios/oro negativos emiten advertencia: que el formato los almacene no prueba que el cliente o servidor acepte una economía negativa.
Se admiten UTF-8, Windows-1252, Big5, coreano CP949 y UTF-16LE en los campos definidos. En detección automática la escritura de texto requiere elegir una codificación; no se adivina al exportar. Un carácter no representable se rechaza, no se sustituye por '?'. La exportación sin cambios conserva incluso bytes no interpretados y la codificación original.

## Extracción y par SAH/SAF
Exportar / herramientas permite extraer TODOS los registros del archivo, incluidas extensiones que el visor no muestra. Copia por bloques con progreso, cancelación, rutas seguras y hashes de los datos escritos. No requiere cargar un SAF entero en memoria.
Guardar un par nuevo reconstruye offsets/tamaños, conserva nombres binarios/versiones de entradas y relee el resultado antes de publicarlo. Los cambios se preparan en una carpeta temporal propia; nunca sobrescribe el par abierto. El resultado usa la estructura SAH estándar soportada: no promete conservar una protección privada desconocida.
Extracción y reconstrucción de carpetas se habilitan en escritorio. La salida de carpetas Android no está implementada en esta revisión; lectura de recursos y edición continúan disponibles, pero no se afirma equivalencia de todos los selectores del sistema.

## Montura, alas y aterrizaje
La pelvis del jinete sigue un punto baricéntrico de la superficie deformada de la montura; el conjunto visual se transforma por separado de la posición de navegación. Los ajustes de altura y avance son relativos a ese asiento, no la altura absoluta del personaje. Recursos que no proporcionan superficie segura muestran diagnóstico y conservan calibración manual.
El anclaje de espalda se restringe a la cadena de antecesores de la cabeza. Hereda una sola vez la transformación del jinete, la escala y su rotación local.
El suplemento separado puede incluir seis ataques montados por perfil, validados por hash, jerarquía y perfil corporal. No sustituye las animaciones originales.
El ataque solicitado durante el vuelo captura su objetivo, desciende progresivamente con límites de velocidad y aceleración y se ejecuta SOLO al tocar el suelo y conservar alcance/estado válido. Durante la guardia de combate se mantiene la locomoción terrestre. La transición combina poses existentes con desplazamiento continuo: no se presenta como una nueva animación cinematográfica verificada para cada atuendo.

## Verificación y pendientes
Las pruebas automatizadas comprueban lectura/escritura, límites, cancelación y regresión; las de la ventana Windows usan recursos sintéticos propios. La auditoría de los archivos originales comprueba invariantes y no modifica DATA.
En el paquete original: 137 archivos SData/SVMAP con conservación exacta sin cambios; 121 esquemas completos, 16 parciales/solo inspección (incluida la extensión opaca de Monster). Para las 720 entradas de monturas: 605 con superficie y movimiento verificados numéricamente, 84 requieren calibración manual y 31 tienen diagnósticos. No son 720 modelos únicos ni una certificación visual de todas las combinaciones.
Se verificaron jerarquías originales de 16 perfiles del suplemento. No hay vuelo suplementario Panda. Las recetas EFT completas, la correspondencia exacta de cada lapisia, agua avanzada y asociaciones UV ambiguas siguen sin certificación universal. No se incluyen ni fabrican texturas nude que no existen en los recursos inspeccionados.
