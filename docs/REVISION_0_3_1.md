# Revisión 0.3.1

Integra la entrega 0.3 (armas/3DO, mapa completo, DG, navegación, salto, varios oponentes y efectos de previsualización) con la corrección de composición corporal al cambiar de arquetipo.

- Relación de piezas `Trousers` y `Arm`, incluida la familia Panda.
- Un torso se considera integral solo cuando su geometría demuestra cobertura de la pieza ausente.
- Conjunto «Base original» completo y estable, independiente del anterior.
- Rostro y cabello conservados al cambiar de equipo compatible.
- Soporte de perfiles de malla/textura Nude reales con validación, sin falsificar una textura vestida.
- Restauración de apariencia compatible con los identificadores de perfiles corporales.
- Regresiones unitarias y nativas para un arquetipo modular de cuatro piezas.

## Evidencia local

94 pruebas Dart/Flutter pasaron en el motor de pruebas Flutter con recursos sintéticos. El análisis estático no encontró incidencias. La biblioteca original permitió comprobar las composiciones iniciales y de base de 20 arquetipos (40 estados, sin errores de malla) y 1.355 combinaciones de conjunto sin regiones corporales ausentes en la composición. Esto no equivale a homologar visualmente cada combinación ni demuestra disponibilidad de desnudos: los 20 arquetipos carecen de un conjunto Nude completo identificado en esta biblioteca.

Los ejecutables de Windows y Android solo deben distribuirse desde un trabajo CI satisfactorio de esta revisión. La prueba nativa de Windows abre el renderizador con geometrías sintéticas; el APK de Android es de pruebas y no constituye una validación sobre un teléfono físico.
