import unittest

import main


class TranscriptCorrectionTests(unittest.TestCase):
    def test_auto_language_maps_to_whisper_detection(self):
        self.assertIsNone(main.whisper_language("auto"))
        self.assertIsNone(main.whisper_language(""))
        self.assertEqual(main.whisper_language("ko"), "ko")
        self.assertEqual(main.whisper_language("en"), "en")
        with self.assertRaises(ValueError):
            main.whisper_language("../../invalid")

    def test_mixed_language_merge_keeps_each_script_in_timestamp_order(self):
        korean = [
            {"start": 0.0, "end": 2.0, "text": "오늘 회의를 시작합니다."},
            {"start": 3.0, "end": 5.0, "text": "영어처럼 들린 가짜 번역"},
        ]
        english = [
            {"start": 2.1, "end": 3.0, "text": "Release candidate passed."},
            {"start": 5.1, "end": 6.0, "text": "다음 회의"},
        ]
        merged = main.merge_mixed_language_segments(korean, english)
        self.assertEqual(
            [segment["text"] for segment in merged],
            ["오늘 회의를 시작합니다.", "Release candidate passed.", "영어처럼 들린 가짜 번역"],
        )
        self.assertEqual([segment["id"] for segment in merged], [1, 2, 3])

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
