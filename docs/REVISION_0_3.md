# Revisión 0.3.0+4 · cierre de integración local

## Entrega

Fuentes Flutter completas con lectores, renderizador, interfaz, pruebas, configuración CI y scripts para compilar Windows y Android. La base consultada en GitHub sigue en `58d23b3a24c089a95f1ba143c6ae32f7fb3cdbfe`. Esta entrega no declara un nuevo commit remoto ni aporta binarios Windows/Android recompilados.

## Correcciones de mayor impacto

1. Los 3DO que terminan en ocho bytes nulos se interpretan sin desactivar la validación del formato. También se conserva la opacidad en armas IT2 de modo -1; no basta con leer su malla si el material después elimina sus píxeles.
2. En SMOD, los valores inválidos de vértices no referenciados se aíslan con diagnóstico. Los datos utilizados por los triángulos siguen exigiendo valores finitos. No se inventan posiciones válidas en superficies dañadas.
3. El motor three_js no calculaba correctamente la visibilidad de grupos instanciados: los edificios cargados se ocultaban porque se evaluaba el prototipo en el origen. Se evalúan ahora los límites reales de cada grupo transformado.
4. La llegada a una DG considera la altura del portal. No se usa el máximo vertical de la mazmorra, que podía colocar al personaje en el techo por encima de su entrada.
5. El movimiento transforma la entrada según la cámara y orienta el modelo teniendo en cuenta el cambio de sistema de coordenadas. El salto usa la animación original y una trayectoria con gravedad, con aterrizaje y bloqueo de doble salto.
6. Cada impacto captura el ID del oponente atacado. Seleccionar otro mob durante la animación no transfiere el daño.
7. Se restablecen todos los slots al cambiar conjunto. Cara/cabello permanecen independientes; el casco no se introduce implícitamente y un traje integral no hereda guantes/botas de otro set. La protección opcional de cabeza integrada no modifica DATA.
8. `.gitignore` ahora excluye DATA solo en la raíz. `lib/data` es código indispensable y forma parte del manifiesto y del ZIP.

## Evidencia

| Verificación | Resultado |
|---|---|
| Analizador Dart de todas las fuentes entregadas | Sin incidencias |
| Pruebas Dart/Flutter | 85 correctas |
| Pruebas Python de integridad y herramientas | 7 correctas |
| Prueba original EGL/GLES | 14 comprobaciones correctas |
| Arma 06041 visible y unida al actor | Comprobado con archivo original |
| Apulune | 274 objetos colocados, cielo y animación VANI |
| Cloron | Geometría DG, suelo del portal y posición del personaje comprobados |
| Ventana nativa Windows de la revisión 0.3 | No ejecutada en esta sesión |
| Dispositivo físico Android de la revisión 0.3 | No ejecutado en esta sesión |

La prueba gráfica utiliza Flutter tester y un framebuffer EGL/GLES real. Se sustituye únicamente el puente de registro de texturas de ventana; los lectores, las mallas, el skinning, los materiales, las texturas y las llamadas de dibujo son los de la aplicación. Las capturas no son una simulación visual generada.

La configuración CI y `COMPILAR.ps1 -Integracion` añaden una prueba de la ventana Windows con recursos sintéticos para ejecutarse en la máquina de compilación. Incluir esa prueba no significa haberla ejecutado aquí.

## Alcance restante

No se declara compatibilidad visual exhaustiva con todas las combinaciones de DATA. No se ha homologado la receta exacta de cada lapisia/elemento; la función se presenta como previsualización configurable. Agua avanzada y el intérprete completo de EFT no están incluidos. Algunos SMOD y el 3DO de flecha contienen variantes o datos que permanecen diagnosticados. Las colisiones dependen de la geometría legible y no sustituyen las reglas del servidor original.
