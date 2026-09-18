# Shaiya Studio 0.5.0 · uso y exportación segura

## Programa Windows
Extrae TODO el ZIP del programa en una carpeta nueva y ejecuta `herramienta_shaiya.exe`. Conserva DLL, carpeta `data` de Flutter y `Extras` si viene incluida. La biblioteca DATA del juego debe permanecer separada.
Pulsa DATA para elegir carpeta o un par `.sah` + `.saf`. No requiere recompilar el juego. La aplicación no modifica el origen durante la lectura.

## Editor de datos
Pulsa **Editor de datos**, en el centro de la barra superior. Selecciona un SData o SVMAP, busca el registro y el campo y pulsa para modificarlo. `Deshacer` / `Rehacer` recuperan los valores de la sesión. El panel de cambios muestra antes/después.
Elige la codificación de texto de tu cliente. Para clientes españoles antiguos prueba **Windows-1252**; para UTF-8 usa UTF-8. La detección automática no autoriza una escritura de texto ambigua. El original se conserva íntegro al exportar sin cambios.

En **Exportar / herramientas**:
- **Exportar archivo verificado** genera una copia; no sustituye el archivo abierto.
- **Guardar / aplicar parche JSON** comprueba SHA-256 y valores anteriores antes de aplicarlo.
- **Extraer archivo a DATA** crea una carpeta nueva con todos los registros del SAH/SAF y un manifiesto de hashes.
- **Guardar un par SAH/SAF nuevo** incluye las tablas modificadas, verifica la relectura y conserva el original.
- **Importar tabla / CSV servidor** abre una fuente adicional; no se conecta a SQL ni despliega cambios.

Los campos con signo admiten negativos; los campos sin signo los rechazan sin desbordarse. Los valores negativos de monedas/precios requieren comprobar las reglas del cliente/servidor. La edición de SAH/SAF no cambia automáticamente la economía autoritativa del servidor.

## Alas y monturas
El suplemento `Extras/flight.json.gz` se carga al iniciar cuando está junto al programa; también puede importarse en Alas y monturas. No reemplaza ANI originales. La revisión del suplemento 0.5 contiene hover/vuelo y seis ataques montados para cada uno de los 16 perfiles compatibles.
El asiento se ajusta sobre una superficie animada; altura y avance son correcciones relativas. Las monturas sin superficie segura muestran diagnóstico y siguen admitiendo calibración. No se afirma un ajuste visual perfecto de todas las variantes.
Un ataque desde vuelo baja gradualmente al suelo antes de iniciarse. Al terminar la guardia vuelve al vuelo, si corresponde.

## Fuentes y compilación
El ZIP de fuentes es distinto al ZIP del programa. Para compilar requiere Flutter 3.47.4, SDK de destino y Python 3. Windows necesita Visual Studio C++; Android necesita Java/Android SDK/NDK y CMake 3.31.4.
`COMPILAR.ps1 -Plataforma Windows -Ejecutar` o `py -3 tool/build.py --platform windows --run`.
Prueba adicional nativa: `COMPILAR.ps1 -Plataforma Windows -Integracion`.
Android: `COMPILAR.ps1 -Plataforma Android`. APK de depuración: no es firma comercial y puede no actualizar una instalación firmada con otra clave.
El método de compilación remota solicita PUBLICAR y usa la sesión Git del usuario; crea una rama, no fusiona main ni publica DATA.

## Cobertura
Consulta `docs/revision-05.md` para esquemas, campos desconocidos, extracción Android y comprobaciones reales. No instales una copia editada en producción sin un respaldo y una prueba compatible del cliente y servidor.
