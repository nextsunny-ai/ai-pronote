import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "static" / "index.html").read_text(encoding="utf-8")


class LibraryReopenContractTests(unittest.TestCase):
    def test_whole_card_and_keyboard_open_the_item(self):
        self.assertIn('role="button"', HTML)
        self.assertIn('tabindex="0"', HTML)
        self.assertIn("openLibraryItem(id, type)", HTML)
        self.assertIn("if (e.target !== card) return", HTML)
        self.assertIn("if (e.key === 'Enter' || e.key === ' ')", HTML)

    def test_linked_recording_and_note_do_not_duplicate_a_meeting_card(self):
        self.assertIn("const meetingByRecording = new Map()", HTML)
        self.assertIn("if (meetingByRecording.has(a.id)) return", HTML)
        self.assertIn("if (m.standalone && m.note && m.note.trim())", HTML)

    def test_recovered_server_result_can_be_opened(self):
        self.assertIn("async function ensureMeetingForRecord", HTML)
        self.assertIn("source: r.source || 'recording'", HTML)
        self.assertIn("await ensureMeetingForRecord(record)", HTML)

    def test_pending_and_failed_items_explain_their_state(self):
        self.assertIn("data-library-status", HTML)
        self.assertIn("처리 중", HTML)
        self.assertIn("다시 시도", HTML)
        self.assertIn("원본 녹음이 이 기기에 없습니다", HTML)


if __name__ == "__main__":
    unittest.main()
