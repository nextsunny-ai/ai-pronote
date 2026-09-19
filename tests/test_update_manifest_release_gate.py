import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "update-manifest.json"


class UpdateManifestReleaseGateTests(unittest.TestCase):
    def test_unverified_mac_artifact_is_not_published(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        artifacts = data.get("artifacts", {})

        self.assertIn("windows", artifacts)
        self.assertNotIn("mac", artifacts)

    def test_no_platform_reuses_the_windows_artifact(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        artifacts = data.get("artifacts", {})
        windows_url = artifacts["windows"]["url"]

        for platform, artifact in artifacts.items():
            if platform != "windows":
                self.assertNotEqual(artifact.get("url"), windows_url)


if __name__ == "__main__":
    unittest.main()
