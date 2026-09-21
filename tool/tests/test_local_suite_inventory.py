"""Prevent local validation from silently omitting new Dart test suites."""
from pathlib import Path
import re
import unittest

class LocalSuiteInventoryTest(unittest.TestCase):
    def test_every_dart_test_is_imported_and_called_once(self):
        root = Path(__file__).resolve().parents[2]
        expected = {p.name for p in (root / "test").glob("*_test.dart")}
        content = (root / "tool" / "run_all_local.dart").read_text(encoding="utf-8")
        imports = re.findall(r"import ['\"]\.\./test/([^'\"]+)['\"] as (\w+);", content)
        self.assertEqual(expected, {name for name, _ in imports})
        self.assertEqual(len(expected), len(imports), "Duplicated suites")
        for _, alias in imports:
            self.assertEqual(1, len(re.findall(r"\b" + re.escape(alias) + r"\.main\(\);", content)), alias)

    def test_flight_actions_opt_out_of_movement_cancellation(self):
        root = Path(__file__).resolve().parents[2]
        main = (root / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertRegex(main, r"onFlightToggle:\s*\(\)\s*=>\s*act\(scene\.toggleFlight,\s*preserveMovement:\s*true\)")
        self.assertRegex(main, r"onChanged:\s*\(enabled\)\s*=>\s*act\([\s\S]{0,150}requestFlight\(enabled\)[\s\S]{0,100}preserveMovement:\s*true")
        self.assertIn("await scene.runUserAction(action, preserveMovement: preserveMovement)", main)
        self.assertIn("<  —  alternar vuelo con alas", main)

if __name__ == "__main__":
    unittest.main()
