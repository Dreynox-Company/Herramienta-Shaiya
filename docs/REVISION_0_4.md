# Auditoría 0.4.0

Base: 20520d37030afe5e7d34fc75241e0dadb2e91d99 (0.3.1).

Se ha revisado el código de cada control, sus conexiones de escena y su gestión de errores. Las pruebas locales usan Dart 3.13.3/Flutter 3.47.4, renderizador Dart real sobre EGL/GLES3 y los recursos proporcionados, no reconstrucciones visuales. La ventana de Flutter en Windows se prueba por separado en CI.

## Hallazgos corregidos

- Semantic head de un suplemento solo se utiliza cuando su perfil coincide; un índice fuera del esqueleto se rechaza.
- La prueba de metadatos de rostros tenía un patrón `face00(1_2|9|10)` que no coincidía con `face010`; el patrón se corrigió. La malla original face010 sí existe y se renderizó con su textura tatuada.
- El lector respeta un SAH que solicita datos más allá del final del SAF: `patch2` de las referencias tiene un rango hasta 128 en un SAF de 122 bytes. Se mantiene como rechazo esperado, no se eliminan límites para hacer pasar la muestra.
- La opción de carga de archivo está conectada a la misma canalización de catálogos/modelos/texturas que la carpeta; conserva la biblioteca anterior si falla.
- Streaming mantiene el lector de su biblioteca original, sin depender del catálogo mutable mientras llegan cargas tardías.
- El suplemento de vuelo de 16 arquetipos se empaqueta por separado de las fuentes y del DATA original.

## Comprobaciones locales ejecutadas

La ejecución original previa a correcciones menores pasó 164 pruebas Dart/Flutter y el análisis sin incidencias. El lector recorrió 45.566 recursos y catalogó las 18.269 DDS. Los 20 arquetipos restauraron su cuerpo base; 16 perfiles suplementarios coincidieron con sexo y jerarquía.

En el renderizador EGL/GLES se comprobaron: cuerpo inicial, traje de Navidad frente/espalda sin pantalón base, rostro gris 001_2 y tatuajes 009/010, arma+escudo, lanza con clip 054, flotación, vuelo, rotación de alas, límites y conservación de claves de cabeza y mapa exterior con sectores. Todas esas capturas terminaron con error GL=0.

Se ejecuta nuevamente análisis y pruebas después de los ajustes. El resultado definitivo y las capturas de Windows están en los artefactos del workflow de esta revisión, no en los historiales 0.2/0.3.1.

## No sobreinterpretar evidencia

La interfaz de selección no equivale a homologar cada recurso. No se garantiza descifrado universal, perfiles de vuelo para esqueletos no suministrados ni todas las coordenadas UV de cada DDS. Los registros no resueltos siguen visibles con diagnóstico.
