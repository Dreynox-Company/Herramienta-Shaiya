"""Compatibilidad Linux SOLO para validación interna con flutter_angle 0.4.2.

No modifica los builds Windows o Android. Corrige dos declaraciones C++
inconsistentes del paquete publicado. El fallo se detectó compilando, no se
oculta con flags que ignoren errores. Retirar cuando upstream lo incorpore.
"""
from pathlib import Path
from urllib.parse import urlparse, unquote
import json

config = Path('.dart_tool/package_config.json').resolve()
packages = json.loads(config.read_text())['packages']
entry = next(p for p in packages if p['name'] == 'flutter_angle')
uri = entry['rootUri']
root = Path(unquote(urlparse(uri).path)) if uri.startswith('file:') else (config.parent / uri).resolve()
header = root / 'linux/include/fl_angle_texture_gl.h'
text = header.read_text()
if 'EGLContext eglContext;' not in text:
    assert '  EGLDisplay eglDisplay;' in text, 'Cambió el encabezado upstream; revisar compatibilidad.'
    header.write_text(text.replace('  EGLDisplay eglDisplay;', '  EGLContext eglContext;\n  EGLDisplay eglDisplay;'))
source = root / 'linux/fl_angle_texture_gl.cc'
text = source.read_text()
if 'uint32_t *width,' not in text:
    assert '  uint32_t *name,\n  GError **error' in text, 'Cambió la firma del callback upstream.'
    text = text.replace('  uint32_t *name,\n  GError **error', '  uint32_t *name,\n  uint32_t *width,\n  uint32_t *height,\n  GError **error')
    text = text.replace('  *name = f->name;', '  *name = f->name;\n  *width = f->width;\n  *height = f->height;')
    source.write_text(text)
print('Compatibilidad del backend Linux de validación preparada.')
