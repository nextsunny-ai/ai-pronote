import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "static" / "index.html"


class HtmlSourceIntegrityTests(unittest.TestCase):
    def test_html_contains_no_nul_bytes(self):
        self.assertNotIn(b"\x00", HTML.read_bytes())

    def test_markdown_code_block_placeholder_survives_html_parsing(self):
        source = HTML.read_text(encoding="utf-8")

        self.assertIn("return '\\uE000CODE' + (codeBlocks.length - 1) + '\\uE001';", source)
        self.assertIn("/\\uE000CODE(\\d+)\\uE001/g", source)


if __name__ == "__main__":
    unittest.main()
