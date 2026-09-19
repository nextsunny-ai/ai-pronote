import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "mobile-update.json"


class MobileUpdateManifestTests(unittest.TestCase):
    def test_manifest_is_publishable_and_points_to_https_download_page(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))

        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(data["version"], "1.0.0")
        self.assertTrue(data["download_url"].startswith("https://"))
        self.assertIn("nextsunny-ai.github.io/ai-pronote", data["download_url"])
        self.assertTrue(data["notes"].strip())


if __name__ == "__main__":
    unittest.main()
