# SPK real reader — estado auditado 0.6.13

Fecha de corte: 2026-09-21.

Esta nota es el punto de reanudación del trabajo SPK. No volver a empezar desde
cero: la rama `feat/studio-0612-spk-workspace` continúa el lector v3, el
AutoPerfil de payloads y la integración de DATA.SPK como fuente de Shaiya
Studio.

## DATA.SPK de referencia

Índice cifrado identificado por SHA-256:

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
- 5 registros especiales.

El índice AES-GCM y su frame Zstandard están entendidos y validados. Esto no
equivale por sí solo a tener descifrados los payloads.

## Evidencia del inventario real recibido

El inventario actual confirma el modo `spk-v3`, la geometría anterior y
21.360 rutas inferidas. En ese inventario todavía aparecen:

- `resolvedNames = 0`;
- `inferredNames = 21360`;
- `unresolvedNames = 28775`;
- `canReadSimpleResources = false`;
- `canReadFragmentedResources = false`;
- `canExtractAll = false`;
- clave de recursos no disponible.

Por lo tanto no se debe declarar aún que los payloads reales del SPK de
referencia están descifrados. El árbol visible es un avance real del índice y
de la reconstrucción de nombres, pero el contenido sigue cerrado hasta que
AutoPerfil produzca y Studio vuelva a autenticar el perfil de recursos.

## Avances consolidados

1. Los IDs SPK se manejan como uint64 y se serializan siempre con 16 dígitos
   hexadecimales mediante `spkU64Hex`.
2. Los 5 registros especiales quedan separados de recursos simples y
   fragmentados.
3. Las rutas confirmadas y las inferidas son estados distintos. Una inferencia
   no se promueve a confirmada solo por tamaño o nombre.
4. Las colisiones entre rutas inferidas se excluyen del montaje en vez de
   escoger un recurso arbitrario.
5. `Library` puede montar DATA.SPK como fuente transparente para el resto de
   Studio cuando simples y fragmentados están autenticados.
6. Las modificaciones desde el editor se guardan en un overlay transaccional;
   DATA.SPK original permanece intacto. El overlay registra Entry ID, SHA-256
   original, SHA-256 modificado, tamaño y fecha.
7. Una ruta SPK solo puede modificarse si está confirmada. Las rutas inferidas
   siguen siendo útiles para lectura/3D, pero no son autoridad de escritura.
8. El editor reconoce tablas de objetos, monstruos, habilidades, NPC skills,
   set items, tiendas y textos DB mediante sus contratos binarios.
9. El descubrimiento estructural de tablas examina payloads autenticados,
   valida SEED/checksum, cabeceras y esquemas, y puede confirmar automáticamente
   las tablas núcleo. El mapa resultante se persiste junto al SPK.
10. Al montar el SPK en Studio, si todavía faltan tablas núcleo confirmadas, el
    flujo las descubre primero y después monta la biblioteca.
11. El editor de monstruos expone los pares `ItemN / ItemDropRateN` como botín
    sin inventar porcentajes; las relaciones de botín se resuelven por Grade.
12. En objetos, `ReqOg` y `Og` tienen selector explícito para
    intercambiable / no intercambiable / vinculado cuando el servidor soporte
    ese tercer estado.
13. Skills, requisitos, clases, precios, estadísticas y demás parámetros
    conservan el tipo numérico original y se editan con round-trip validado.
14. El catálogo 3D consume la misma `Library`. Cuando existen MLT/ITM/MON los
    usa como autoridad. En SPK se añadió un fallback conservador que solo expone
    un personaje si encuentra cuerpo completo y parejas 3DC/DDS con nombre
    exacto; no inventa asociaciones aproximadas.

## Gates criptográficos

La presencia de una clave en JSON no habilita lectura por sí sola.

Estados admitidos:

- índice válido + sin perfil de payloads: catálogo/rutas solamente;
- clave presente pero no autenticada: lectura bloqueada;
- simples autenticados: lectura de simples habilitada;
- regla de nonce de chunks aún no validada: fragmentados bloqueados;
- simples + reconstrucción fragmentada autenticados: `Extraer todo` y montaje
  completo habilitados.

AutoPerfil de Windows abre el cliente de la misma instalación en modo offline y
el resultado se vuelve a comprobar contra ciphertexts reales del SPK antes de
habilitar lectura. La derivación de fragmentos se valida también offline contra
los tags de la tabla auxiliar.

## Estado de CI

La base 0.6.12 ya pasó regresión completa y build nativo de Windows. Los cambios
0.6.13 añaden descubrimiento automático antes del montaje, pruebas sintéticas
de identificación estructural de DBItem/DBMonster/DBSkill y cobertura del
selector de intercambio de objetos. El gate definitivo de esta iteración es
mantener verdes formato, análisis, suite Flutter/Dart/Python, integración nativa
y build Windows.

## Evidencia real todavía pendiente

Para cerrar el soporte del SPK observado todavía hace falta ejecutar sobre la
instalación real:

1. AutoPerfil SPK con el par exacto `game.exe + data.spk`;
2. revalidación distribuida de recursos simples;
3. derivación y validación de fragmentos completos;
4. nuevo inventario donde `canReadSimpleResources`,
   `canReadFragmentedResources` y `canExtractAll` reflejen el resultado;
5. descubrimiento de tablas núcleo sobre esos payloads;
6. prueba real de edición de un objeto, un drop de monstruo y una skill en
   overlay con relectura byte a byte;
7. montaje en Studio y prueba 3D con Character/DDS/ANI/MLT leídos desde el SPK;
8. extracción de muestras y después barrido completo con manifest.

Hasta tener esa evidencia no marcar como completada la lectura real de los
50.135 recursos.

## Orden exacto de continuación

1. Mantener CI verde en `feat/studio-0612-spk-workspace`.
2. Generar build Windows actual.
3. Ejecutar AutoPerfil SPK en la máquina que contiene el SPK real.
4. Exportar un nuevo inventario y conservar también el perfil/diagnóstico
   producido.
5. Ejecutar **Preparar Studio**: descubrimiento estructural + montaje.
6. Validar primero DBItemData/Item, DBMonsterData/Monster y DBSkillData/Skill.
7. Probar Item tradeability, drops por Grade y skills con overlay y reapertura.
8. Probar catálogo 3D directamente desde DATA.SPK.
