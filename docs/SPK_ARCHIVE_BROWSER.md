# Explorador DATA.SPK — integración 0.6.13

Shaiya Studio trata DATA.SPK como una fuente de recursos real, no como un
archivo plano. El explorador mantiene una experiencia similar a WinRAR o al
Explorador de Windows y comparte la misma abstracción `Library` que usa el
editor de datos y la herramienta 3D.

## Interfaz

Incluye:

- árbol de carpetas;
- barra de dirección;
- búsqueda por nombre o Entry ID;
- búsqueda recursiva;
- lista de recursos con tipo, tamaño almacenado, tamaño decodificado e ID;
- propiedades técnicas y evidencia del nombre;
- inspección individual;
- extracción individual;
- extracción de carpeta;
- extracción de recursos legibles;
- extracción completa cuando todo el perfil está validado;
- inventario JSON;
- importación y persistencia de mapas de nombres;
- AutoPerfil SPK;
- descubrimiento estructural de tablas editables;
- **Preparar Studio**, que identifica tablas núcleo antes del montaje cuando es
  necesario.

## Geometría SPK v3 observada

El archivo de referencia:

- 3.351.341.186 bytes;
- 50.140 registros;
- 50.135 recursos;
- 48.668 simples;
- 1.467 fragmentados;
- 6.789 chunks auxiliares;
- índice AES-GCM + Zstandard;
- SHA-256 de índice cifrado
  `a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f`.

El índice está entendido. La capa de payloads tiene un gate independiente.

## Seguridad e integridad

DATA.SPK se abre siempre en solo lectura. El lector usa rangos y no carga los
3+ GiB en memoria. Antes de aceptar el índice valida firma, versión, offsets,
tamaños, hash del índice, AES-GCM, Zstandard, tamaño de registros, redundancias
y relaciones con la tabla auxiliar.

Los payloads no se consideran legibles porque exista una clave en un JSON.
Primero se autentican muestras reales. Los fragmentados solo se habilitan cuando
la regla de nonce y la reconstrucción completa también pasan autenticación.

Las extracciones usan staging transaccional. Un fallo o cancelación no modifica
el SPK original.

## Nombres y confianza

El índice usa Entry IDs de 64 bits. Las rutas se separan en:

- **confirmadas**: autoridad para edición;
- **inferidas fuertes**: útiles para navegación y lectura cuando el payload es
  legible;
- **inferidas aproximadas**;
- **sin resolver**.

Dos Entry IDs que intenten usar la misma ruta inferida no se montan
arbitrariamente: la ruta ambigua se excluye hasta resolverla.

Un nombre inferido no obtiene autoridad de escritura solo por coincidir en
tamaño. La confirmación puede venir de SHA-256 contra una DATA de referencia o
de un descubrimiento estructural suficientemente específico de las tablas
núcleo.

## Integración con el editor

Cuando los payloads ya están autenticados, **Descubrir tablas** valida recursos
SEED por checksum y aplica los contratos binarios existentes para localizar,
entre otras:

- `BinarySData/DBItemData.SData`;
- `BinarySData/DBMonsterData.SData`;
- `BinarySData/DBSkillData.SData`;
- `BinarySData/DBNpcSkillData.SData`;
- tablas de textos;
- set items;
- ventas/tiendas;
- transformaciones de modelos.

También intenta resolver las tablas clásicas `Item/Item.SData`,
`Monster/Monster.SData` y `Skill/Skill.SData` mediante sus perfiles
estructurales y correlación de filas.

Al pulsar **Preparar Studio**, si todavía no existen tablas núcleo confirmadas,
el descubrimiento se ejecuta antes de montar el SPK.

## Edición SPK

El editor no sobrescribe DATA.SPK. Guarda los cambios en un overlay asociado al
hash exacto del índice. Cada entrada del overlay conserva:

- Entry ID;
- SHA-256 original;
- SHA-256 del contenido editado;
- tamaño;
- fecha de actualización.

Antes de guardar, el editor relee el recurso y exige que el hash original siga
siendo el mismo. Una ruta inferida no se puede modificar hasta confirmarla.

Esto permite editar con seguridad objetos, habilidades y tablas de monstruos
sin fingir que el contenedor original ya fue reempaquetado.

## Botín, objetos y skills

El editor conserva la semántica de los contratos conocidos:

- monstruos: `Item1..Item9` + `ItemDropRate1..ItemDropRate9`; las referencias
  de drop se interpretan como Grade cuando corresponde y no como ItemID
  inventado;
- objetos: selector de `ReqOg/Og` para intercambiable, no intercambiable y el
  estado de vinculación cuando el servidor lo soporte;
- skills: niveles, daños, tiempos, efectos, requisitos y referencias tipadas;
- valores desconocidos: se conservan sin reinterpretarlos.

No se convierten tasas enteras de drop a porcentajes sin un contrato que lo
demuestre.

## Integración 3D

El catálogo 3D lee desde la misma `Library` montada sobre SPK. La prioridad
sigue siendo usar MLT/ITM/MON originales. Para archivos SPK con nombres aún
incompletos existe un fallback conservador para personajes: solo se expone un
arquetipo si hay cuerpo completo y cada parte tiene una pareja 3DC/DDS con
nombre exacto.

No se generan combinaciones aproximadas de malla/textura.

## Estado real del inventario recibido

El inventario actual sigue indicando:

- 21.360 rutas inferidas;
- 0 rutas confirmadas;
- payload simple no legible;
- payload fragmentado no legible;
- `canExtractAll = false`.

Por eso el siguiente paso real no es inventar más rutas: es ejecutar AutoPerfil
SPK con el `game.exe` de la misma instalación, volver a exportar inventario y
después usar **Preparar Studio**.

## CI

La rama mantiene gates de formato, análisis estático, regresión Flutter/Dart,
pruebas Python, integración nativa y build Windows. Hay pruebas sintéticas
específicas para validar que DBItemData, DBMonsterData y DBSkillData pueden ser
identificadas por estructura una vez que el payload está autenticado.
