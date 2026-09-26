# SPK real: continuidad del 26/09/2026

**Recuperación completa NO confirmada. No se ha demostrado todavía carga de Personajes/Ítems desde el SPK real ni se entrega un descifrador terminado.**

Base de Studio: R28 `6284bf30b9f35877efd18f43d501b1d0b0d3358d`. El trabajo de esta rama no modifica main ni cambia flags de capacidad para aparentar recuperación.

## Bytes reales recuperados

La exploración de los archivos grandes localizó game.part1.rar a game.part7.rar. Se obtuvieron los bytes de las partes 1 y 3. Los intentos de materializar las partes 2, 4, 5, 6 y 7 fallaron con falta de ruta raw autorizada para esas referencias Project. No equivale a que el usuario no los haya aportado.

La primera parte RAR5 contiene una contribución almacenada de game.zip; su primer registro ZIP es data.spk comprimido con DEFLATE. Se recuperaron 524.207.806 bytes iniciales; el descompresor NO alcanzó fin de secuencia. No llamar a ese prefijo archivo completo.

- Cabecera de 128 bytes SHA-256: `1019e8a552c827d7f0e1a2628741d105dcf2e87bbb098db1e651f54a4c3289df`, idéntica al inventario.
- Rango [128,65664) SHA-256: `a2f0e5ed4e3cd2349f18611ede4d4a4a87c370f8a4429ab257703e6998e08a81`, idéntico al payload_start del diagnóstico V4 previo.
- El prefijo cubre ciphertext completo de 7.631 simples y 242 fragmentados según offsets del inventario. Esto NO acredita descifrado; no se recuperó la clave de recursos.

No publicar el prefijo, game.exe, perfiles privados ni futuros paquetes de captura en el repositorio público.

## Diagnóstico histórico y lector actual

El inventario suministrado corresponde a Studio 0.6.22+30: contenedor de 3.351.341.186 bytes; 50.135 recursos, 48.668 simples y 1.467 fragmentados, 6.789 auxiliares. Lectura simple habilitada; fragmentados y extracción completa deshabilitados, cero rutas confirmadas, 16.334 pistas, validación global ausente. `secretAvailable=true` informa del entorno que exportó el inventario; el JSON NO entrega esa clave.

La revisión de R28 encontró dos planos distintos:

1. Fragmentación: once reglas candidatas de nonce; perfil histórico `unsupported`. Deben comprobarse nonce, tag, unidad de compresión y reconstrucción con ciphertext/auxiliares reales antes de implementar una regla nueva. No se aceptan bytes que fallen autenticación.
2. Identidad: descifrar una malla no recupera el nombre que necesitan MLT/ANI/Items. Las pistas por tamaño no son rutas nativas verificadas. El descubrimiento estructural de tablas también exige auditoría global y pasa por SEED: limita el arranque parcial y necesita revisión con payloads reales, sin fabricar tablas o sustituirlas por otra DATA.

La exploración acotada de hashes de rutas y candidatos de clave disponibles no produjo una coincidencia verificable. No se ha demostrado una nueva clave ni un algoritmo de nombres. No publicar hipótesis como resultado.

## Captura mínima implementada

`tool/spk_evidence/SpkEvidence.cs` compila a una utilidad Windows x64 independiente de Flutter. No es ShStudio R29 ni un nuevo ResourceProbe.

- Lectura explícita del SPK, sin red, ejecución del cliente, inyección o cambios en el registro.
- Plan JSON acotado y validado por tamaño y SHA-256 de cabecera/índice.
- Rango individual máximo 8 MiB; payload agregado máximo 32 MiB, sin solapamientos ni lecturas fuera del contenedor.
- Cabecera, índice cifrado, auxiliar, pie y rangos seleccionados, cada uno con tamaño/hash/offset.
- Perfil de recursos y game.exe opcionales, con consentimiento y en PRIVATE/. El programa no afirma que la forma válida del perfil demuestre su clave correcta.
- Escritura temporal y publicación sin sobrescribir destinos; origen abierto solo lectura y con bloqueo de escritura durante captura.
- Manifiesto explícito fullDecryptionVerified=false, incluso al completar la captura.

El plan de esta entrega se generó localmente, no se incorpora al repositorio. Tiene 226 rangos (212 simples y 14 fragmentados completos), 13.564.381 bytes de ciphertext más 2.311.749 de índice y 217.248 de auxiliar. Incluye candidatos de tablas/catálogos y muestras distribuidas. Las pistas de nombres solo priorizan muestras; no identifican DBItemData de forma probada.

El plan se liga al inventario SHA-256 `14bced55d6a3b54315e5af0c78f7634c292339f3805e71922b6f9266433299bb` e índice cifrado `a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f`.

## Validación y entrega del recolector

- Commit exacto compilado `41bd9fe615b6035a9c1e9a184a93386c929f77da`.
- Workflow `36220991550`, éxito; artifact `10898708828`.
- 14 pruebas sobre el EXE en Windows: hashes, rangos, lectura exacta, perfiles, consentimiento, no ejecución del cliente, rechazo de destino existente y conservación de origen. Son pruebas sintéticas de transporte, NO pruebas de descifrado del SPK del usuario.
- EXE 24.064 bytes, SHA-256 `f755fa6408a9b3a0bf96c4eb2d4bee78e8ad94e907322a4263ad881083f67458`.
- Artifact descargado SHA-256 `a2ebfb15c8512a87b848e4fd7aebe2a29cae3735f8cd3e7120e2a2354d8c735e`, CRC y hash del EXE comprobados.
- Entrega local `ShStudio-SPK-Evidencia-Real-Windows.zip`, 31.745 bytes, SHA-256 `4a3a9c833baf5804251d7774bfc74a3b4dd09a5bfd13ba443e0a28a70e622a9c`.
- Añade plan e instrucciones en español sin modificar el EXE probado. Todos los hashes del manifiesto y CRC del ZIP final se comprobaron.

## Próxima evidencia necesaria y aceptación

Recibir el ZIP generado por la utilidad, especialmente el perfil simple que ya funciona y el game.exe de la MISMA instalación SPK. Es una alternativa a volver a subir varios GB para la próxima fase, no un sustituto del ensayo integral final.

Después: autenticar índices y muestras, verificar las cadenas de fragmentos y descartar reglas ambiguas, recuperar nombres/dependencias con evidencia y probar Items/Personajes con bytes propios del contenedor. La aceptación final requiere todos los recursos legibles y correctamente asociados, editar/guardar/reabrir y medir apertura/reapertura. El repack necesita su propia validación y aceptación por el cliente correspondiente.

No declarar tiempos instantáneos sin medición, ni usar el éxito de pruebas sintéticas como sustituto de esta aceptación. El objetivo del usuario sigue abierto.
