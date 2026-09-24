# Shaiya Studio 0.6.22 · Matriz profesional de capacidades DATA

Esta matriz separa estrictamente tres niveles de evidencia:

1. **Confirmado con archivo real**: el formato o tabla fue abierto y validado con material suministrado para esta auditoría.
2. **Confirmado por parser/regresión de Studio**: existe soporte estructural y pruebas del formato en el repositorio, pero no equivale a haber validado cada recurso propietario de la instalación del usuario.
3. **Solo inventario SPK inferido**: la ruta aparece en el inventario de nombres del DATA.SPK, pero el payload sigue cifrado y no puede considerarse abierto.

Nunca se convierte una ruta inferida del SPK en evidencia de contenido.

## Estado por dominio

| Dominio / formato | Evidencia actual | Studio 0.6.22 | Edición | Game-facing | Gate pendiente |
| --- | --- | --- | --- | --- | --- |
| WingPosition.xml | **Archivo real confirmado** | SpreadsheetML, 48 perfiles, selector 3D | BONE_IDX + posición XYZ + rotación XYZ | **Sí, nativo** | QA visual final con ps0032 |
| Character/Wing/*.MON MO2/MO4 | Parser/regresión + contrato DATA | Visor/equipamiento + 9 slots ANI | ANI, WAV/OGG, EFT/3DE, adjunto MO4, malla, textura | **Sí, MON DATA** | Probar Wing.MON exacto de la instalación |
| ANI de ala | Referencias del MON | Reproducción por estado/evento | Se reasigna el ANI del slot; no se reescribe el binario ANI | Sí, por MON | Autoría ANI genérica no implementada |
| Flight V3 Runtime | **ZIP real confirmado** | 26 transiciones + ON/DU/TH/SP + neutral/escudo | Importación/preview, no muta los ANI fuente | Studio/runtime | Expandir rigs cuando existan ANI reales compatibles |
| WingDecompose.xml | **Archivo real confirmado** | ExcelXml Lab | Celdas tipadas | Tabla DATA | Validación funcional in-game por sistema |
| WingExpItem.xml | **Archivo real confirmado** | ExcelXml Lab | Celdas tipadas | Tabla DATA | Validación funcional in-game por sistema |
| WingSwap.xml | **Archivo real confirmado** | ExcelXml Lab | Celdas tipadas | Tabla DATA | Validación funcional in-game por sistema |
| Vehicle MON MO2/MO4 | **Archivo real confirmado** · 6 MO4 activos × 120 registros | Montura 3D + ANI + auditoría de referencias/LOAD | ANI, sonidos, efectos, sentinel LOAD | **Sí, MON DATA** | QA in-game Hu/El/Vi/De y bridge |
| Asiento de montura | game.exe + Studio Bridge documentado | Calibración 6DoF, escala, espejo, perfiles ANI | VehiclePosition.ini | **Bridge ps0032**, no tabla original | Certificación in-game del bridge |
| LookAndEquipment.xml | **Archivo real confirmado** | ExcelXml Lab | Celdas tipadas | Tabla DATA | No confundir VEHICLE/PET con pose de asiento |
| functionalpetsize.xml | **Archivo real confirmado** | ExcelXml Lab | Tamaños/efectos | Tabla DATA | QA visual de pets |
| ymwatershaderparams.xml | **Archivo real confirmado** | Acceso desde Escenario + ExcelXml Lab | Parámetros por MapID | Tabla DATA | Enlace visual directo de cambios al renderer |
| WLD | Parser/regresión; rutas SPK inferidas | Terreno/objetos/streaming | Lectura/visualización | Nativo | Editor geométrico genérico pendiente |
| WTR | Parser/regresión | Capas/texturas de terreno | Lectura/visualización | Nativo | Editor de capas pendiente |
| SVMAP | Parser/regresión | NPC, mobs, portales, spawns, áreas | Lectura estructural | Nativo/server-side según corpus | Editor especializado pendiente |
| DG / dungeon | Parser/regresión | Geometría, texturas, colisión | Lectura/visualización | Nativo | Autoría/guardado pendiente |
| SMOD | Parser/regresión; rutas SPK inferidas | Malla estática + colisión | Lectura/visualización | Nativo | Autoría/guardado pendiente |
| VANI | Parser/regresión; rutas SPK inferidas | Malla animada por frames | Lectura/visualización | Nativo | Autoría/guardado pendiente |
| 3DC / 3DO | Parser/regresión; rutas SPK inferidas | Visor 3D, skinning, equipamiento | Referencias editables; binario genérico no se reescribe | Nativo | Writer 3DC/3DO antes de baking/mirror real |
| DDS / TGA | Parser/decoder + rutas reales/inferidas | Preview y asociación de texturas | Selección/referencia | Nativo | Editor de textura dedicado opcional |
| EFT / 3DE | Referencias MON + rutas SPK inferidas | Selección/referencia; preview parcial | Referencia editable en MON | Nativo | Secuenciador/VFX completo pendiente |
| WAV / OGG | Referencias MON + rutas SPK inferidas | Reproducción/selección | Referencia editable en MON | Nativo | Mezclador/editor de audio fuera de alcance |
| DB*.SData | Workbench/regresiones | Filas/columnas, IDs, referencias | Edición estructurada donde el schema está probado | Nativo | Validar cada tabla propietaria con DATA real |
| ItemCreate.xml y opciones | **Archivos reales confirmados** | ExcelXml Lab | Celdas tipadas | Tabla DATA | QA de reglas/servidor |
| Drops / respawn XML | **Archivos reales confirmados** | ExcelXml Lab | Celdas tipadas | Tabla DATA | Diferenciar cliente/servidor por instalación |
| Font/GM notices/time notices | **Archivos reales confirmados** | ExcelXml Lab | Celdas/XML | Tabla DATA | Preview UI especializado opcional |
| DATA.SPK índice V3 | **Inventario real confirmado** | Árbol, inventario, nombres, diagnósticos | No se modifica original | Contenedor | Payload key |
| DATA.SPK payload simple | Bloqueado | Fail-closed | **No** hasta autenticar | — | canReadSimpleResources=true |
| DATA.SPK payload fragmentado | Bloqueado | Fail-closed | **No** hasta autenticar | — | nonce/AAD/chunks autenticados |
| DATA.SPK repack | Writer/regresión sintética | Overlay + construcción separada | Solo tras perfil autenticado | Contenedor | 50.135/50.135 + 0 fallos + reopen |

## Cobertura real de ExcelXml auditada

La fuente excelxml.zip suministrada contiene 46 XML. Studio 0.6.22 los expone en **ExcelXml Lab** y además agrupa accesos contextuales por dominio:

- **Alas**: WingPosition, WingDecompose, WingExpItem, WingSwap.
- **Mundo/viaje**: water shader, mapas, facción, límites de nivel y movimiento entre ciudades.
- **Monstruos/NPC/drops**: drops globales/por mapa, tasas, respawn, eventos y ventanas de NPC.
- **Objetos/economía**: creación, opciones, bonus, random options, renown shop, gemas y restricciones.
- **UI/eventos/operación**: fuentes/estilos, avisos GM, avisos temporizados, eventos, enlaces y main quest.

AccessContinueEvent.xml está malformado en la fuente recibida. Studio no normaliza ni “arregla” ese archivo silenciosamente: abre un modo de reparación y solo habilita guardado después de que el documento completo vuelva a parsear.

## Cobertura de rutas observadas en el inventario SPK

El inventario real contiene nombres **inferidos** en familias útiles para Studio, entre ellas:

- Character/*/3DC y Character/*/ANI;
- Vehicle/3DC y Vehicle/ANI;
- Monster/3DC y Monster/ANI;
- Entity/Building/*.SMOD y Entity/Tree/*.SMOD;
- Entity/VAni/*.VANI;
- Effect/*.EFT y Effect/3DE/*.3de;
- Sound/*.wav;
- Item/3DO;
- world/*.wld;
- interface/Xml/*.xml.

Estas rutas sirven para priorizar parsers, asociación visual y AutoPerfil, pero **no prueban que el payload de esos IDs haya sido descifrado**.

### Freeze 0.6.22

El código funcional 0.6.22 queda congelado después del commit de formato determinista. A partir de este punto solo se corrigen fallos demostrados por el gate; no se añaden capacidades nuevas antes de obtener el artifact Windows auditado.

## Prioridad de cierre

1. Congelar 0.6.22 y pasar format/analyze/tests.
2. Integración Windows + Release + smoke.
3. Empaquetar ResourceProbe V13 y artifact auditado.
4. Probar el artifact con DATA real: WingPosition/Wing.MON/Vehicle.MON/XML.
5. Ejecutar ResourceProbe contra el par exacto game.exe + DATA.SPK.
6. Solo después de autenticación: auditoría 50.135/50.135, repack, reapertura.
7. En una siguiente versión, priorizar editores especializados para WLD/WTR/SVMAP/SMOD/VANI y un writer 3DC/3DO antes de permitir baking de escala/espejo directamente en geometría.


### Vehicle real audit

La fuente `DATA (1).zip` real (SHA-256
`c5b6eb7510c55f49198e4527495a9f5e86fcc80886f88e77a5454649f025870a`)
confirma 168 3DC, 590 ANI, 187 DDS y 6 MON activos bajo `Vehicle/`.
Cada MON activo es MO4 con 120 registros. El valor `LOAD` aparece como sentinel
nativo en ANI/sonido/efecto/adjunto y ya no se trata como una ruta faltante.
Studio conserva además las colas opacas y reporta por separado referencias
concretas que sí faltan en la DATA suministrada. Véase
`VEHICLE_REAL_DATA_AUDIT.md`.
