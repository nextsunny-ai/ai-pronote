import unittest

import main


class TranscriptCorrectionTests(unittest.TestCase):
    def test_parse_glossary_accepts_arrow_and_equals_and_ignores_comments(self):
        pairs = main.parse_glossary("# 팀 용어\n프로 노트 = AI PRONOTE\n클로 드 -> Claude\n")
        self.assertEqual(pairs, [("프로 노트", "AI PRONOTE"), ("클로 드", "Claude")])

    def test_apply_glossary_prefers_longest_term_and_preserves_raw_result(self):
        result = {
            "full_text": "에이 아이 프로 노트와 프로 노트",
            "speaker_text": "SPEAKER_00: 에이 아이 프로 노트",
            "segments": [{"text": "에이 아이 프로 노트"}],
        }
        corrected = main.apply_glossary_to_result(
            result,
            "에이 아이 프로 노트=AI PRONOTE\n프로 노트=PRONOTE",
        )
        self.assertEqual(corrected["raw_full_text"], "에이 아이 프로 노트와 프로 노트")
        self.assertEqual(corrected["full_text"], "AI PRONOTE와 PRONOTE")
        self.assertEqual(corrected["speaker_text"], "SPEAKER_00: AI PRONOTE")
        self.assertEqual(corrected["segments"][0]["text"], "AI PRONOTE")
        self.assertEqual(corrected["glossary_applied"], 2)

    def test_glossary_is_bounded_and_rejects_empty_source(self):
        with self.assertRaises(ValueError):
            main.parse_glossary("=잘못된 값")
        with self.assertRaises(ValueError):
            main.parse_glossary("\n".join(f"용어{i}=값{i}" for i in range(101)))


if __name__ == "__main__":
    unittest.main()
