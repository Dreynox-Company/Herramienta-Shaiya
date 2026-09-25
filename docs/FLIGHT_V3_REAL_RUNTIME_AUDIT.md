# Flight V3 · auditoría de runtime real

Fecha de auditoría: 2026-09-24.

Esta evidencia corresponde a los dos ZIP reales suministrados para Shaiya Studio.
No se deriva de fixtures sintéticos.

## Fuentes

- `Shaiya_Vuelo_Combate_V3_Completo.zip`
  - bytes: 12,228,693
  - SHA-256: `7f720a9e339d96a6e47cdce11094ecb64663c2f80f102de179f76e7f0b2c8a44`
- `Shaiya_Studio_FlightV3_Runtime.zip`
  - bytes: 1,940,566
  - SHA-256: `6d0422c69a0e5c4b7f2a42061e30a91a6c6b452afaacac53af1e7034267cb5ba`

El `RUNTIME_MANIFEST.json` del runtime declara exactamente el SHA-256 de la
fuente completa anterior.

## Integridad del runtime

Auditoría independiente del ZIP runtime:

- 63 archivos bajo `Shaiya_Vuelo_Combate_V3/`;
- 61 entradas verificadas por `SHA256SUMS.txt`;
- 0 archivos declarados ausentes;
- 0 hashes incorrectos;
- 57 ANI reales parseados;
- todos los ANI usan exactamente 36 huesos;
- 0 jerarquías de huesos inválidas;
- duración ANI observada: 0.5 s a 17.0 s;
- 26 transiciones declaradas;
- 26 IDs de transición únicos;
- 0 diferencias entre `transiciones.json` y los ANI en número de huesos;
- 0 diferencias de duración por encima de la tolerancia de 1/15 s.

## Cobertura

El runtime contiene:

- locomoción base `humf_000/001/002`;
- combate ON, DU, TH y SP;
- hover y vuelo neutral;
- hover y vuelo con escudo;
- hover → flight;
- flight → hover;
- despegue y aterrizaje normal;
- entrada y salida de combate;
- variantes de escudo donde la fuente las declara.

Shaiya Studio conserva `targetClip` y `destinationPhase` de cada transición
para enlazar la secuencia con el estado corporal de destino sin un salto de
fase arbitrario.

## Seguridad de importación

El importador:

1. limita tamaño del ZIP y tamaño expandido;
2. rechaza traversal/rutas absolutas;
3. verifica `SHA256SUMS.txt`;
4. exige que QA binaria y numérica reporten 0 fallos;
5. reparsea los ANI con el parser nativo de Studio;
6. exige rig `humf` de 36 huesos y jerarquía compatible;
7. valida las 26 transiciones;
8. no ejecuta BAT, HTML, JS ni otro contenido activo del paquete fuente.

## Límite de esta evidencia

La auditoría prueba que el runtime suministrado es internamente coherente y que
Studio puede validarlo. No demuestra por sí sola que cada transición reproduzca
visualmente el comportamiento exacto deseado dentro de `game.exe ps0032`.
Ese gate es QA comparativo in-game contra el cliente original y la DATA real.
