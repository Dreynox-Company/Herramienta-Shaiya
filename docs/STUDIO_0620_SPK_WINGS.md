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
- wolfSSL: `wc_AesGcmSetKey`, `wc_AesSetKey`.

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
