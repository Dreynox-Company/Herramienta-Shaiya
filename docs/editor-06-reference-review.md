# Editor visual 0.6: referencia y criterios de aceptación

Fuentes solicitadas por el propietario:
- https://www.elitepvpers.com/forum/shaiya-pserver-guides-releases/1063024-release-shstudio-multi-purposes-editor.html (documentación de la versión 0.7.1)
- https://www.elitepvpers.com/forum/shaiya-pserver-guides-releases/3430120-release-shstudio-0-7-5-a.html (hilo 0.7.5 cuyo primer mensaje incluye actualizaciones 0.8)

Revisión del 18 de septiembre de 2026. Se han consultado los capítulos de ambos primeros mensajes. Las imágenes integradas se sustituyen por hiddenimage.png para lectores sin registro: no se afirma haber inspeccionado las imágenes ocultas. Se utilizan adicionalmente las capturas proporcionadas por el propietario. No se copian logos, binarios ni código propietario de shStudio.

## Organización funcional de la referencia

Workspace/archivo cliente, directorio servidor, acceso a varios documentos, búsqueda y vista 3D. Catálogos: objetos y equipo (armas, armaduras, escudos, accesorios, lapis/lapisia, capas, monturas, consumibles, todos y grupos de botín); habilidades de personajes y monstruos; monstruos; NPC, comerciantes, portales y misiones; modelos MLT/ITM/MON y conjuntos MLX; mapas SVMAP/WLD, texturas, objetos SMOD y DG.

Doble clic en una fila abre un formulario por registro. Las vistas 3D de equipo se enlazan mediante los índices de modelo y los archivos MLT/ITM/MON, no mediante una miniatura inventada. Las tiendas relacionan objetos; el botín puede referir grupos Grade. Los mapas del servidor utilizan minimapas de la biblioteca cliente.

La referencia distingue cliente y servidor: ubicaciones en SVMAP, información adicional en SQL/CSV, y modificaciones de archivos cliente que no despliegan automáticamente los valores autoritativos del servidor. Esa distinción no se elimina en nuestra interfaz.

## Contrato de la nueva interfaz

- Tipografía de escritorio compacta y legible; controles agrupados sin tarjetas enormes.
- Explorador por dominios; pestañas de documentos que conservan selección, búsqueda y desplazamiento.
- Catálogo virtualizado con imagen real, nombre, ID y columnas del dominio; ordenación y filtros compatibles con los campos originales.
- Formularios de registro con pestañas, validación atómica, Aplicar/Aceptar/Cancelar, cambios pendientes y acceso a todos los campos conocidos.
- Iconos recortados de los atlas originales; procedencia consultable y marcación clara cuando no existe icono verificable.
- Vista previa 3D independiente de la escena de juego; errores de recurso visibles, sin sustituir un modelo por otro.
- Referencias navegables; selección visual de iconos/modelos cuando los datos lo permiten.
- Exportaciones verificadas y reversibles; sin sobrescribir DATA, ni prometer SQL, nuevas estructuras binarias o funciones que no se han implementado.

## Verificación requerida antes de distribuir

Análisis estático, regresiones existentes, tests de interacción de ventanas y catálogos, controles de tamaño compacto, cancelación/conflictos, iconos con fixtures propios y recursos locales, capturas nativas y build Windows Release. Una matriz final separará implementado, parcial y pendiente. La paridad universal con todos los formatos del programa de referencia no se deduce de una compilación exitosa.
