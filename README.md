# Shaiya Studio 0.6

Editor nativo de recursos para Windows y Android. [Guía del editor 0.6](docs/EDITOR_06.md).

Esta revisión incluye catálogos visuales compactos, ventanas de edición independientes, relaciones entre recursos, vista 3D y animaciones, minimapa SVMAP, edición MLT/ITM/MON y configuración de texto. **Guardar actualiza el origen abierto**, incluido SAH/SAF; Guardar copia y Respaldo son opcionales. También se construyen SAH/SAF desde carpetas DATA.

La lectura y edición utilizan el esquema real: se conservan encabezados, bytes desconocidos, codificación y rangos. Los datos del servidor se distinguen de los del cliente. El juego offline y el enlace directo con su motor son una integración separada y no se declaran terminados mediante esta entrega del editor.

## Notas históricas (anteriores a 0.6)

# Antecedentes: Shaiya Studio 0.4.0 — Flutter nativo

Windows y Android. Sin HTML ni WebView. Selecciona **carpeta DATA** o el par **DATA.SAH + DATA.SAF**. La lectura es local y no modifica los recursos originales. Mantén la biblioteca separada de la carpeta `data` de Flutter, junto al ejecutable.

## Cambios de 0.4

- Selector de clase real dentro del arquetipo; armas y escudos filtrados mediante los metadatos de DATA, con identificación explícita del respaldo por familia cuando faltan reglas. El modo de inspección conserva los recursos no compatibles para examinarlos.
- Escudo independiente con un arma de una mano. Al pasar a dos manos se libera el escudo. Anclajes originales por esqueleto.
- Reposo al equipar; guardia únicamente por actividad de combate, con salida después de ocho segundos sin ataques ni impactos. Carrera específica por familia de arma.
- El casco del conjunto se equipa automáticamente. Oculta el cabello dibujado sin olvidar el cabello elegido; al quitarlo vuelve a mostrarse. El rostro se conserva.
- Cobertura corporal combinada de prendas: el traje de Navidad no hereda las piernas base cuando torso y botas contienen ya esa región. No se infiere desnudez a partir de nombres como body001.
- Alas con rotación horizontal local y ajuste por recurso. Pose adicional de cabeza suave y limitada, sin escribir sobre las claves originales.
- Biblioteca suplementaria de vuelo aislada por arquetipo, sexo y jerarquía. Otros gestos no reemplazan acciones originales. Los recursos no compatibles se conservan sin aplicarlos al cuerpo equivocado.
- Impactos discretos con una reserva acotada de partículas pequeñas; fuentes de sonido originales cuando existen.
- Streaming espacial con carga por proximidad, descarga con margen de histéresis, reutilización de modelos/texturas y retirada de colisiones por sector. El personaje no entra en un sector cuyo piso no está preparado.
- Inventario de **todas** las DDS, con función, asociaciones y estado. Descubre recolores y mallas homónimas omitidas por MLT. Máscaras, efectos, terreno e iconos no se convierten falsamente en armaduras. Los casos ambiguos quedan en el explorador para asociación manual, no se ocultan.

## Ejecutar

Extrae completo el ZIP binario de Windows y ejecuta `herramienta_shaiya.exe`, conservando sus DLL y `data`. Android utiliza el selector nativo con permiso de solo lectura.

El selector DATA ofrece:
1. **Carpeta DATA:** comportamiento tradicional.
2. **Archivos DATA.SAH + DATA.SAF:** el SAH contiene el índice; el SAF, los recursos. En Windows puedes seleccionar ambos o uno y localizar su compañero. En Android selecciona ambos en el diálogo del sistema.
3. **Exportar diagnóstico de archivo:** disponible incluso después de un fallo al abrir.

### Cifrado y diagnóstico

Se admiten índices estándar y los perfiles implementados y comprobados: contadores de directorio XOR 0x55, XOR uniforme de cabecera reconocido y envoltura SEED reconocida mediante integridad. Se verifican nombres, límites, recuentos, terminación y rangos dentro del SAF. El contenido se lee por rangos; no se carga todo el SAF en RAM ni se extrae sobre DATA.

**No es un descifrador universal.** Un índice propietario, otra clave, compresión o cifrado del contenido puede requerir un perfil nuevo. No se intenta adivinar ni presentar un índice inválido como válido. El reporte JSON incluye huellas, tamaños, perfil, motivos de rechazo y pequeñas cabeceras de recursos fallidos; no incluye claves, credenciales ni el contenido completo. Revisa el reporte antes de compartirlo.

## Paquete de vuelo

Las animaciones de referencia del usuario no se publican con los recursos del juego en el repositorio. En el paquete final de Windows se suministra `Extras/flight.json.gz`; se carga automáticamente al conectar la biblioteca. Se puede importar también desde **Alas y monturas → Importar vuelo**. En Android importa el archivo suministrado aparte. Solo se habilitan los perfiles que coinciden exactamente; los Panda no reciben por defecto un vuelo humano.

## Compilar desde fuentes

```shell
python tool/prepare.py
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build windows --release
```

Requiere Flutter 3.47.4 y herramientas nativas de la plataforma. `COMPILAR.ps1` y `tool/build.py` realizan esas comprobaciones y generan los paquetes. GitHub Actions prueba una ventana nativa Windows con recursos sintéticos propios antes de empaquetar el EXE. El APK es de prueba, no una firma comercial. No distribuyas artefactos de una ejecución fallida ni confundas los binarios 0.3.1 con 0.4.

## Evidencia y límites

Consulta `docs/REVISION_0_4.md` y los artefactos de la ejecución del commit exacto. Las pruebas de lectores, lógica, renderizado EGL y ventana Windows se contabilizan por separado. No se afirma validar visualmente cada combinación de todos los clientes.

No están implementados el agua avanzada, el cliente multijugador ni la correspondencia oficial completa de cada receta EFT/lapisia. La asociación de una DDS a una malla no prueba por sí sola la compatibilidad visual de sus UV. La calibración de alas/jinete y los casos de recursos dañados disponen de diagnóstico y controles de inspección. No se promete abrir cualquier archivo cifrado sin conocer su formato o clave.

Licencias: ver `THIRD_PARTY_NOTICES.md`. No se incluyen modelos/texturas/sonidos originales del juego en GitHub.
