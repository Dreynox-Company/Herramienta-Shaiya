# Cuerpos completos y perfiles Nude · 0.3.1

## Corrección de cuerpos incompletos

Los conjuntos se enlazan por identidad de recurso, no por el índice de su tabla. El agrupador reconoce también `Trousers`, `Arm`, `Body` y variantes de nombres de manos y botas. La ausencia de una fila de pantalón **no demuestra** que el torso sea un traje integral: la cobertura de una pieza faltante se comprueba con la geometría y la referencia base del mismo arquetipo. Cuando no hay prueba de cobertura, se conserva la pieza base.

Al cambiar de raza o arquetipo se prepara un cuerpo completo antes de reemplazar la escena anterior. El conjunto inicial y «Base original · cuerpo completo» no necesitan una segunda pulsación de Restaurar. El rostro y el cabello se mantienen al cambiar de conjunto dentro del mismo arquetipo; no se mezclan rostros de otra raza.

## Disponibilidad real de Nude

La biblioteca inspeccionada contiene 20 arquetipos. No se encontró un conjunto original completo de malla y textura Nude identificable para ninguno de ellos. Las bases revisadas contienen ropa o armadura. Los archivos `_M.dds` son máscaras y `body001` puede ser una armadura: no se etiquetan falsamente como piel desnuda.

«Base original» está disponible para todos los arquetipos. «Nude» utiliza exclusivamente recursos originales compatibles que estén realmente disponibles. No reconstruye genitales, no recolorea ropa como si fuese piel y no aplica una capa de censura a la textura cargada. Si no hay un perfil completo, explica la ausencia y conserva la apariencia actual.

## Añadir recursos de cuerpo propios a DATA

El lector reconoce conjuntos MLT con nombres explícitos `nude`, `naked`, `desnudo` o `desnuda`. También admite el archivo opcional `DATA/shaiya-studio-bodies.json`, para indicar recursos ya existentes sin renombrar las tablas del juego.

Esquema (los nombres del ejemplo son ilustrativos y **no** archivos incluidos):

```json
{
  "version": 1,
  "archetypes": {
    "human/humf": {
      "parts": {
        "upper": {"mesh": "Character/Human/3dc/mi_torso.3dc", "texture": "Character/Human/dds/mi_torso.dds", "alpha": 1},
        "lower": {"mesh": "Character/Human/3dc/mis_piernas.3dc", "texture": "Character/Human/dds/mis_piernas.dds", "alpha": 1},
        "hand": {"mesh": "Character/Human/3dc/mis_manos.3dc", "texture": "Character/Human/dds/mis_manos.dds", "alpha": 1},
        "foot": {"mesh": "Character/Human/3dc/mis_pies.3dc", "texture": "Character/Human/dds/mis_pies.dds", "alpha": 1}
      }
    }
  }
}
```

Cada perfil debe pertenecer a la raza y al esqueleto del arquetipo. Un cuerpo de una sola pieza puede omitir `lower`, `hand` o `foot` únicamente si la geometría del torso cubre esas zonas. Un perfil parcial o con archivos inexistentes se rechaza antes de reemplazar el personaje. No se modifica ningún archivo de DATA. El programa permite perfiles diferentes para cada uno de los 20 arquetipos.

El archivo JSON y las texturas permanecen en la biblioteca local. No deben copiarse a este repositorio.
