import json
import os
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]


class IPadCompanionContractTests(unittest.TestCase):
    def test_pwa_manifest_and_offline_shell(self):
        manifest = json.loads((ROOT / "static/manifest.webmanifest").read_text(encoding="utf-8"))
        self.assertEqual(manifest["display"], "standalone")
        self.assertEqual(manifest["scope"], "/")
        sizes = {icon["sizes"] for icon in manifest["icons"]}
        self.assertTrue({"152x152", "192x192", "512x512"} <= sizes)
        sw = (ROOT / "static/sw.js").read_text(encoding="utf-8")
        self.assertIn("caches.match", sw)
        self.assertIn("url.pathname.startsWith('/api/')", sw)

    def test_ipad_input_and_secure_context_contract(self):
        html = (ROOT / "static/index.html").read_text(encoding="utf-8")
        ink = (ROOT / "static/v15-ink.js").read_text(encoding="utf-8")
        self.assertIn('name="viewport"', html)
        self.assertIn("viewport-fit=cover", html)
        self.assertIn("serviceWorker.register", html)
        self.assertIn("pointerdown", ink)
        self.assertIn("pressure", ink)
        self.assertRegex(html, r"type=[\"']file[\"']")

    def test_launcher_requires_https_token_and_expiry(self):
        launcher = (ROOT / "start_ipad_companion.ps1").read_text(encoding="utf-8")
        for marker in ("PRONOTE_IPAD_MODE", "PRONOTE_LAN_TOKEN", "PRONOTE_HTTPS_CERT", "PRONOTE_LAN_SESSION_SECONDS"):
            self.assertIn(marker, launcher)
        main = (ROOT / "main.py").read_text(encoding="utf-8")
        self.assertIn("secure=True", main)
        self.assertIn("compare_digest", main)
        self.assertIn("_lan_token_consumed", main)
        self.assertIn("access_log=not IPAD_MODE", main)
        self.assertIn("iPad 모드는 유효한 HTTPS 인증서", main)
        cert_script = (ROOT / "prepare_ipad_certificate.ps1").read_text(encoding="utf-8")
        self.assertNotIn("mkcert -install\"", cert_script)
        self.assertIn("root trust was NOT installed", cert_script)


if __name__ == "__main__":
    unittest.main()
