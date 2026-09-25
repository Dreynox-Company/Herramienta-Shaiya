"""Install exact original PNG icon frames and generate the embedded fallback.

The full user-supplied original artwork in Extras/Branding is a distribution
supplement; it is never fetched over the network or confused with game DATA.
"""
from pathlib import Path
import base64
import hashlib
import struct

EXPECTED = '69b78550a8020305438a524e567899f7845f8fb4d7ef1476f5625b3b9a1afb23'


def prepare(root: Path) -> bytes:
    encoded = (root / 'platform/branding/app_icon.ico.b64').read_text().strip()
    icon = base64.b64decode(encoded, validate=True)
    if hashlib.sha256(icon).hexdigest() != EXPECTED:
        raise ValueError('ShStudio icon transport integrity mismatch')
    reserved, kind, count = struct.unpack_from('<HHH', icon)
    if reserved or kind != 1 or count != 5:
        raise ValueError('Unexpected ICO header')
    sizes = []
    biggest = None
    for i in range(count):
        width, height, _, _, _, _, size, offset = struct.unpack_from('<BBBBHHII', icon, 6 + 16*i)
        image = icon[offset:offset+size]
        if width != height or len(image) != size or not image.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Invalid icon frame')
        sizes.append(width or 256)
        if (width or 256) == 128:
            biggest = image
    if sizes != [16, 32, 48, 64, 128] or biggest is None:
        raise ValueError('Unexpected ICO frame sizes')
    asset = root / 'assets/branding/shstudio-emblem.png'
    asset.parent.mkdir(parents=True, exist_ok=True)
    asset.write_bytes(biggest)
    return icon


if __name__ == '__main__':
    prepare(Path(__file__).resolve().parents[1])
