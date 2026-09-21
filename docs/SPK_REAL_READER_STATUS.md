# SPK real reader — estado auditado 0.6.11

Fecha de corte: 2026-09-21.

Esta nota existe para que el trabajo SPK no vuelva a empezar desde cero. La rama
0.6.11 continúa directamente desde `feat/studio-0610-spk-autoperfil`.

## DATA.SPK de referencia

El archivo observado queda identificado por el SHA-256 del índice cifrado:

`a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f`

Geometría validada:

- archivo: 3.351.341.186 bytes;
- índice: offset 3.349.029.373;
- índice almacenado: 2.311.749 bytes;
- índice decodificado: 4.813.440 bytes;
- 50.140 registros;
- 50.135 recursos;
- 48.668 simples;
- 1.467 fragmentados;
- 6.789 registros auxiliares/chunks;
- 5 registros especiales no extraíbles como archivos.

El índice AES-GCM y su frame Zstandard están entendidos y validados. Esto no
equivale a tener descifrados los payloads.

## Avances que ya no deben revertirse

1. Los IDs son uint64. La salida antigua podía imprimir la mitad alta como
   valores negativos, incluso con ceros antes del signo. `spkU64Hex` y
   `spkParseU64Hex` normalizan ahora siempre a 16 dígitos hexadecimales.
2. Los registros especiales ya no se presentan como si fueran recursos
   fragmentados.
3. El mapa empaquetado ligado al índice contiene 21.360 rutas inferidas y
   mantiene separadas las rutas confirmadas.
4. Las inferencias nunca se promocionan a confirmadas solo por nombre/tamaño.
   La promoción a confirmada exige comparación SHA-256 del payload decodificado
   contra una DATA de referencia.
5. ResourceProbe observa únicamente llamadas criptográficas cuyo ciphertext
   coincide por hash con uno de los 55.457 objetivos reales del SPK
   (48.668 recursos simples + 6.789 chunks).
6. La clave del índice y la clave de recursos siguen siendo conceptos
   separados. El lector acepta AES-GCM 128/256 para payloads y AAD
   none/constant cuando la evidencia lo respalda.
7. La regla de nonce de fragmentos se deriva por autenticación GCM; no se elige
   por heurística de formato.
8. La extracción continúa siendo transaccional mediante carpeta temporal.

## Nuevo gate 0.6.11

La mera presencia de una clave en un JSON ya no habilita lectura/extracción.

Antes de habilitar recursos simples, Studio autentica muestras distribuidas del
SPK real con AES-GCM. Antes de habilitar fragmentados, deriva la regla de nonce
contra tags auxiliares y reconstruye recursos fragmentados completos,
verificando además el tamaño decodificado.

Estados:

- índice válido + sin clave de payload: solo catálogo;
- clave presente pero no autenticada: lectura bloqueada;
- simples autenticados: lectura simple habilitada;
- nonce derivado pero reconstrucción fragmentada no validada: fragmentos
  bloqueados;
- simples autenticados + reconstrucciones fragmentadas validadas:
  `Extraer todo` habilitable.

ResourceProbe finaliza en cuanto obtiene suficientes observaciones simples. No
necesita esperar a que el cliente cargue chunks: Studio puede derivar la regla
de fragmentación offline usando la clave ya autenticada, los ciphertexts reales
y los tags de la tabla auxiliar.

## Evidencia todavía pendiente

No se considera cerrado el descifrado de payloads hasta ejecutar ResourceProbe
contra el `game.exe` que acompaña exactamente al DATA.SPK de referencia y
obtener un `derived-resource-profile.json` que Studio revalide.

No hay que declarar completados todavía:

- extracción real de los 48.668 simples;
- reconstrucción real de los 1.467 fragmentados;
- detección de formatos sobre el conjunto completo;
- confirmación SHA-256 de rutas;
- integración SPK como fuente transparente del catálogo 3D;
- Extraer todo de 50.135 recursos.

## Orden de continuación

1. CI de 0.6.11 y build Windows.
2. Ejecutar AutoPerfil SPK offline con el par real `game.exe + data.spk`.
3. Revalidar la clave sobre muestras simples distribuidas.
4. Derivar nonce de chunks y validar al menos dos recursos fragmentados completos.
5. Ejecutar una extracción de muestras y luego barrido completo con manifest.
6. Detectar formatos y auditar los desconocidos.
7. Confirmar rutas contra DATA conocida por SHA-256.
8. Solo después conectar SPK a la abstracción de `Library` usada por
   personajes, DDS, ANI, mapas, SData y demás sistemas.
