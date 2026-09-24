# Shaiya Studio 0.6.23 · World Authoring

Esta rama parte del 0.6.22 ya auditado y mantiene `main` intacto.

## Alcance

El objetivo de 0.6.23 es convertir el frente **Mundo** de Studio en autoría
estructural real para los dos formatos cuya semántica ya está suficientemente
acotada en el repositorio:

- `*.SVMAP`: reglas y placements del mapa;
- `*.WTR`: referencias de capas/texturas de terreno.

No se atribuye a estos formatos información que el parser no demuestre.

## SVMAP · edición fixed-width y lossless

El parser actual identifica:

- tamaño del mapa;
- máscara de navegación;
- `cellSize`;
- ladder records;
- áreas de mobs;
- NPC y sus rutas/waypoints;
- portales;
- áreas de spawn;
- áreas con nombres.

0.6.23 añade un documento de edición que **no reconstruye a ciegas** el archivo.
En su lugar registra offsets binarios de los campos numéricos confirmados y
modifica únicamente esos bytes.

Campos editables:

- mobs: límites del área, MonsterID y cantidad;
- NPC: tipo, ID, posición de cada waypoint y yaw;
- portales: posición, facción/ID, nivel mínimo/máximo, mapa destino y
  coordenadas destino;
- spawns: facción y bounds;
- áreas con nombre: bounds + `name1/name2`.

Se preservan byte por byte:

- máscara de navegación;
- datos de ladders todavía opacos;
- los dos enteros no identificados de cada spawn;
- cualquier cola adicional después de las estructuras conocidas.

Antes de guardar, Studio vuelve a parsear el resultado, exige conservar toda la
topología (recuentos y rutas) y además lo valida con `SvmapData.parse`.

### Limitación deliberada

0.6.23 no permite todavía insertar/eliminar NPC, mobs, portales o waypoints.
Cambiar recuentos reubicaría regiones completas del binario y requiere una
especificación más completa. La edición fixed-width permite modificar de forma
segura el corpus existente sin destruir bytes desconocidos.

## WTR · capas de terreno

El WTR auditado por parser tiene un layout completo y cerrado:

1. `tileSize` (float);
2. dos enteros conservados;
3. número de texturas;
4. strings de textura con longitud.

0.6.23 permite:

- editar `tileSize`;
- editar cada referencia DDS/TGA/BMP/PNG;
- conservar exactamente los bytes originales de strings no modificados;
- reconstruir solo cuando una referencia cambia;
- validar con dos lectores independientes antes de escribir.

Las rutas nuevas se restringen a ASCII portable y traversal-safe. Studio no
adivina Big5/CP949 para un nombre nuevo.

## Persistencia

World Authoring utiliza el mismo contrato de `Library`:

- DATA local: backup + staging + verificación + reemplazo;
- DATA.SPK autenticado: overlay;
- SPK cifrado no autenticado: fail-closed;
- SAH/SAF/SAF Android mantienen sus reglas de escritura existentes.

## Evidencia

La rama incluye fixtures sintéticos que comprueban:

- round-trip SVMAP sin cambios = bytes idénticos;
- cambios numéricos reparseables;
- preservación de máscara, ladder data, unknown spawn fields y tail;
- overflow/NaN rechazados;
- round-trip WTR byte-for-byte sin cambios;
- edición de tileSize/texturas;
- rutas inseguras o extensiones no soportadas rechazadas.

Esto prueba el contrato del editor, no reemplaza la validación con el SVMAP/WTR
exacto de la instalación del usuario.

## Próximo frente

Después de estabilizar 0.6.23:

1. conectar cambios WTR al renderer en vivo;
2. overlays visuales de portales/NPC/spawns sobre el mapa 3D;
3. editor de geometría WLD/SMOD/VANI;
4. writer 3DC/3DO antes de permitir baking real de escala/espejo;
5. continuar DATA.SPK V13 como frente independiente hasta autenticar payloads.
