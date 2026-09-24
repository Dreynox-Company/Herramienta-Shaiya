# Windows Release · auditoría de distribución

Último artifact funcional auditado antes de este documento:

- workflow run: `36060761059` (run #1138)
- branch: `feat/studio-0620-spk-wings`
- head: `628a4e306c613426225e4ff28c5b616425039e5b`
- artifact: `Shaiya-Studio-Windows-Audited`
- artifact ID: `10835205640`
- tamaño: 86,393,295 bytes
- SHA-256 del artifact GitHub: `dc90aa0b3756373dab3394effbd9ab2e3f0fe7f30a4d63daf151b908dd204aa7`
- ZIP interno: `Shaiya-Studio-Windows-26428352aed8.zip`
- SHA-256 ZIP interno: `fa22af02a2efc9ed2137b9534057778d0803b65c32153f812f291edec2a2b071`

## Gates verdes

El run #1138 completó:

- formato;
- análisis estático;
- regresión Dart/Flutter;
- pruebas Python de entrega/integridad;
- integración nativa Windows;
- build Release x64;
- round-trip del writer SPK sintético;
- arranque y ventana real de la aplicación;
- ResourceProbe V13 self-contained;
- empaquetado con provenance y hashes.

El smoke de ventana confirma **arranque**, no paridad visual con game.exe ni
aceptación de DATA real.

## Runtime Flight V3

El runtime real suministrado se auditó por separado:

- `Shaiya_Studio_FlightV3_Runtime.zip`
- SHA-256: `6d0422c69a0e5c4b7f2a42061e30a91a6c6b452afaacac53af1e7034267cb5ba`
- 57 ANI, todos de 36 huesos;
- 26/26 transiciones coherentes;
- 61/61 hashes declarados correctos.

Studio lo detecta automáticamente si se coloca en:

`Extras/FlightV3/Shaiya_Studio_FlightV3_Runtime.zip`

junto al ejecutable, o puede importarse desde la UI.

## Hallazgo de empaquetado ANGLE

La dependencia externa `flutter_angle 0.4.2` suministra en Windows sus propias
bibliotecas ANGLE precompiladas. La inspección PE del artifact confirmó que:

- `libEGL.dll`, `libGLESv2.dll`, `libc++.dll` y `zlib.dll` enlazan
  contra el CRT **Debug** de MSVC;
- por esa razón el bundle actual contiene `MSVCP140D.dll`,
  `VCRUNTIME140D.dll`, `VCRUNTIME140_1D.dll` y `ucrtbased.dll`;
- el ejecutable de Studio y sus plugins propios sí enlazan contra el runtime
  Release normal.

El upstream de flutter_angle declara explícitamente esos DLL debug como
`flutter_angle_windows_bundled_libraries`. Por tanto no se eliminan a ciegas:
hacerlo rompería el renderer 3D.

Este punto no invalida el artifact para QA, pero sí queda como gate de
**hardening de distribución** antes de llamar al paquete Windows una entrega
final de producción: sustituir el runtime ANGLE upstream por un build Release
compatible y volver a pasar smoke/render/CI.

## Gates que no acredita este artifact

1. Comparación visual real contra `game.exe ps0032`.
2. Guardado/reapertura de los Wing.MON/Vehicle.MON exactos del usuario.
3. Confirmación visual del WingPosition real después de guardar.
4. Certificación in-game del VehiclePosition Studio Bridge.
5. Autenticación del payload del DATA.SPK real.
6. Auditoría DATA.SPK 50.135/50.135 y repack/reopen.
7. Runtime ANGLE Release sin CRT Debug.

Hasta cerrar esos puntos, el artifact se considera **RC auditada para QA**, no
“100% producción”.
