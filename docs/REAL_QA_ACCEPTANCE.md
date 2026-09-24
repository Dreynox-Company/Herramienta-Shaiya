# QA real · contrato de aceptación para Shaiya Studio 0.6.22

`distribution-status.json` ya no mantiene permanentemente abiertos los gates
de DATA real. El empaquetador puede consumir una evidencia explícita y ligada a
hashes para cerrar de forma reproducible los checks que **no pueden certificarse
con fixtures sintéticos de CI**.

## Archivo

Ruta por defecto:

`qa-real/acceptance.json`

También puede indicarse otra ruta mediante la variable
`SHAIYA_REAL_QA_ACCEPTANCE`.

El archivo es opcional. Si no existe, todos los gates de aceptación real
permanecen en `false`.

## Esquema 1

```json
{
  "schema": 1,
  "gameExeSha256": "<64 hex>",
  "wing": {
    "positionGameExe": true,
    "positionSha256": "8a2c376c898bb025550b5fe34b92a40dbbbb9e39063619cfee4756006908cd03",
    "monExactInstall": true,
    "monSha256": "5fb05afe456e158f4343a904d6192efe427b9c764a058bd6be6afc688a3da94b"
  },
  "vehicle": {
    "monExactInstall": true,
    "bridgeGameExe": true,
    "monSha256": {
      "Hu": "b280b941076eb7067ed8001fce3b82d12f87eb9eff42778b6a2fd90b51ec7aab",
      "El": "a2ea784c162d11186e49cc4ba82086e02181b33bb0e22bde21a18f14cee85940",
      "Vi": "893a7c4a7c70aa93de01cd28415c164e6ea23dbe6ce5296bceab45c7afc1801b",
      "De": "ba23e03028aa99ef804402d2d0ee3dc975a45debf6e1a75e63e5fdef4e9aabf7"
    }
  },
  "spk": {
    "indexSha256": "a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f",
    "canReadSimpleResources": true,
    "canReadFragmentedResources": true,
    "canExtractAll": true,
    "validatedResources": 50135,
    "failures": 0,
    "repackReopened": true,
    "gameExeAccepted": true
  }
}
```

## Reglas fail-closed

Studio no acepta un booleano aislado como prueba suficiente.

- WingPosition solo cierra si `positionGameExe=true` **y** su SHA-256 coincide
  con la fuente real auditada.
- Wing.MON solo cierra si el hash coincide con el MO4 real de 81 registros
  auditado.
- Vehicle.MON exige los cuatro hashes activos Hu/El/Vi/De auditados.
- El bridge de montura exige además un SHA-256 de `game.exe` sintácticamente
  válido para ligar la prueba a un binario concreto.
- El SPK solo cierra la auditoría si el índice es exactamente el perfil real,
  simples y fragmentados están habilitados, `canExtractAll=true`,
  `validatedResources=50135` y `failures=0`.
- `repackReopened` y `gameExeAccepted` solo cuentan después de que la
  auditoría integral anterior sea válida.
- La clave de payloads sigue siendo autoridad del perfil criptográfico
  autenticado de ResourceProbe/Studio; este JSON no puede fingir
  `resourceKeyValidated`.

## Efecto sobre distribución

El empaquetador refleja la evidencia en `distribution-status.json`.

El gate `real-data-visual-qa` desaparece únicamente cuando son verdaderos:

1. WingPosition probado con game.exe.
2. Wing.MON exacto guardado/reabierto/probado.
3. Vehicle.MON exactos probados.
4. VehiclePosition Studio Bridge probado con game.exe.

El gate `spk-50135-full-audit-and-reopen` desaparece únicamente cuando:

1. 50.135/50.135 recursos están validados y hay 0 fallos.
2. El SPK reconstruido fue reabierto.
3. El SPK reconstruido fue aceptado por el game.exe usado en QA.

Así el estado “100%” deja de ser una estimación manual: el ZIP de distribución
expone exactamente qué evidencia falta y no puede declararse completo mientras
alguno de los checks permanezca abierto.
