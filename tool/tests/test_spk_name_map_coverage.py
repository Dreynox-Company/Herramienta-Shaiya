import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
NAME_MAP = ROOT / 'profiles' / 'spk-name-map-a3ea7e3b.json'
EXPECTED_INDEX = 'a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f'

CODES = (
    'humf', 'huwf', 'humm', 'huwm',
    'elmr', 'elwr', 'elmm', 'elwm',
    'vimm', 'viwm', 'vimr', 'viwr',
    'demf', 'dewf', 'demr', 'dewr',
)


def race_for(code: str) -> str:
    if code.startswith('hu'):
        return 'human'
    if code.startswith('el'):
        return 'elf'
    if code.startswith('vi'):
        return 'vile'
    if code.startswith('de'):
        return 'deatheater'
    raise AssertionError(code)


def slot_for(stem: str):
    patterns = {
        'upper': r'torso|upper',
        'lower': r'lower|trousers|pants',
        'hand': r'hand|glove|gloves|arm',
        'foot': r'foot|boot|boots',
    }
    for slot, token in patterns.items():
        if re.search(r'(^|_)(?:' + token + r')(?=_|[0-9]|$)', stem):
            return slot
    return None


class SpkNameMapCoverageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(NAME_MAP.read_text(encoding='utf-8'))
        cls.strong = {
            key: row['path']
            for key, row in cls.data.get('hints', {}).items()
            if isinstance(row, dict)
            and row.get('confidence') == 'strong-inferred'
            and isinstance(row.get('path'), str)
        }

    def test_map_is_bound_to_the_validated_index(self):
        self.assertEqual(self.data.get('spkIndexSha256'), EXPECTED_INDEX)
        self.assertEqual(self.data.get('stats', {}).get('strongInferred'), len(self.strong))
        self.assertGreaterEqual(len(self.strong), 16000)

    def test_strong_routes_can_reconstruct_core_character_bodies(self):
        paths = [value.lower() for value in self.strong.values()]
        textures = {}
        for path in paths:
            if not path.startswith('character/') or '/dds/' not in path:
                continue
            if not re.search(r'\.(dds|tga|png|bmp)$', path):
                continue
            parts = path.split('/')
            stem = pathlib.PurePosixPath(path).stem
            textures[(parts[1], stem)] = path

        complete = set()
        coverage = {}
        for code in CODES:
            race = race_for(code)
            root = f'character/{race}/3dc/'
            slots = set()
            for path in paths:
                if not path.startswith(root) or not path.endswith('.3dc'):
                    continue
                stem = pathlib.PurePosixPath(path).stem
                if not stem.startswith(code + '_'):
                    continue
                slot = slot_for(stem)
                if slot and (race, stem) in textures:
                    slots.add(slot)
            coverage[code] = slots
            if {'upper', 'lower', 'hand', 'foot'} <= slots:
                complete.add(code)

        expected = {
            'humf', 'huwf', 'humm', 'huwm',
            'elmr', 'elwr', 'elmm', 'elwm',
            'demf', 'dewf', 'demr', 'dewr',
        }
        self.assertTrue(expected <= complete, coverage)
        self.assertGreaterEqual(len(complete), 12)


if __name__ == '__main__':
    unittest.main()
