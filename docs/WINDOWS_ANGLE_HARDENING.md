# Windows ANGLE Release hardening · Shaiya Studio 0.6.23

## Motivo

La rama 0.6.22 quedó compilada y auditada, pero el paquete upstream
`flutter_angle 0.4.2` incluye en Windows un runtime ANGLE que depende del CRT
Debug de MSVC. El ejecutable y los plugins propios de Studio son Release; el
problema está en los `libEGL.dll/libGLESv2.dll` precompilados que el plugin
empaqueta.

No se eliminan DLLs Debug a ciegas ni se sustituyen por binarios sin
procedencia. Este frente construye un runtime ANGLE Release reproducible y
lo prueba antes de cerrar el gate de distribución.

## Fuente reproducible

Studio usa el port `angle` de Microsoft vcpkg con manifest propio:

- baseline vcpkg:
  `5f96cd15fd745122cf27e0524606d6c1efc5fd07`;
- port: `angle`;
- versión solicitada: `chromium_7258`;
- triplet: `x64-windows`;
- licencia declarada por el port: BSD-3-Clause.

El baseline fue elegido dentro de la generación del runner Windows usada por
CI y contiene `angle chromium_7258` port-version 2.

## Pipeline

Cuando `build.yml` recibe `harden_angle=true`:

1. compila Studio normalmente en Release;
2. instala/compila el ANGLE fijado mediante vcpkg;
3. sustituye en la carpeta Release solo los DLL de runtime producidos por el
   triplet Release;
4. exige `libEGL.dll` y `libGLESv2.dll` AMD64;
5. inspecciona dependencias PE con `dumpbin /dependents`;
6. rechaza cualquier dependencia directa al CRT Debug;
7. elimina los CRT Debug que solo eran necesarios por el runtime upstream;
8. comprueba que `flutter_angle_plugin.dll` sigue importando EGL y GLESv2;
9. arranca el ejecutable Release con una DATA sintética montada y exige una
   ventana nativa viva;
10. vuelve a ejecutar el smoke normal, ResourceProbe y empaquetado;
11. guarda `qa-angle/angle-hardening.json` con hashes, baseline, dependencias
    y DLLs copiadas.

## Gate fail-closed

`distribution-status.json` solo marca
`graphicsRuntimeHardeningComplete=true` si simultáneamente:

- no quedan CRT Debug en el paquete;
- existe evidencia de ANGLE proveniente del manifest vcpkg fijado;
- `libEGL.dll` y `libGLESv2.dll` tienen SHA-256 registrados;
- ambos son AMD64;
- el smoke del Release endurecido con DATA termina con proceso y ventana vivos.

Si falta cualquiera de esas pruebas, permanece abierto
`windows-angle-release-runtime`.

## Alcance

Este gate prueba el runtime gráfico distribuido por Studio. No sustituye la
comparación visual con `game.exe ps0032`, ni resuelve el DATA.SPK. Es un
hardening de distribución Windows independiente.
