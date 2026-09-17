> Histórico de una revisión anterior. El estado actual está en REVISION_0_3.md y README.md.

# Auditoría de recursos originales

La biblioteca se procesó localmente. No se suben mallas, texturas, sonidos ni el archivo RAR a GitHub.

## Primera ejecución del lector Dart compilado (5eb90a5)

Se extrajeron 44.007 archivos de recursos de las cinco partes RAR, verificando integridad y tamaño durante la extracción. La auditoría de los siete formatos principales recorrió **31.480 archivos**. Resultado: **31.307 interpretados y 173 incompatibilidades**. No son 31.307 combinaciones visualmente verificadas.

| Formato | Interpretados |
|---|---:|
| 3DC | 7.431 |
| ANI | 5.317 |
| MLT | 142 |
| ITM | 19 |
| MON | 19 |
| DDS | 18.249 |
| WLD | 130 |

Los MON auditados incluyen categorías que no se presentan como personajes jugables, como NPC. Los recuentos de monturas por MON pueden repetir un vehículo entre facciones.

## Hallazgos y correcciones

- Los índices de MLT no son el identificador compartido de un set. El conjunto 016 usa distintas posiciones en las tablas de torso y piernas. Los conjuntos ahora se relacionan por sus recursos.
- Un traje integral puede contener las piernas dentro de la malla de torso. La sustitución de sets vacía las selecciones incompatibles y prohíbe añadir un pantalón modular sobre un traje integral.
- `body001` no identifica de forma universal un cuerpo desnudo. La muestra `human_m_fighter_body001` inspeccionada contiene armadura.
- El modo Glow de MLT contiene alfa para brillo. La conversión conserva RGB y fuerza opacidad en ese modo, sin convertir las caras o el cabello en placas opacas.
- Se encontraron tablas `pandaIT2` con 24 perfiles de anclaje y clips ANI cuyo fotograma inicial es negativo. El lector ahora admite ambas variantes.
- Algunos modelos 3DC contienen bloques concatenados; otros son realmente mallas rígidas 3DO con otra extensión. Solo se combinan bloques con matrices de enlace compatibles.
- La auditoría Dart detectó 14 texturas DDS con paleta de 8 bits, incluidas alas. Se añade el decodificador P8 con paleta RGBA y pruebas de transparencia.
- Hay archivos con valores no finitos, matrices singulares y formatos antiguos de capa. No se los declara sanos ni se sustituyen silenciosamente por un material negro. Se deben distinguir datos de vértices inválidos de normales o huesos auxiliares no utilizados antes de rehabilitar un recurso.

## Alcance de la evidencia

La lectura binaria, el análisis estático, las pruebas unitarias, la compilación nativa y el renderizado visual son comprobaciones distintas. Cada una se registra por separado. No se afirma validar exhaustivamente la biblioteca por el hecho de que sus catálogos se puedan enumerar.
