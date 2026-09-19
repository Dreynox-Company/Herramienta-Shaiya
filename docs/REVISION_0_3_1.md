# Revisión 0.3.1 · cuerpo completo y entrega reproducible

## Cambios

El catálogo anterior trataba cualquier torso sin fila de pantalón como traje integral. Esa inferencia no era válida. Los nombres Panda Trousers y Arm tampoco se normalizaban, de modo que la selección inicial omitía las piernas y los antebrazos. Se eliminó esa inferencia; ahora se combinan los nombres equivalentes y la supresión de piezas base necesita evidencia de cobertura en la malla y sus pesos de animación. La incertidumbre conserva la región base.

El preset `@base` incluye las cuatro regiones corporales originales y mantiene cara/cabello. No equipa casco. `@nude` solo existe ante un juego explícito completo de referencias originales; la biblioteca inspeccionada no contiene un perfil de este tipo verificado para ninguno de sus 20 arquetipos. La conservación de prendas es fidelidad al recurso, no un filtro ni un desenfoque aplicado por la herramienta.

Una sesión antigua con fullCostume=true se vuelve a resolver y no puede suprimir las piernas por sí sola. La geometría y sus animaciones dependientes se preparan antes de publicar el actor. Un fallo de textura conserva al actor anterior; una carga tardía no sustituye a la selección más reciente. Se mantiene una caché CPU acotada de mallas corporales, independiente del propietario de cada textura GPU.

## Pruebas

99 Dart/Flutter, 22 Python, 60 comprobaciones EGL/GLES3 de los 20 arquetipos. Se verificaron 1.354 conjuntos y se rechazó con diagnóstico el recurso elmr_constan_upper.3dc por un valor no finito. Esos recuentos de catálogo no constituyen validación visual de cada combinación.

Las capturas de los 20 cuerpos base se generaron con el renderizador del programa. La reproducción del Panda incompleto usa las fuentes originales 0.3 sin modificar, no la ocultación artificial de una pieza en 0.3.1.

## Ejecutables

No hay EXE/APK nuevos precompilados en este paquete de fuentes. Los iniciadores de compilación exigen éxito y no reutilizan artefactos 0.2. OBTENER_EXE_Y_APK.cmd permite que el usuario autorice una publicación Git desde un clon aislado, seguida del workflow Windows/Android y la descarga verificada por commit. No se ha ejecutado remotamente esta revisión. Ningún iniciador toca DATA ni cambia main mediante force-push.
