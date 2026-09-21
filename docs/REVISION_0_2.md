# Revisión 0.2 — objetivos de regresión

Estado: en desarrollo; no describe funciones ya comprobadas.

- El inicio utiliza exclusivamente reposo terrestre o pose de enlace, nunca natación como respaldo.
- W / WASD: caminar; Shift con desplazamiento: correr. Soltar teclas, perder foco o abrir un selector cancela el movimiento.
- Animaciones sincronizadas de jinete y montura; transiciones sin respuestas asíncronas obsoletas.
- Selectores con búsqueda, elemento activo resaltado, posición recordada y navegación ↑/↓. Las teclas del selector no mueven al personaje.
- Alas ancladas al espacio local del torso, independientes de los desplazamientos del jinete y conservadas al cambiar equipo o montura.
- Paneles laterales compactos y plegables, barra de animación fuera del visor y controles de combate accesibles.
- Cielo visible en mapas; carga de recursos originales cuando el formato está soportado, sin inferir que un WLD define un cielo que no se ha interpretado.
- Pruebas de regresión de selección, entrada, estados de animación y composición de anclajes; compilaciones Windows y Android trazables a la misma revisión.

No se incorporan recursos originales de DATA al repositorio ni se modifica la biblioteca del usuario. Cada resultado de validación se documentará separado de lo que solo está implementado en código.
