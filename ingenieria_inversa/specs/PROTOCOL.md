# Protocolo ps0032: hechos y límites

Direcciones válidas exclusivamente para SHA-256
`509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`,
x86, base PE `0x400000`. Reproduce la evidencia con `tools/inspect_client.py`.

## Corrección comprobada de autenticación

La rutina en `0x542C48` toma `game.exe` de `0x85F2F0`; en `0x542C5A` llama a
`0x5427E0`. `0x542C69` llama a `0x5606F0`, que genera A114. Después `0x542C74`
llama a `0x560780`, que genera A110 con la cadena de sesión.

**A114 no contiene el nombre y contraseña.** La carga observada es de 64 bytes
relacionados con el archivo. No se identifica aquí su algoritmo como SHA-256 ni
se afirma haber reconstruido esa transformación. El adaptador que antes trataba
A114 como autenticación era incorrecto.

`native-offline/prepare_protocol.py` recibe A114 como metadatos de 1–256 bytes
sobre loopback. No concede identidad ni roles. A110 conserva la comprobación de
contraseña y valida una cadena ASCII acotada con un separador `:`. Cada sesión
local tiene credenciales aleatorias privadas, no cuentas ni claves de un servidor
público. No hay bypass de autenticación remota.

## Criterios independientes

1. Compilar servicios y verificar SQLite.
2. Escuchar en loopback con HTTP autenticado.
3. Renderizar el cliente sin diálogo de error.
4. A114 llega, A110 autentica y aparece Partida local.
5. Elegir servidor/facción y cargar selección de personajes.
6. Crear personaje, entrar al mundo, moverse y combatir.
7. Cerrar procesos, reabrir la partida y comprobar progreso real.

Las capturas identifican la etapa real; aprobar 1–5 no aprueba 6–7. Los campos
`nativeGameEntered` y `progressReloaded` permanecen false hasta probar esos
recorridos. Las coordenadas del probe solo se usan en su ventana propia aislada.

## Separación de Flutter

El nuevo cliente no usa A110/A114 para su juego local: ejecuta progreso y escena
en el proceso. `scene_profile.dart` es JSON propio del editor y Flutter; el PE
original no lo interpreta. Cambiar datos del cliente no implementa por sí solo
las reglas del servidor.

Fuentes fijadas: Imgeneus `0ce355594d521c3a06a08f24d0a9b60ebc8a459f`;
autenticación `77b3a65e9a0ba60f83e1aa452e9f0b997ea27a70` (el pin histórico no
estaba disponible); recetas SQLite base
`63afe4c3a2b97be1dd0f415930b7fa6bd59e82e9`. La entrega conserva fuente GPL
correspondiente y manifiestos. No mezclar otra versión con las partidas sin
migración comprobada.
