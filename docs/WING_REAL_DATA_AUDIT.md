# Wing real DATA audit · Shaiya Studio 0.6.22

Fuente real auditada: `Character.rar` suministrado por el usuario. El archivo
contiene la carpeta `Wing/`, que corresponde a
`DATA_Español/Character/Wing/` cuando se monta dentro del DATA completo.

## Wing.MON real

- ruta: `Character/Wing/Wing.MON`
- firma: **MO4**
- bytes: 24,540
- SHA-256:
  `5fb05afe456e158f4343a904d6192efe427b9c764a058bd6be6afc688a3da94b`
- registros: **81**
- flags: 76 × 255 y 5 × 180
- partes: 81 (una por registro en esta fuente)
- altura observada: 0.43381977 a 1.58216310
- 25 registros contienen cola opaca no vacía;
- la cola opaca alcanza hasta 16 elementos de 8 bytes.

### Slots reales

Los 81 registros contienen 729 slots ANI:

- 230 referencias ANI concretas;
- **499 valores `LOAD`**;
- 0 strings ANI vacíos.

Además:

- 324/324 slots de sonido = `LOAD`;
- 324/324 slots de efecto = `LOAD`;
- 81/81 efectos adjuntos MO4 = `LOAD`.

Esto confirma con el **Wing.MON real** que `LOAD` es un sentinel nativo del
formato, no un nombre de archivo perdido. Studio ahora lo reconoce, lo preserva
y permite restaurarlo explícitamente en ANI/sonido/efecto/adjunto.

## Recursos Wing presentes en Character.rar

La carpeta suministrada contiene:

- 22 × `.3DC`;
- 32 × `.ANI`;
- 22 × `.DDS`;
- 1 × `Wing.MON`.

### ANI

Los **32/32 ANI** presentes se parsearon completos con las mismas reglas de
`ClipData.parse`:

- todos usan cabecera `ANI_V2`;
- 0 jerarquías inválidas;
- rigs desde 26 hasta 68 huesos;
- duración observada: 1.3333 s a 2.6667 s;
- 67,406 claves de rotación;
- 0 claves de traslación en este corpus Wing.

### 3DC

Las **22/22 mallas 3DC** se parsearon hasta EOF con las reglas de
`MeshData.skinned`:

- 0 pesos a huesos inexistentes;
- 0 matrices de enlace usadas inválidas;
- 44,074 vértices;
- 56,616 triángulos;
- rango de 564 a 5,990 vértices por recurso.

Por tanto, para estas alas, la lectura 3DC/ANI ya está validada con archivos
reales. El trabajo pendiente de geometría es autoría/writer si se quiere
hornear escala/espejo en el binario.

## Referencias ausentes en la copia suministrada

`Wing.MON` tiene 81 registros, mientras `Character.rar` solo contiene los
recursos visuales de una parte del catálogo. Studio detectó, sin sustituirlos:

- 95 referencias ANI concretas ausentes;
- 35 referencias de malla 3DC ausentes;
- 35 referencias de textura ausentes.

Los primeros grupos ausentes comienzan a partir de alas como
`china_8yx_wing_18_*`, `wing_19_*`, `wing_20_*` y posteriores.

Esto no invalida el parser: demuestra que **el archivo MON real referencia un
catálogo mayor que el subconjunto de recursos incluido en este RAR**. Studio
ahora lo muestra como diagnóstico de DATA y no inventa una asociación por
nombre parecido.

## Animación funcional de alas en Studio

El contrato real confirmado queda separado en dos capas:

1. **Wing.MON** decide qué ANI usa el modelo de ala para caminar/correr,
   ataques, caída, respirar, daño y reposo, incluyendo `LOAD`.
2. **Flight V3** anima el cuerpo del personaje y las transiciones de
   vuelo/combate; no reemplaza el rig del ala.

La sincronización automática del ala respeta los one-shot de ataque/daño/caída
y no los pisa inmediatamente con hover/cruise.

## Posicionamiento

El posicionamiento del ala no está dentro de Wing.MON. Se mantiene en
`ExcelXml/WingPosition.xml`, ya auditado por separado como SpreadsheetML real
con 48 perfiles y:

- `BONE_IDX`;
- rotación X/Y/Z;
- izquierda/derecha;
- arriba/abajo;
- frente/espalda.

## Gate de certificación final

Con esta auditoría quedan cerrados **parser y estructura real de Wing.MON,
Wing ANI y Wing 3DC**. Todavía falta ejecutar el build Windows sobre la DATA
completa y validar visualmente en `game.exe ps0032` una muestra representativa
de alas, incluyendo guardado/reapertura del MON y del WingPosition.
