# Auditoría DATA/ExcelXml · Shaiya Studio 0.6.22

Fuente auditada: `excelxml.zip` suministrado por el usuario el 24-09-2026.

- 46 archivos XML reales.
- `wingposition.xml` SHA-256:
  `8a2c376c898bb025550b5fe34b92a40dbbbb9e39063619cfee4756006908cd03`.
- La mayoría de tablas editables usan Excel 2003 SpreadsheetML.
- `AccessContinueEvent.xml` está malformado en la fuente recibida
  (mismatched tag); Studio lo abre en modo reparación y solo permite guardarlo
  si el XML completo vuelve a ser válido.
- El archivo más grande es `MonDeathItemWorldDrop.xml` (~25.6 MB), dentro del
  límite de 32 MiB del editor estructurado.

## Integración en Studio

`ExcelXml Lab` monta directamente `DATA/ExcelXml` desde la biblioteca activa:

- detección de Workbook/Worksheet/Table/Row/Cell/Data;
- cabeceras y filas reales, incluyendo celdas sparse con `ss:Index`;
- búsqueda por archivo/función y filtro transversal de filas;
- edición de celdas existentes sin inventar columnas;
- preservación del árbol XML, estilos, comentarios y processing instructions;
- reparseo estructural antes de guardar;
- DATA local: escritura transaccional con backup;
- DATA.SPK autenticado: overlay; nunca se modifica el SPK original;
- XML no tabular: editor textual con validación XML antes de escribir;
- XML roto: modo reparación fail-closed.

## Inventario y utilidad

| Archivo | Utilidad principal en Studio |
| --- | --- |
| AccessContinueEvent.xml | Eventos/acceso · fuente malformada, reparación validada |
| BattleField3Prize.xml | Recompensas de campo de batalla |
| chaoticsquaretype.xml | UI/configuración de Chaotic Square |
| CharWarMode.xml | Reglas de modo de guerra |
| CreateCharacterLearn.xml | Creación/tutorial de personaje |
| Events.xml | Eventos |
| fontstyleset.xml | UI: fuentes, colores, bordes y estilos |
| FoolsEvent_ChangeMonInfo.xml | Monstruos: stats/drop temporal |
| functionalpetsize.xml | Mascotas: escala y efectos |
| GeneralMoveTowns_Server.xml | Viaje/teletransporte |
| gmnoticeinfo.xml | UI: avisos GM, colores, fondo y velocidad |
| GoldDropMonster.xml | Drop de oro |
| GuildGemItem.xml | Gremio: gemas |
| healskilllist.xml | Skills de curación |
| HotTimeEvent.xml | Eventos horarios |
| InfiniteDungeonRebirth.xml | Mazmorra infinita/rebirth |
| itemaddoptiondata.xml | Objetos: opciones adicionales |
| ItemAddOptionExtraData.xml | Objetos: bonus por enchant |
| ItemBuffReUse.xml | Objetos/buffs: reutilización |
| ItemCreate.xml | Objetos: creación/recetas/probabilidad |
| ItemGiveEvent.xml | Objetos: recompensas de eventos |
| ItemUseingControll.xml | Objetos: control de uso |
| LimitationOnItemUseInMap.xml | Objetos: restricciones por mapa |
| LookAndEquipment.xml | Apariencia/equipamiento; incluye VEHICLE/PET |
| mainquest.xml | Quests principales |
| MapCountry.xml | Mundo: país/facción por mapa |
| MapLimitLv.xml | Mundo: límites de nivel |
| Marriage.xml | Matrimonio |
| MarriageReward.xml | Recompensas de matrimonio |
| MonDeathItemMapDrop.xml | Drops de monstruos por mapa |
| MonDeathItemWorldDrop.xml | Drops globales + metadata completa de objetos |
| MonitoringItemList.xml | Objetos monitorizados |
| monsterdroprate.xml | Multiplicadores/tasas de drop |
| MonsterRespawnChangeSystem.xml | Respawn dinámico de monstruos |
| NpcDisableSystem.xml | NPC: ventanas de disponibilidad |
| RandomOptionEdit.xml | Objetos: opciones aleatorias |
| RenownShop.xml | Tienda de renombre |
| StartMapChange.xml | Mundo: nombres/cambio de mapas |
| timenoticesystem.xml | Avisos/eventos programados |
| visiblepartybufskill.xml | Skills/buffs visibles de party |
| WingDecompose.xml | Alas: descomposición, grade y nivel |
| WingExpItem.xml | Alas: objetos de experiencia |
| wingposition.xml | Alas: FAMILY/JOB/SEX/BONE_IDX + transform 6DoF |
| WingSwap.xml | Alas: intercambio/recompensas |
| ymeventinfo.xml | UI/eventos: título, contenido, URL |
| ymwatershaderparams.xml | Mundo: parámetros de shader/agua por MapID |

## Frentes especializados prioritarios

### Alas

Studio ya integra de manera específica:

1. `wingposition.xml`: posición XYZ, rotación XYZ y `BONE_IDX`.
2. `Character/Wing/Wing.MON`: ANI, WAV/OGG, EFT/3DE, efecto adjunto MO4,
   partes 3DC/3DO y texturas.
3. `WingDecompose.xml`, `WingExpItem.xml` y `WingSwap.xml`: accesibles
   desde ExcelXml Lab para editar la progresión/sistemas del ala sin convertir
   esos datos en parámetros 3D falsos.
4. Flight V3: animaciones corporales de vuelo/combate verificadas por SHA y
   compatibilidad de rig, separadas del rig ANI propio de cada Wing.MON.

### Mundo

`ymwatershaderparams.xml` es especialmente útil para el laboratorio 3D:
permite inspeccionar/editar color superficial/profundo, underwater, wave density,
wave scale/speed, reflection, Fresnel, HDR y specular por `MapID`.

`StartMapChange.xml`, `MapCountry.xml` y `MapLimitLv.xml` sirven para
diagnóstico de mundo, selección de mapa y reglas de acceso.

### Monstruos y drops

`FoolsEvent_ChangeMonInfo.xml`, `MonDeathItemMapDrop.xml`,
`MonDeathItemWorldDrop.xml`, `monsterdroprate.xml` y
`MonsterRespawnChangeSystem.xml` complementan `DBMonsterData.SData`.
Studio no mezcla automáticamente tablas cliente/servidor: muestra su procedencia
para evitar que un cambio se presente como autoritativo donde no corresponde.

### Objetos

`ItemCreate.xml`, `itemaddoptiondata.xml`, `ItemAddOptionExtraData.xml`,
`RandomOptionEdit.xml`, `LimitationOnItemUseInMap.xml`, `RenownShop.xml`
y demás tablas complementan `DBItemData.SData` para recetas, probabilidades,
restricciones y recompensas.

### UI y operación

`fontstyleset.xml`, `gmnoticeinfo.xml`, `timenoticesystem.xml` y
`ymeventinfo.xml` permiten usar Studio como editor de presentación/eventos,
no solamente como visor 3D.

## Lo que no se infiere

La auditoría no encontró dentro de este `ExcelXml` una tabla nativa de asiento
de montura equivalente a `WingPosition.xml`. `LookAndEquipment.xml` clasifica
VEHICLE/PET y `functionalpetsize.xml` parametriza mascotas, pero ninguno
expone una transformación de jinete. El posicionamiento editable de montura se
mantiene explícitamente como **ps0032 Studio Bridge** hasta completar su
validación in-game; no se etiqueta como una estructura nativa original.

## DATA.SPK

ExcelXml Lab no relaja el gate del SPK. Si la biblioteca proviene de DATA.SPK,
solo puede editar recursos cuando el payload está autenticado y montado; los
cambios quedan en overlay hasta reconstruir y reabrir un SPK nuevo.
