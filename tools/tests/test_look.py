"""The app's colours are the daemon's tables (look.py), in the same order: the firmware checks itself against them too."""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "daemon"))
import look  # noqa: E402


class SameAsTheDaemon(unittest.TestCase):
    def test_skins_and_accents(self):
        app = (ROOT / "Sources/TTYCat/Look.swift").read_text()
        skins = [(n, int(b, 16), int(s, 16)) for n, b, s in re.findall(r'Skin\(name: "(\w+)", body: 0x(\w{6}), shade: 0x(\w{6})\)', app)]
        accents = [(n, int(v, 16)) for n, v in re.findall(r'Accent\(name: "(\w+)", value: 0x(\w{6})\)', app)]
        self.assertEqual(skins, look.SKIN_COLOURS)
        self.assertEqual(accents, look.ACCENT_COLOURS)


if __name__ == "__main__":
    unittest.main()
