# Entrega 0.5.0+7

Esta revisión incorpora el editor de SData/SVMAP, precios y botín, copias SAH/SAF verificadas, codificación de texto explícita y las mejoras de asiento y aterrizaje. No sustituye la biblioteca DATA del usuario ni se conecta a su servidor.

## Correcciones del cierre

Los controles principales se distribuyen en varias filas según el ancho: Deshacer, Rehacer y Guardar no quedan fuera de la vista. El panel de bienvenida permite desplazamiento vertical. Las pruebas hacen fallar un clic fuera del área interactiva.

Las tablas DB importadas se reconocen también fuera de BinarySData; los documentos importados permanecen seleccionables en la sesión. La importación aplica el presupuesto de memoria de la sesión. Los campos opacos marcan el documento como parcial: conservarlos no equivale a interpretar su contenido.

## Cobertura original, corregida

La reauditoría local del 18 de septiembre incluye 137 SData/SVMAP, todos con exportación sin cambios idéntica. Son 121 con esquema estructural completo y 16 parciales o solo inspección. Esto corrige el recuento anterior 122/15: la extensión de cinco bytes de Monster ahora se cuenta correctamente como parcial. No se ha perdido la lectura de sus campos conocidos.

El informe JSON de entrega identifica cada archivo. La prueba de edición automática de la auditoría cambia un campo de muestra y comprueba su relectura; no afirma haber ejecutado todos los parámetros dentro del cliente y servidor del juego.

## Ejecutar

Windows: extrae completamente el ZIP en una carpeta nueva y abre herramienta_shaiya.exe. Conserva DLL y data (Flutter). DATA del juego es una ubicación distinta. Conecta DATA o el par SAH/SAF, y pulsa Editor de datos. Para instalar cambios usa únicamente las copias exportadas y conserva una copia de seguridad del cliente.

Android: APK de pruebas, no firmado comercialmente. Una instalación con firma distinta puede no actualizar la versión anterior; no desinstales sin guardar tus datos. La extracción/reconstrucción de carpetas se entrega en escritorio, no en Android.

## Alcance de la verificación

build-provenance.json vincula el EXE a su commit y ejecución. Las pruebas de ventana Windows usan recursos sintéticos propios; la auditoría del DATA original es independiente. La compilación de un APK no equivale a una prueba en un teléfono físico.

La modificación del cliente no cambia por sí sola las tablas autoritativas del servidor. Formatos propietarios, bloques no interpretados y combinaciones visuales no examinadas siguen requiriendo validación específica. No se incluyen archivos del juego en GitHub.
