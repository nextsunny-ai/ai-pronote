import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class InkContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = (ROOT / "static" / "index.html").read_text(encoding="utf-8")
        cls.js = (ROOT / "static" / "v15-ink.js").read_text(encoding="utf-8")

    def test_text_and_ink_tabs_and_accessible_canvas_exist(self):
        for token in (
            'id="noteModeText"', 'id="noteModeInk"', 'id="inkCanvas"',
            'aria-label="필기 캔버스"', 'role="tablist"',
        ):
            self.assertIn(token, self.html)

    def test_vector_schema_tools_pressure_and_history(self):
        for token in (
            'schemaVersion: 1', 'pointerdown', 'pointermove', 'pressure',
            'pen', 'eraser', 'arrow', 'rect', 'ellipse', 'undo', 'redo',
            'startMs', 'endMs',
        ):
            self.assertIn(token, self.js)

    def test_indexeddb_preview_and_audio_anchor_contract(self):
        for token in (
            'indexedDB.open', 'pronote-ink-v1', 'toBlob', 'image/webp',
            'inkTimeAnchors', 'currentTime', 'meetingId',
        ):
            self.assertIn(token, self.js)

    def test_clear_requires_confirmation_and_responsive_controls(self):
        self.assertIn('confirm(', self.js)
        self.assertIn('.ink-toolbar', self.html)
        self.assertIn('@media (max-width: 639px)', self.html)

    def test_meeting_switch_and_pointer_are_guarded(self):
        for token in ('structuredClone(doc.strokes)', 'loadGeneration', 'loadedMeetingId',
                      'activePointerId', 'event.pointerId!==activePointerId', 'pointercancel'):
            self.assertIn(token, self.js)
        self.assertIn('aspect-ratio:1200/700', self.html)

    def test_shape_eraser_and_account_cleanup_contract(self):
        for token in ('segmentDistance', "item.tool==='rect'", 'clearAll', '.objectStore(STORE).clear()'):
            self.assertIn(token, self.js)

    def test_every_current_meeting_change_has_sync_ink_switch(self):
        self.assertEqual(
            self.html.count("localStorage.setItem('ai_pronote.current_view_meeting.v1'"),
            self.html.count('PronoteInk?.switchMeeting'),
        )
        self.assertIn("/^(https?:|mailto:)/i.test(safe)", self.html)
        self.assertIn("switchGeneration", self.js)
        self.assertIn("saveQueue.catch(()=>{})", self.js)
        self.assertIn("switchMeeting?.(loadedMeetingId || 'draft')", self.html)
        self.assertIn("switchMeeting?.(previousMeetingId || 'draft')", self.html)


if __name__ == "__main__":
    unittest.main()
