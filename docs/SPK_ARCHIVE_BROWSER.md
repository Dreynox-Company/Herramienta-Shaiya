# Explorador DATA.SPK — integración 0.6.3

Esta rama añade a Shaiya Studio un explorador nativo de DATA.SPK con una
experiencia similar a WinRAR/Explorador de Windows:

- árbol de carpetas a la izquierda;
- barra de dirección y navegación por niveles;
- lista central de recursos con nombre, tipo, tamaño e ID;
- búsqueda por nombre o ID y modo recursivo;
- panel de propiedades;
- inspección individual;
- extracción individual;
- extracción completa transaccional;
- inventario JSON;
- importación de un mapa ID -> ruta para nombres reales.

## Seguridad e integridad

DATA.SPK se abre siempre en solo lectura. El lector usa rangos del archivo y
nunca carga los 3+ GiB completos en RAM. Antes de montar el catálogo valida:

1. firma y versión;
2. offsets/tamaños de cabecera;
3. SHA-256 del índice contra el perfil local;
4. AES-GCM del índice;
5. frame Zstandard;
6. 96 bytes exactos por registro;
7. redundancia de tamaños;
8. cobertura contigua de la región de datos;
9. relaciones entre recursos fragmentados y la tabla auxiliar.

Una extracción completa se escribe primero en una carpeta *.partial y solo se
publica al final. Un fallo o cancelación elimina exclusivamente esa carpeta
staging y nunca modifica DATA.SPK.

## Nombres

El índice observado usa identificadores de 64 bits en vez de guardar las rutas
en claro. Shaiya Studio no inventa nombres. Un recurso sin ruta resuelta sigue
visible bajo:

    _SPK_SinNombre/Simples
    _SPK_SinNombre/Fragmentados

Un spk-name-map.json puede resolver IDs a rutas como Character/..., Item/...,
Terrain/..., etc. Los recursos no incluidos en el mapa permanecen visibles.

## Perfil criptográfico

Las claves observadas no se publican en GitHub. El usuario selecciona un perfil
JSON local, o lo coloca junto a DATA.SPK como:

    data.spk.profile.json
    spk-crypto-profile.json

El perfil incluye el SHA-256 del índice y el material AES-GCM correspondiente.
Si el perfil no trae material de recursos, el índice se puede explorar pero no
se permite fingir que un payload fue extraído correctamente.

La extracción completa también permanece deshabilitada mientras la regla
criptográfica de los recursos fragmentados no esté validada.

## Estado de esta rama

Se integra la capa de montaje/indexado y la interfaz de archivo. El siguiente
gate es importar el perfil de recursos obtenido por la observación dirigida y
validar el nonce/tag de los 1.467 recursos fragmentados; entonces el botón
"Extraer todo" queda habilitado para el SPK observado y la misma fuente puede
conectarse al catálogo 3D.


## CI gate

The focused SPK format/profile tests pass after deterministic Dart formatting.
The branch is now ready for the repository-wide regression and Windows native
build. Full archive extraction remains intentionally fail-closed until the
fragmented-resource crypto profile is validated.
