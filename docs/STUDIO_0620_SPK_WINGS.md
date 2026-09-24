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

## Alas — posición real + Wing.MON

La auditoría cruzada con el corpus canónico ps0032 confirma dos frentes
distintos y complementarios:

1. `DATA_Español/ExcelXml/WingPosition.xml` controla el anclaje por
   **familia + job + sexo**. El archivo canónico auditado tiene SHA-256
   `8a2c376c898bb025550b5fe34b92a40dbbbb9e39063619cfee4756006908cd03`
   y 48 perfiles = 4 familias × 6 jobs × 2 sexos.
2. `DATA_Español/Character/Wing/Wing.MON` describe los registros MO2/MO4 de
   ala: mallas/texturas y sus ANI declarados para caminar, correr, ataques 1–3,
   caída, respirar, daño y reposo.

### WingPosition.xml

El cliente clásico usa seis campos de transformación confirmados:

- `WING_LEFT_RIGHT` → posición X;
- `WING_UP_DOWN` → posición Y;
- `WING_FRONT_BACK` → posición Z;
- `WING_ROT_X`, `WING_ROT_Y`, `WING_ROT_Z` → rotación Euler.

Los 48 perfiles canónicos usan el hueso 4. Studio carga primero el XML realmente
montado y solo usa el baseline verificado como fallback de previsualización.
Cuando existe el XML real, el editor permite mover y rotar en los tres ejes y
guardar de forma transaccional:

- carpeta DATA local: backup + staging + SHA-256 antes/después;
- DATA.SPK autenticado: escritura al overlay, nunca al SPK original;
- SAH/SAF y SAF Android: permanecen fail-closed de solo lectura.

Antes de guardar, Studio vuelve a parsear el XML serializado y exige conservar
los 48 perfiles. Escala y espejo X/Y/Z se ofrecen como transformación visual de
Studio, pero **no se escriben al juego** porque no forman parte de los seis
campos WingPosition confirmados.

### Wing.MON

Studio incluye un editor lossless para MO2/MO4. Al cambiar un slot ANI:

- se modifica únicamente la cadena del slot seleccionado;
- las cadenas no editadas reutilizan sus bytes originales;
- la bandera del registro, altura, partes y cola opaca se conservan;
- el archivo generado se vuelve a parsear antes de escribirlo;
- el selector usa ANI reales de `Character/Wing/ANI`, sin inventar nombres.

La sincronización automática del visor sigue usando exclusivamente los slots ANI
declarados por el MON activo. Así, editar Wing.MON cambia tanto la configuración
persistente como el comportamiento que Studio vuelve a cargar.

### Monturas

Las monturas ya disponen de calibración visual **6DoF** por montura: asiento X/Y/Z
y rotación X/Y/Z sobre una superficie animada detectada en la geometría. Este
ajuste se recuerda durante la sesión.

A diferencia de WingPosition, todavía no se ha autenticado una tabla/archivo DATA
de monturas equivalente que el game.exe consuma para esos seis valores. Por eso
Studio no los escribe al juego todavía. El editor lo etiqueta como
previsualización y el siguiente gate es localizar esa fuente real en DATA o en
el comportamiento del game.exe antes de habilitar persistencia.

La paridad final de alas y monturas se valida contra el cliente original exacto
y no se deduce solo porque el visor se vea correcto.


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
