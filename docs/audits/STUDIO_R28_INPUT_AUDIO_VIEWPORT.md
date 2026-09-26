# R28 — Inspector, superficie 3D, entrada y sonido

## Fuente realmente inspeccionada

Se recuperó Sh.zip de las siete partes RAR suministradas. Contiene 56.066 entradas y la carpeta DATA_Español. El game.exe original y el game.exe del paquete offline suministrado son idénticos: 5.352.488 bytes, SHA-256 `509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d`.

La revisión de esta pasada es estática (cadenas, referencias de código y lectura completa de MON), no ejecución del juego nativo ni escucha de todos sus sonidos. No se modificó ni se redistribuye ese game.exe como una versión nueva. Sh.zip no contiene el DATA.SPK real del inventario del usuario.

## Hallazgos de audio comprobados

- Studio ejecutaba `weaponSound('jump')`. El despachador anterior elegía banco de impacto para cualquier acción distinta de `attack`, por lo que saltar disparaba un golpe. R28 separa los eventos explícitamente y rechaza acciones desconocidas.
- El cliente contiene `ch_att_spear001.wav` en VA 0x866d8c. La instrucción en 0x5f0462 carga esa referencia, precedida del código 0xa0006 en 0x5f045d y seguida de la llamada al registro de sonidos en 0x5f1ae0. La correspondiente referencia de impacto está en VA 0x866dc8, con el grupo 0xd0006. La familia 6 utiliza spear; javelin tiene su banco separado. No deben confundirse ambas familias.
- Hay voces de daño/muerte `ch_{hum,huw,elm,elw,dem,dew,vim,viw}_{dam,die}.wav` tanto en el ejecutable como en la DATA suministrada. Cuando el evento de combate señala al jugador como víctima, corresponde su voz de daño/muerte, no el impacto de su propia arma.
- Se parsearon completos 24 archivos MON de DATA_Español, conservando por separado originales y copias .bak. MO2/MO4 contienen tres referencias de sonido de ataque y una de caída/muerte. No existe en esas cuatro posiciones una referencia de daño genérica o salto.
- `character/wing/wing.mon`: SHA-256 `338444d1fef0f8026f1609a2f52cbe5732f2d17fdfb48ce410d206dee33c50dd`, 29 registros y cero referencias WAV explícitas en esos cuatro slots; contienen LOAD. No se inventa un sonido de golpe como sustituto.
- `monster/monster.mon`: SHA-256 `6073cc40c15744822cfca842ba120a4f2d70dc2e52cae99659d21ea06213784b`, 863 registros y 2.838 referencias explícitas de sonidos. Por ejemplo, el primer registro apunta a mob_ape_att01.wav, mob_ape_att02.wav y mob_ape_die.wav.
- Las únicas rutas con jump en el nombre dentro de Sound son ch_tyros_jumpturbo.wav y ch_tyros_jump_01.wav. Eso NO demuestra ausencia de todos los sonidos nativos de salto. No se reutilizan sonidos Tyros para cualquier personaje; la corrección elimina el impacto falso y no afirma una réplica sonora total.

## Correcciones integradas en fuente

Campos numéricos estables por recurso, no por valor; validación finita/rango y descarte de texto no confirmado al cambiar selección. Listas del inspector cacheadas por identidad/revisión de biblioteca en vez de recorrer todos los recursos varias veces por fotograma. Selección asíncrona de alas con generación, biblioteca capturada y actor anterior conservado hasta completar la preparación; salidas tardías no se aplican a otra DATA.

NativeView recibe el tamaño del área 3D real mediante LayoutBuilder. Actualiza superficie ANGLE, proporción de cámara y tamaño de renderizador de forma serializada. Durante la transición contiene la imagen previa sin estirarla. El bucle de fotogramas libera su guardia incluso si un callback falla, registra el primer error y conserva un contador para QA.

Ambos paneles pueden extraerse a paneles flotantes DENTRO de la aplicación, moverse, redimensionarse, maximizarse/restaurarse y volver a acoplarse. No son ventanas independientes del sistema operativo. La misma instancia de contenido se mueve; no se duplican editores. El redimensionado acoplado reserva al menos 380 unidades lógicas para el centro cuando el tamaño de ventana lo permite.

La tecla física ISO `< >` (intlBackslash), y los símbolos lógicos less/greater, alternan la intención de vuelo. Solo se procesa keydown real con foco en el visor, sin repetición automática ni Ctrl/Alt/Meta. No intercepta campos de texto. Se conserva Shift+Espacio. Es un atajo solicitado para Studio, no una tecla atribuida al game.exe original.

La presentación del logo dura 1.440 ms con entrada, pausa breve y salida, y se retira del árbol. No depende de cargar DATA ni reaparece por una biblioteca vacía. Respeta movimiento reducido y no bloquea clics.

## SPK y catálogo de Ítems

Una tabla no disponible no se reemplaza con una tabla inventada ni con los bytes de otra DATA. La pantalla explica por separado el perfil simple, fragmentos y rutas confirmadas y ofrece volver a Recursos, revisar el perfil o confirmar rutas por contenido usando una referencia explícita. Este flujo no es un descifrador nuevo de los 1.467 fragmentados y no certifica que DBItemData ya sea accesible en el SPK real.

El inventario suministrado es histórico de 0.6.22+30: 50.135 recursos, 48.668 lecturas simples, cero rutas confirmadas, fragmentos bloqueados y sin auditoría integral terminada. No se elevan flags de capacidad para ocultar esa limitación.

## Aceptación

El workflow R28 ejecuta análisis estricto, todas las pruebas Dart/Python y pruebas nativas Windows. Las pruebas de ventanas redimensionan/desacoplan/reacoplan ambos paneles y comparan la superficie y proyección con el rectángulo del visor. Las pruebas de alas cambian repetidamente entre dos recursos con escalas distintas y comprueban que avanzan los fotogramas. Los fixtures son propios y sintéticos; no sustituyen la aceptación con el ala, outfit y SPK reales del usuario.

Las cifras y hashes definitivos de entrega se registran solo después de finalizar esos gates. No usar el éxito previo de R27 como prueba de R28. Permanecen pendientes el cliente offline nuevo con vuelo/apariencia nativos, la recuperación integral del SPK real y las demás aceptaciones documentadas de Ítems/servidor.
