# Vehicle real DATA audit · Shaiya Studio 0.6.22

Fuente real auditada: `DATA (1).zip` suministrado por el usuario.

- bytes: 120,134,155
- SHA-256: `c5b6eb7510c55f49198e4527495a9f5e86fcc80886f88e77a5454649f025870a`
- 2,797 entradas ZIP.
- La copia contiene tres raíces principales: `Item/`, `Vehicle/` y
  `Vehicle.bak/`.
- Este ZIP **no contiene** `Character/Wing/Wing.MON` ni
  `ExcelXml/WingPosition.xml`; por eso la evidencia de alas y la de monturas
  se mantienen separadas.

## Vehicle activo

`Vehicle/` contiene 951 archivos útiles:

- 168 × `.3DC`;
- 590 × `.ANI`;
- 187 × `.DDS`;
- 6 × `.MON`.

Los seis MON activos son MO4 y tienen 120 registros cada uno:

| MON | SHA-256 | bytes | registros |
| --- | --- | ---: | ---: |
| Vehicle_Hu_01.MON | `b280b941076eb7067ed8001fce3b82d12f87eb9eff42778b6a2fd90b51ec7aab` | 40,048 | 120 |
| Vehicle_El_01.MON | `a2ea784c162d11186e49cc4ba82086e02181b33bb0e22bde21a18f14cee85940` | 40,027 | 120 |
| Vehicle_Vi_01.MON | `893a7c4a7c70aa93de01cd28415c164e6ea23dbe6ce5296bceab45c7afc1801b` | 40,040 | 120 |
| Vehicle_De_01.MON | `ba23e03028aa99ef804402d2d0ee3dc975a45debf6e1a75e63e5fdef4e9aabf7` | 40,066 | 120 |
| Vehicle_Pdb_01.MON | igual a De | 40,066 | 120 |
| Vehicle_Pdw_01.MON | igual a De | 40,066 | 120 |

`Vehicle.bak/` conserva cuatro MO4 antiguos Hu/El/Vi/De con 60 registros
cada uno. La DATA activa, por tanto, duplicó el catálogo a 120 registros y
añadió recursos posteriores.

## ANI reales

Se recorrieron los **590 ANI** de `Vehicle/ANI/` aplicando las mismas reglas
estructurales que usa `ClipData.parse`:

- 590/590 parsearon completos;
- 0 jerarquías de huesos inválidas;
- 388 usan cabecera `ANI_V2` y 202 el layout clásico;
- los rigs reales varían desde 2 hasta 117 huesos;
- duración observada: 0.1667 s a 9.4667 s;
- se validaron en conjunto 750,463 claves de rotación y 79,528 claves de
  traslación;
- existen clips con frame inicial 0 y casos reales con 1, -1 y -23, por lo que
  Studio conserva lectura signed de los frames y no los interpreta como uint.

Esto confirma con archivos reales que el parser ANI de Studio cubre todo el
corpus Vehicle suministrado.

## 3DC reales

También se recorrieron las **168 mallas 3DC** activas con las reglas de
`MeshData.skinned`:

- 168/168 parsearon hasta EOF;
- todas son mallas skinned en esta copia;
- 0 pesos apuntan a huesos inexistentes;
- 0 matrices de enlace usadas resultaron inválidas;
- 453,327 vértices y 483,392 triángulos en conjunto;
- rango de 9 a 11,205 vértices por recurso.

Por tanto el frente pendiente de 3DC ya no es **lectura** de estas monturas: es
la **autoría/writer binario** necesaria si se quiere hornear escala, espejo o
cambios geométricos directamente en el recurso.

## Semántica MON confirmada con los bytes reales

Cada registro MO4 real contiene:

1. nombre;
2. flag;
3. nueve slots ANI;
4. cuatro slots de sonido;
5. cuatro slots de efecto;
6. efecto adjunto MO4;
7. lista de partes malla/textura;
8. altura;
9. contador + cola opaca de 8 bytes por elemento.

En cada MON activo:

- 1,080 slots ANI totales;
- 597 contienen una referencia ANI concreta;
- 483 contienen exactamente el sentinel **`LOAD`**;
- los 480 slots de sonido contienen `LOAD`;
- los 480 slots de efecto contienen `LOAD`;
- los 120 efectos adjuntos contienen `LOAD`;
- existen 146 partes malla/textura;
- 55–56 registros tienen cola opaca no vacía;
- la cola alcanza hasta 31/32 elementos.

Esto confirma que `LOAD` **no es un nombre de archivo faltante**. Es un valor
nativo del MON que debe conservarse y poder restaurarse desde el editor.

Shaiya Studio ahora:

- reconoce `LOAD` de forma explícita y case-insensitive;
- permite usar/restaurar `LOAD` en ANI, sonido, efecto y adjunto;
- no intenta resolver `LOAD` como `.ANI/.WAV/.EFT`;
- conserva la cola opaca byte por byte;
- vuelve a parsear el MO4 completo antes de escribir.

## Referencias realmente ausentes en esta DATA

Los MON activos contienen algunas referencias concretas que no tienen archivo
compañero dentro de este ZIP. Esto es una propiedad de la fuente auditada, no
un error inventado por Studio.

Por familia normal aparecen 25 referencias ANI ausentes; Hu tiene 29. Los
grupos repetidos incluyen, entre otros:

- `china_8yx_62_*.ANI`;
- `china_8yx_63_*.ANI`;
- `china_8yx_66_*.ANI`;
- `china_8yx_70_*.ANI`;
- en Hu, además, referencias `china_8yx_pet14_*.ANI`.

También existen unas pocas referencias de malla/textura sin compañero dentro de
la copia suministrada (5 por familia, con una textura adicional en Hu).

Studio no sustituye esas referencias por coincidencias aproximadas. El catálogo
ahora audita los MON al cargar DATA, contabiliza `LOAD` como sentinel válido y
reporta referencias concretas ausentes con ejemplos.

## Posicionamiento del jinete

En este corpus `Vehicle/` solo aparecen 3DC, ANI, DDS y MON. No hay un archivo
de asiento/pose equivalente a `WingPosition.xml`.

Esto refuerza la conclusión anterior obtenida del ExcelXml real: el ajuste 6DoF
de jinete no debe atribuirse falsamente a un XML nativo de Vehicle. La ruta
editable actual sigue siendo el **ps0032 VehiclePosition Studio Bridge**, que
aplica un delta sobre la transformación nativa del cliente y requiere
certificación visual in-game antes de declararse final.

## Gate siguiente

Con esta DATA real queda cerrado el contrato estructural de Vehicle.MON y el
sentinel `LOAD`. Aún faltan para certificación final:

1. abrir estos MON exactos en el build Windows más reciente;
2. guardar una copia modificada y reabrirla;
3. comprobar en game.exe una montura real por familia Hu/El/Vi/De;
4. validar el VehiclePosition Bridge con delta neutral y con cambios 6DoF;
5. nunca corregir automáticamente las referencias ausentes de la fuente.
