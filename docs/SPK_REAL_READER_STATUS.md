# SPK real reader / writer — estado auditado 0.6.20

Fecha de corte: 2026-09-22.

Esta nota es el punto de reanudación del trabajo SPK. No volver a empezar desde
cero. La rama `feat/studio-0620-spk-wings` continúa el lector v3, AutoPerfil,
auditoría integral, montaje transparente en Studio, edición por overlay y el
primer escritor/repacker DATA.SPK con autoverificación.

## Actualización 0.6.20 — V13 y recursos del motor

Se reutilizó evidencia obtenida durante el trabajo del cliente Flutter sin
mezclar ambos productos. Studio incorpora ahora conocimiento confirmado del
cliente sobre:

- alas: equipo slot 16, `DBItemData.ItemType = 121` y `Image` como ID del
  registro `Character/Wing/*.MON`;
- formatos del motor que antes quedaban frecuentemente como BIN:
  `WTR`, `MAni`, `VAni`, `SMOD`, `DG` y `SVMAP`;
- inspección estructurada de esos formatos directamente desde el explorador SPK;
- familias modernas de objetos y su slot de equipo, usando el contrato
  ps0032/metadata ya ejercitado por el cliente Flutter.

ResourceProbe sube a **V13**. Mantiene el mismo oráculo fail-closed AES-GCM y
amplía observación de candidatos a BoringSSL, mbedTLS y wolfSSL además de
CNG/OpenSSL. La presencia de una candidata no desbloquea ningún payload:
Studio debe autenticarla offline contra ciphertexts y tags exactos del SPK.

La evidencia real del DATA.SPK del usuario **no cambia por estos commits**:
hasta ejecutar este build con el par exacto `game.exe + data.spk`, no se afirma
que los 50.135 payloads estén descifrados ni que el writer sea aceptado por el
cliente oficial.

## DATA.SPK real de referencia

Índice cifrado identificado por SHA-256:

`a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f`

Geometría ya validada:

- archivo: 3.351.341.186 bytes;
- índice: offset 3.349.029.373;
- índice almacenado: 2.311.749 bytes;
- índice decodificado: 4.813.440 bytes;
- 50.140 registros;
- 50.135 recursos;
- 48.668 simples;
- 1.467 fragmentados;
- 6.789 registros auxiliares/chunks;
- 5 registros especiales tipo 32768.

Los cinco registros técnicos reales tienen `dataOffset = 0`; se preservan como
metadatos y no se tratan como payloads.

El índice AES-GCM y su frame Zstandard están entendidos y validados.

## Correcciones 0.6.16 a partir de la prueba real

La ejecución real más reciente confirmó que el explorador todavía estaba
mostrando inferencias mientras los payloads seguían cifrados. También se observó
`FormatException: Missing extension byte` durante AutoPerfil en Windows.

Se corrigieron ambos frentes:

- ResourceProbe fuerza UTF-8 en todos sus JSON de evidencia;
- Studio fuerza UTF-8 en el proceso hijo y tolera bytes malformados de consola,
  evitando que una codificación regional de Windows aborte AutoPerfil;
- recursos cifrados ya no permiten **Leer / inspeccionar**, doble clic ni
  extracción directa;
- el explorador muestra un aviso explícito de **CONTENIDO CIFRADO**;
- columnas de formato/tamaño se etiquetan como estimadas/declaradas mientras el
  payload no esté autenticado;
- rutas inferidas se aceptan solo con correspondencia uno-a-uno tanto en el SPK
  como en la DATA de referencia;
- inferencias antiguas que asignaban la misma ruta a varios Entry IDs se
  descartan al cargar el mapa en vez de mostrarse como archivos duplicados;
- si AutoPerfil no obtiene una clave válida, Studio informa la carpeta exacta
  de diagnóstico para revisar `derived-resource-profile.json` y
  `resource-observations.json`.

## Capa de trabajo 0.6.17

La herramienta deja de tratar el explorador como un listado pasivo después del
desbloqueo:

- los formatos reales se conservan inmediatamente tras una lectura autenticada;
- recursos sin nombre confirmado reciben un alias estable por Entry ID y
  extensión validada;
- el explorador filtra por formato real;
- DDS/PNG/BMP/JPEG/GIF/TGA tienen previsualización visual;
- XML/JSON/INI/TXT tienen visor de texto;
- 3DC/3DO tienen visor 3D interactivo y usan la DDS compañera cuando puede
  resolverse sin ambigüedad;
- ANI muestra duración y pistas;
- MLT/ITM/MON se inspeccionan como catálogos estructurados;
- SData se muestra en filas/columnas y puede abrirse directamente en el editor;
- antes de editar una SData sin nombre confirmado, Studio ejecuta descubrimiento
  estructural de tablas núcleo;
- SData, MLT, ITM, MON y recursos de texto autenticados pueden abrirse
  directamente en el editor de overlay;
- AutoPerfil genera un diagnóstico clasificado cuando no consigue cerrar la
  clave: ausencia de hook, ausencia de ciphertexts, ausencia de clave, parámetros
  GCM incompletos, fallo de autenticación offline o muestras insuficientes.

La edición por Entry ID técnico sigue exigiendo auditoría completa del SPK. Las
rutas inferidas no se convierten en autoridad de escritura.

## Evidencia real recibida hasta ahora

El inventario más reciente recibido del usuario todavía corresponde a una
ejecución anterior al cierre del AutoPerfil de payloads y declara:

- `resolvedNames = 0`;
- `inferredNames = 21360`;
- `unresolvedNames = 28775`;
- `canReadSimpleResources = false`;
- `canReadFragmentedResources = false`;
- `canExtractAll = false`;
- clave de recursos no disponible.

Existe evidencia local de la clave AES-GCM del índice, ligada al SHA-256 exacto
anterior. Esa clave no se declara automáticamente como clave de recursos:
Studio la prueba contra tags GCM reales y la descarta si no autentica.

Por tanto, el código está preparado para lectura/escritura completa, pero no se
debe afirmar todavía que los 50.135 payloads del archivo real del usuario han
sido descifrados. Falta ejecutar 0.6.17 contra el par real
`game.exe + data.spk` y obtener la auditoría.

## Avances consolidados del lector

1. IDs SPK tratados como uint64 y presentados siempre con 16 dígitos
   hexadecimales.
2. Índice v3, offsets, tamaños, redundancias, tabla auxiliar y geometría
   validados antes de exponer recursos.
3. Nombres confirmados, inferidos validados, inferidos fuertes, aproximados y
   sin resolver son estados separados.
4. Las colisiones de rutas inferidas se excluyen; no se elige arbitrariamente
   un Entry ID.
5. Lectura simple solo se habilita después de autenticar muestras AES-GCM reales.
6. Fragmentos solo se habilitan después de derivar una regla reproducible de
   nonce y reconstruir recursos completos con tags válidos.
7. `Extraer todo` permanece fail-closed hasta que simples y fragmentados estén
   autenticados.
8. Tras el gate criptográfico, la auditoría integral relee todos los recursos,
   comprueba autenticación, decodificación y longitud declarada cuando existe.
9. La auditoría persiste el formato detectado de cada Entry ID y permite montar
   recursos sin nombre bajo `_SPK_SinNombre/<EntryID>.<ext>`.
10. Evidencia de auditoría solo se restaura si coinciden índice, hash de la clave
    de recursos, regla de chunks y cobertura total de Entry IDs.

## AutoPerfil / ResourceProbe V13

Antes de instrumentar `game.exe`, V13 ejecuta un barrido estático acotado y fail-closed: prueba derivaciones de la clave del índice, constantes próximas a evidencia AES/GCM y, como segunda etapa, material literal de 16/32 bytes en secciones PE de datos inicializadas y no ejecutables. La etapa profunda usa primero un recurso simple pequeño como prefiltro para contener el coste; una candidata solo se acepta si después autentica tres recursos simples distribuidos del SPK con sus tags GCM reales. Si ninguna coincide, continúa automáticamente con instrumentación dinámica x86/x64.


AutoPerfil sigue este orden:

1. intenta offline si la clave autenticada del índice también autentica
   payloads;
2. si falla, no reutiliza esa clave;
3. en Windows ejecuta ResourceProbe V13 contra el `game.exe` de la misma
   instalación y sin red;
4. ResourceProbe observa únicamente operaciones cuyo ciphertext coincide con un
   recurso/chunk real del índice;
5. puede recuperar claves desde
   `BCryptGenerateSymmetricKey`, `BCryptImportKey`,
   `BCryptDuplicateKey` y desde handles vivos usados por
   `BCryptDecrypt` mediante `BCryptExportKey/KeyDataBlob`;
6. Studio vuelve a autenticar la clave obtenida contra el SPK;
7. deriva la regla de nonce de chunks offline;
8. ejecuta auditoría completa;
9. descubre tablas editables y persiste rutas/evidencia.

No se aceptan claves ni nonces por parecido, longitud o heurística visual.

## Integración con editor y 3D

`Library` puede usar DATA.SPK directamente como fuente del Studio.

El editor ya cubre:

- `DBItemData` / `Item.SData`;
- `DBMonsterData` / `Monster.SData`;
- `DBSkillData`, `DBNpcSkillData` y tablas de skills;
- textos DB;
- set items;
- tiendas/ventas;
- tablas SData detectables por contrato;
- MLT, ITM y MON;
- configuración/textos compatibles.

Semántica ya expuesta:

- `ReqOg/Og = 0`: intercambiable;
- `ReqOg/Og = 1`: no intercambiable;
- `ReqOg/Og = 2`: vinculación cuando esa versión de servidor la soporta;
- drops de monstruos: `Item1..Item9` +
  `ItemDropRate1..ItemDropRate9`, preservando Grade cuando el contrato así lo
  define en vez de inventar ItemID;
- skills y requisitos conservan tipos y round-trip original.

El catálogo 3D consume la misma Library. MLT/ITM/MON son autoridad cuando están
resueltos; para personajes existe fallback conservador de cuerpo completo con
parejas 3DC/DDS de nombre exacto.

## Overlay editable

Studio no modifica el SPK original durante la edición normal.

Cada recurso editado guarda:

- Entry ID;
- SHA-256 original;
- SHA-256 editado;
- tamaño;
- autoridad de la ruta;
- fecha.

Antes de volver a usar el overlay se comprueba que el origen siga siendo el
mismo. También se puede materializar una DATA completa descifrada y aplicar el
overlay de forma transaccional.

## Nuevo en 0.6.15 — SPK Writer/Repacker

Se añadió `SpkWriter` para producir un **DATA.SPK nuevo**, nunca para
sobrescribir el original.

El escritor:

- exige auditoría total previa;
- valida que cada reemplazo pertenezca al Entry ID correcto;
- conserva bytes desconocidos de cabecera y el footer original;
- conserva ciphertext simple no modificado cuando es seguro hacerlo;
- vuelve a empaquetar recursos editados respetando si el payload original era
  raw o Zstandard;
- genera nonces nuevos para simples editados;
- para todos los fragmentados reconstruye offsets, chunks, tabla auxiliar,
  nonces y tags AES-GCM;
- permite crecer o reducir la cantidad de chunks de un recurso editado;
- recalcula offsets y `auxiliaryStart`;
- serializa los 96 bytes exactos de cada registro;
- recompone y comprime el índice;
- cifra de nuevo el índice AES-GCM con nonce nuevo;
- conserva los cinco registros técnicos;
- vuelve a abrir el archivo temporal con el lector real;
- revalida simples;
- revalida fragmentos;
- audita todos los payloads;
- solo entonces publica el nuevo `.spk`.

Junto al SPK reconstruido publica sidecars ligados al nuevo hash del índice:

- `.profile.json`;
- `.names.json`;
- `.audit.json`.

Si falla cualquier etapa, el archivo parcial y los sidecars incompletos se
eliminan.

El editor expone:

- **Materializar DATA completa + overlay**;
- **Construir nuevo DATA.SPK verificado**.

## Evidencia de CI del writer

El gate previo al bump 0.6.15 pasó completamente en el commit
`b681359db1eb8b5aecb74b115bc22a00e9da6152`:

- formato;
- `flutter analyze`;
- regresión Flutter/Dart;
- regresión Python;
- integración nativa Windows;
- build Release;
- prueba específica del writer con `zstandard_windows.dll`;
- round-trip de recursos simples;
- round-trip de recursos fragmentados;
- crecimiento de cadena de chunks;
- reconstrucción de índice/tabla auxiliar;
- reapertura y auditoría total del SPK generado;
- smoke test de la ventana real;
- ResourceProbe autocontenido;
- empaquetado de entrega.

El test sintético comprueba además que el SPK original no cambia.

Esto demuestra el contrato interno lector↔writer de Studio. **No demuestra aún
que el cliente oficial acepte un SPK reconstruido**, porque esa compatibilidad
solo puede cerrarse con el `game.exe` exacto del usuario y su archivo real.

## Gates para declarar el SPK real “100 % libre”

No cerrar el trabajo hasta obtener en el archivo real:

1. `canReadSimpleResources = true`;
2. `canReadFragmentedResources = true`;
3. `canExtractAll = true`;
4. auditoría `validatedResources = 50135` y `failures = 0`;
5. identificación y apertura de tablas núcleo;
6. edición real de objeto, drop y skill con reapertura;
7. carga 3D real desde SPK;
8. extracción integral con manifiesto;
9. reconstrucción de un SPK nuevo con el writer;
10. reapertura/auditoría del SPK reconstruido;
11. prueba del SPK reconstruido con el `game.exe` exacto de esa instalación.

Solo después del punto 11 debe declararse compatibilidad completa de escritura
con el cliente real.

## Próxima ejecución requerida

Usar el build Windows 0.6.20/V13 sobre la instalación real, preferiblemente offline:

1. abrir el `data.spk`;
2. pulsar **AutoPerfil SPK**;
3. dejar finalizar auditoría y descubrimiento;
4. exportar inventario nuevo;
5. conservar `derived-resource-profile.json`,
   `resource-observations.json`, `data.spk.resources.json`,
   `data.spk.audit.json` y `data.spk.names.json`;
6. montar **Preparar Studio**;
7. validar Item / Monster / Skill;
8. validar 3D;
9. construir un `data-editado.spk` de prueba y probarlo en una copia de la
   instalación, nunca sustituyendo primero el archivo original.
