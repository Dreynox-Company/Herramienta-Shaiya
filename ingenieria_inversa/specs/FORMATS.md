# Recursos y contratos implementados

No se deduce soporte a partir de la extensión. Los lectores validan tamaños,
recuentos y números; las variantes desconocidas mantienen su diagnóstico.

| Familia | Código | Alcance |
|---|---|---|
| 3DC / 3DO / ANI / materiales | lib/core/formats.dart | Mallas, UV, índices, pesos y poses; colas conocidas explícitas. |
| DDS | lib/core/textures.dart | Texturas y atlas. Las máscaras no son conjuntos alternativos. |
| SAH/SAF | lib/core/archive_index.dart, lib/data/archive_source.dart, archive_write.dart, archive_export.dart | Lectura, extracción y escritura transaccional de variantes reconocidas. |
| Carpeta y construcción | lib/data/library.dart, directory_pack.dart | Biblioteca lógica y creación del par desde DATA. |
| SData | lib/editor/schema_reader.dart, primitive_schemas.dart, structure_editor.dart | Esquemas, campos y operaciones estructurales comprobados. Los campos desconocidos no se reinterpretan arbitrariamente. |
| WLD / SVMAP | lib/core/world_resources.dart, lib/ui/editor_map.dart y renderer | Geometría/instancias/ubicaciones según variante, caché y proximidad. No garantiza todos los scripts ni colisión de todos los edificios. |
| Texto | lib/core/game_text_codec.dart, legacy_text.dart, client_locale.dart | SPN, Windows-1252 y Unicode cuando corresponde; conservación de codificación. |
| Suplementos ANI | lib/core/extra_motion.dart | Perfil de arquetipo/sexo/jerarquía con hashes, sin sustituir ANI originales. |
| Partidas | lib/offline/save_store.dart | Revisiones, hash, transacciones, papelera/restauración. No intercambiables con partidas nativas. |
| Escena compartida | lib/offline_game/scene_profile.dart | JSON versionado con IDs, equipo, anclajes y cámara; validación y reversión. |

Leer columnas de una habilidad no reproduce sus reglas; cargar WLD no completa
pathfinding ni misiones. El botín puede depender del servidor. Se necesitan
pruebas específicas antes de convertir esos datos en mecánicas del juego propio.

Pruebas: `test/`, `tool/tests/`, `integration_test/native_studio_test.dart`,
`integration_test/local_game_test.dart` e `ingenieria_inversa/tests/`. Los recursos
sintéticos verifican contratos; el aspecto de cada recurso original necesita
revisión visual propia. No se afirma que todas las DDS tengan una malla válida.
