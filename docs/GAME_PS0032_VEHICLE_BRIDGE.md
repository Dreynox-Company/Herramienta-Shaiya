# ps0032 · VehiclePosition Studio Bridge

Estado: **implementado en rama de Studio; validación estática del PE completada; validación in-game Windows pendiente de runner/PC con el cliente nativo.**

## Binario auditado

- Cliente: `cliente/game.exe`
- SHA-256 soportado: `509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`
- PE32 x86, ImageBase `0x400000`, ASLR activo.
- El parcheador es fail-closed: otro hash no se modifica.

## Alas

ps0032 ya consume nativamente `data/ExcelXml/WingPosition.xml`. Se confirmó el contrato:

- `FAMILY`, `JOB`, `SEX`
- `BONE_IDX`
- `WING_ROT_X`, `WING_ROT_Y`, `WING_ROT_Z`
- `WING_UP_DOWN`, `WING_FRONT_BACK`, `WING_LEFT_RIGHT`

Studio debe seguir editando ese XML directamente. No se parchea esta ruta del cliente.

## Monturas · recursos y animaciones

El cliente carga cuatro familias de MON:

- `Vehicle_Hu_01.MON`
- `Vehicle_El_01.MON`
- `Vehicle_Vi_01.MON`
- `Vehicle_De_01.MON`

La resolución real usa `familia + índice de registro`. Cada registro admite nueve slots ANI mediante el resolver nativo de `Vehicle/*.MON`; Studio no debe usar un ANI global.

Los nueve slots que ya edita el parser MO2/MO4 son:

1. Caminar
2. Correr
3. Ataque1
4. Ataque2
5. Ataque3
6. Caída
7. Respirar
8. Daño
9. Reposo

## ANI del jinete

Es un contrato separado del ANI del MON. El modo nativo termina en `character+0x4F4`.

Mapeo confirmado en ps0032:

| RIDER_PROFILE | Reposo | Movimiento | Estado |
| --- | ---: | ---: | --- |
| 0 | 21 | 20 | nativo |
| 1 | 97 | 22 | nativo |
| 2 | 98 | 98 | nativo |
| 3 | 97 | 22 | nativo |
| 4 | 30 | 31 | corpus VehB / preview; ruta runtime separada aún no hookeada |

Studio carga todos esos ANI compatibles y permite elegir el perfil por montura. El bridge del juego aplica directamente los perfiles nativos 0–3. El perfil 4 se conserva explícitamente como preview hasta cerrar su ruta independiente en `game.exe`.

## Posicionamiento del jinete en game.exe

La rutina de render nativa construye la transformación desde datos de personaje/montura, selección de hueso y constantes del cliente. El resultado world se copia a `0x8E74C8` y se envía a Direct3D con `D3DTS_WORLD`.

Hook auditado:

- VA: `0x44AFBB`
- Bytes originales: `A1 08 79 8E 00`
- Semántica original: `mov eax,[0x8E7908]`
- El bridge sustituye esos 5 bytes por un `CALL rel32` a una sección nueva `.dxst`.
- La rutina inyectada ejecuta la semántica del MOV sobrescrito antes de retornar.

Transformación aplicada:

`Scale * RotX * RotY * RotZ * Translation * NativeWorld`

Es un **delta local sobre el cálculo nativo**, no un reemplazo del asiento/hueso original.

## Archivo DATA editable

Ruta canónica de Studio:

`ExcelXml/VehiclePosition.ini`

El bridge busca, en orden:

1. `DATA_Español\ExcelXml\VehiclePosition.ini`
2. `DATA_Espanol\ExcelXml\VehiclePosition.ini`
3. `DATA\ExcelXml\VehiclePosition.ini`

El launcher offline crea `cliente\data` como junction hacia la DATA seleccionada, por lo que guardar desde Studio en la DATA real queda visible al cliente.

Sección por montura:

```ini
[F0_V0A]
ENABLED=1
POS_X_MM=0
POS_Y_MM=0
POS_Z_MM=0
ROT_X_MDEG=0
ROT_Y_MDEG=0
ROT_Z_MDEG=0
SCALE_X_PERMILLE=1000
SCALE_Y_PERMILLE=1000
SCALE_Z_PERMILLE=1000
RIDER_PROFILE=0
```

Convenciones:

- posición: entero / 1000 unidades del juego;
- rotación: millidegrees / 1000 grados;
- escala: permille / 1000;
- escala negativa = espejo del eje;
- `ENABLED != 1`, sección ausente o archivo ausente => fallback nativo;
- `RIDER_PROFILE` 0–3 sobreescribe el modo nativo; 4 no se inyecta todavía.

El transporte entero evita problemas de locale decimal en el cliente C++/Win32.

## Cache y recarga

El bridge cachea por `familia + vehicleId` y no relee el INI cada frame. Para validar un cambio, desmonta/cambia de montura o reinicia el cliente; el flujo de QA recomendado es guardar en Studio y volver a entrar con la montura.

## Seguridad binaria

El parche:

- no modifica el `game.exe` original;
- genera una copia Studio Bridge;
- agrega `.dxst` con código + cache;
- mantiene ASLR;
- neutraliza únicamente la relocación HIGHLOW que correspondía al operando absoluto reemplazado por el CALL relativo;
- recalcula PE CheckSum;
- limpia Security Directory porque Authenticode deja de ser válido después de modificar el ejecutable;
- conserva los bytes históricos del certificado como datos inertes;
- aborta si hash, hook, ImageBase o relocación no coinciden con el perfil ps0032.

## DATA.SPK

Este bridge **no desbloquea ni sustituye** la investigación de DATA.SPK. Son frentes distintos.

El INI del bridge debe permanecer como archivo suelto legible por el cliente. Studio rechaza crearlo dentro de SAH/SAF, Android SAF o overlay SPK. La investigación SPK mantiene sus gates fail-closed hasta autenticar payload simple y fragmentado con cero fallos.

## Criterio de cierre

Antes de llamar esta ruta “in-game certificada” deben pasar:

1. CI Flutter/Windows de Studio.
2. Arranque del paquete offline con el `game.exe` bridge.
3. Montura perfil 0 con delta neutral.
4. Cambio visible X/Y/Z.
5. Rotaciones X/Y/Z.
6. Escala y espejo por eje.
7. RIDER_PROFILE 1, 2 y 3.
8. Archivo ausente y `ENABLED=0` => resultado nativo.
9. Cambio de familia Hu/El/Vi/De.
10. Cierre específico de la ruta 30/31 antes de declararla game-facing.
