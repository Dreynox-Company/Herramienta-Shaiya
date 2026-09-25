# ps0032 · cross-check binario real para alas y monturas

Fuente: `Shaiya_Offline_Nativo_0_1_2_Windows.zip` suministrado previamente por
el usuario y reabierto durante el cierre de Studio 0.6.22.

## Cliente exacto

`cliente/game.exe`

- tamaño: 5.352.488 bytes;
- SHA-256:
  `509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`;
- PE32 x86;
- ImageBase: `0x00400000`.

El hash coincide con el perfil que usa
`GAME_PS0032_VEHICLE_BRIDGE.md`. Esta evidencia no se traslada a otra versión
de game.exe.

## WingPosition confirmado dentro del ejecutable

El binario contiene de forma contigua:

- `data/ExcelXml/WingPosition.xml`;
- `FAMILY`;
- `JOB`;
- `SEX`;
- `BONE_IDX`;
- `WING_ROT_X`;
- `WING_ROT_Y`;
- `WING_ROT_Z`;
- `WING_UP_DOWN`;
- `WING_FRONT_BACK`;
- `WING_LEFT_RIGHT`;
- el diagnóstico nativo `Can not find WingPosition.xml`.

Esto cierra la correspondencia estática entre el SpreadsheetML real auditado y
los campos que consume este game.exe. La prueba visual de un valor modificado
sigue siendo un gate runtime separado.

## Wing.MON confirmado dentro del ejecutable

El cliente contiene:

- `Wing.MON`;
- `data/Character/Wing`.

Esto coincide con la fuente real auditada bajo
`DATA_Español/Character/Wing/Wing.MON`. Studio conserva MO2/MO4 y el sentinel
`LOAD`; esta comprobación binaria prueba la ruta nativa del catálogo, no que
cada recurso referenciado exista en un subconjunto incompleto de DATA.

## Vehicle.MON confirmado dentro del ejecutable

El bloque de cadenas del cliente contiene:

- `Vehicle_Hu_01.MON`;
- `vehicle_El_01.MON`;
- `Vehicle_Vi_01.MON`;
- `Vehicle_De_01.MON`;
- `data/Vehicle`.

La diferencia de mayúscula/minúscula de `vehicle_El_01.MON` se conserva como
evidencia del binario; Studio normaliza la resolución de rutas sin reescribir
arbitrariamente el archivo original.

## Hook del VehiclePosition Studio Bridge

En VA `0x0044AFBB` los cinco bytes reales son:

`A1 08 79 8E 00`

Semántica x86:

`mov eax, [0x008E7908]`

Es exactamente la instrucción documentada para el hook fail-closed del bridge.
Por tanto el perfil estático del parche corresponde al game.exe real anterior,
no a una dirección deducida de otro cliente.

## Límite de esta evidencia

La inspección binaria confirma rutas, campos y bytes del hook. No sustituye:

1. guardar WingPosition y verificar visualmente el resultado en ps0032;
2. modificar/reabrir Wing.MON y Vehicle.MON exactos y probarlos in-game;
3. verificar posición/rotación/escala/espejo del VehiclePosition bridge;
4. certificar un DATA.SPK reconstruido con el cliente que corresponda a ese
   contenedor.

Esos resultados se registran mediante `qa-real/acceptance.json`; un booleano
sin los hashes esperados no cierra ningún gate.
