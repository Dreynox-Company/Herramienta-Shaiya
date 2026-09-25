# R25 — editor de ítems SData y atlas nativos

## Evidencia de origen

Se extrajo `Sh.zip` del RAR multipartes suministrado, sin escribir en el origen.
Se auditó `DATA_Español/binarysdata`, `DATA_Español/interface/icon` y el
`game.exe` ps0032: SHA-256
`509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`.
Las tablas numérica y española contienen 28.142 registros cada una, con 70
columnas numéricas. Se mantiene la advertencia del CRC SEED heredado documentada
por R24; esto no tiene relación con autenticar los payloads AES-GCM de DATA.SPK.

Ejemplos reales: 25:1 Manzana (Icon=1, ConstHp=119 y descripción de 119 HP);
1:1 Espada Larga (Image=0, Icon=1); 95:1 Arma Lapisia; 42:1 Piedra Invoca Caballos;
121:7 La pesadilla antes de Halloween. Tipo 94 corresponde a lingotes de gremio,
no a lapisias. Los nombres ???? son contenido original, no objetos inexistentes.

## Iconos: no confundir ItemTypeId, Image e Icon

- 0x4e0e31 lee Icon como byte; 0x4e0e35 decrementa: índice nativo 1-based.
- 0x5794e0 remapea familias; tablas en 0x5796d8 y 0x579634.
- 0x4e1310 selecciona rejillas 4/8/16 columnas; UV vertical en dieciseisavos.
- 0x4e11f0 selecciona atlas especiales y páginas. Las familias 25,27,28,30
  usan icon_somo, icon_quest, icon_quest2, icon_rapis, no un número de archivo.
- Tipos 121/122: icon_wing; 125: icon_125_mount; 95: icon_rapis;
  128: icon_128_questitem; 130: icon_130_serviceitems, entre otros.
- Solo tipos paginados restan 100; la página secundaria usa 100+familia.
- Se rechazan Icon=0 y >255, celdas fuera de la rejilla y familias no soportadas.
  Un atlas ausente no se sustituye por somo ni por el de otro tipo.

Estas reglas pertenecen al ejecutable inspeccionado. No se anuncian como un
formato universal de todos los episodios/custom clients.

## Implementación

Ítems es una sección global, independiente del equipamiento del personaje:
lista virtualizada, iconos reales, nombres/descripciones localizados, filtros por
categoría, nombre, Type:TypeId y comparaciones numéricas exactas con BigInt.
El selector SData de equipamiento abre el mismo editor mediante identidad exacta.
Se conservan los dos modos mutuamente excluyentes Recursos y Objetos registrados.

Todas las columnas de propiedades nativas permanecen accesibles; campos se
agrupan por tipo sin inventar el significado de Arg ni convertir Effect1..4 a
una fórmula universal. Las identidades y contadores estructurales se protegen
porque cambiarlos exige migrar referencias, no simplemente editar un stat.
Nombre y descripción se editan en la tabla localizada de la misma familia.

MLT/ITM/MON asociados exponen sus modelos/texturas, índices, anclajes y ANI donde
el formato los contenga. Se elige explícitamente la variante; no se colapsan
varios MON/MLT a la primera coincidencia. Un aviso explica el impacto sobre otros
ítems al modificar un recurso compartido.

La sesión conserva borradores y deshacer/rehacer en lote. Publicar relee las
salidas, verifica los cambios, comprueba el hash de los orígenes antes y después
de preparar una carpeta temporal y la renombra solo al finalizar. No escribe
media transacción en el DATA activo. La salida contiene COPIAR_EN_DATA y un
manifiesto con hashes/cambios. El servidor no se sincroniza automáticamente.

## Límites de aceptación que siguen abiertos

- Generar una miniatura nueva, importar sus píxeles e insertarlos en un atlas
  nativo sin colisiones no es lo mismo que elegir un Icon existente; sigue abierto.
- Cambiar referencias a malla/textura no es un editor de escultura o pintura 3D.
- Asociaciones nuevas/candidatas de tipos modernos requieren validación de la
  variante exacta del cliente; nunca se confirman por tener un icono parecido.
- No todas las funciones de Special/Arg son conocidas; quedan editables bajo su
  nombre nativo, sin inventar efectos de juego.
- Tablas legacy Item.SData de otras familias/episodios siguen en el editor
  genérico; este módulo usa explícitamente DBItemData de BinarySData.
- game.exe con vuelo nativo y consumidor --appearance, sincronización del servidor,
  DATA.SPK real y aceptación visual de usuario no se dan por cerrados por estos tests.

El resultado de CI y el SHA exacto compilado se incorporan al cierre de entrega;
este documento por sí mismo no afirma que el lote esté ya aprobado.
