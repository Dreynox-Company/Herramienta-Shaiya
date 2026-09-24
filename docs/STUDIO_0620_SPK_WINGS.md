# Shaiya Studio 0.6.20 — SPK V13 + alas

## Alcance

Esta rama trabaja exclusivamente en **Shaiya Studio / herramienta de edición**.
No modifica el cliente de juego Flutter ni sus ramas de paridad.

## DATA.SPK

ResourceProbe V13 mantiene el contrato fail-closed de V12: una candidata de
clave nunca habilita lectura por su tamaño, origen o apariencia. Debe reproducir
offline AES-GCM contra ciphertexts y tags exactos del DATA.SPK cuyo índice
coincide con el perfil validado.

V13 conserva CNG/OpenSSL y añade observación de claves en:

- BoringSSL: `EVP_AEAD_CTX_init`;
- mbedTLS: `mbedtls_gcm_setkey`, `mbedtls_aes_setkey_enc/dec`;
- wolfSSL: `wc_AesGcmSetKey`, `wc_AesSetKey`;
- barrido profundo acotado de secciones PE de datos del cliente y DLLs;
- escaneo runtime alrededor de copias de la clave del índice en memoria,
  limitado y validado siempre por el oráculo AES-GCM del SPK.

La evidencia real sigue siendo la autoridad. No se declara descifrado total
hasta que simples y fragmentados autentiquen, la auditoría integral tenga cero
fallos y el SPK reconstruido sea reabierto y validado.

## Alas

Studio ya lee `character/wing/*.mon` como registros MO2/MO4 con sus mallas,
texturas y slots ANI originales. 0.6.20 añade:

- calibración de posición/escala/rotación separada por **ala + raza/arquetipo**;
- anclaje sobre la cadena real del torso, evitando reutilizar offsets entre
  esqueletos incompatibles;
- sincronización automática de la animación del ala usando exclusivamente los
  slots declarados por su MON original;
- estados explícitos de reposo terrestre, flotación, vuelo en movimiento y
  aterrizaje;
- modo manual para inspeccionar cualquier ANI original del ala sin perder la
  capacidad de volver a la sincronización automática.

La selección automática no inventa archivos ANI ni certifica todavía paridad
1:1 con `game.exe`. La paridad final requiere capturas/pruebas con el cliente
original exacto y el mismo DATA.SPK.


## Contrato de interacción conservado

- W mantiene marcha; W + Shift mantiene carrera.
- Equipar alas no activa por sí solo el vuelo.
- Las alas permanecen vinculadas al personaje y siguen la transformación del
  asiento cuando se equipa/cambia una montura.
- Entrar en combate desde vuelo inicia un descenso natural; el ataque terrestre
  solo comienza después del contacto con el suelo.
- La guardia y las animaciones de combate siguen siendo estados de combate, no
  reposos permanentes del editor.


## Gate de rama

La rama 0.6.20 se normaliza con `dart format` antes de exigir analyze, regresión
completa, integración nativa y Windows Release. Un fallo de formato no debe
ocultar errores reales de compilación.


## Estado del gate 0.6.20

Los parsers trasladados desde el cliente Flutter se validan primero con fixtures
sintéticos y luego con la integración Windows de Studio. La compatibilidad con
recursos propietarios se declara únicamente después de probar los archivos
reales; una detección de formato no sustituye esa evidencia.

## Preview de DATA externa mientras el SPK está bloqueado

Para evitar que el explorador sea solo un listado inútil mientras falta la
clave de payloads, 0.6.20 permite seleccionar una carpeta DATA de referencia.
Las rutas candidatas pueden abrirse con doble clic y mostrarse con el mismo
visor de Studio; 3DC/3DO intentan además resolver su DDS/TGA homóloga.

Este modo está etiquetado explícitamente como **referencia**: no confirma el
payload del SPK, no habilita escritura del contenedor y no relaja el gate
criptográfico. Sirve únicamente para inspección y trabajo visual mientras
AutoPerfil obtiene evidencia suficiente.
