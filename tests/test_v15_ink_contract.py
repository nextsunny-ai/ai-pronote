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
        self.assertIn('window.__pronoteAskConfirmation', self.js)
        self.assertIn('window.__pronoteNotify', self.js)
        self.assertNotIn('confirm(', self.js)
        self.assertNotIn('alert(', self.js)
        self.assertIn('window.__pronoteAskConfirmation = askConfirmation', self.html)
        self.assertIn('window.__pronoteNotify = showToast', self.html)
        self.assertIn('.ink-toolbar', self.html)
        self.assertIn('@media (max-width: 639px)', self.html)
        self.assertIn('.mynote-block.fullpage .mynote-fullpage-meta { display:none; }', self.html)
        self.assertIn('.mynote-block.fullpage .mynote-document-head { padding-left:64px; }', self.html)

    def test_meeting_switch_and_pointer_are_guarded(self):
        for token in ('structuredClone(doc.strokes)', 'loadGeneration', 'loadedMeetingId',
                      'activePointerId', 'event.pointerId!==activePointerId', 'pointercancel'):
            self.assertIn(token, self.js)
        self.assertIn('aspect-ratio:1200/700', self.html)

    def test_shape_eraser_and_account_cleanup_contract(self):
        for token in ('segmentDistance', "item.tool==='rect'", 'clearAll', '.objectStore(STORE).clear()'):
            self.assertIn(token, self.js)

    def test_highlighter_is_saved_rendered_and_restorable(self):
        self.assertIn('data-ink-tool="highlighter"', self.html)
        for token in ("'highlighter'", "item.tool==='highlighter'", 'globalAlpha=.28'):
            self.assertIn(token, self.js)

    def test_sticky_notes_use_an_in_app_editor(self):
        self.assertIn("function openStickyEditor", self.js)
        self.assertIn("data-sticky-save", self.js)
        self.assertNotIn("prompt('포스트잇", self.js)
        self.assertIn('/static/v15-ink.js?v=beta13-hotfix2', self.html)

    def test_multi_page_notes_preserve_legacy_strokes(self):
        for token in (
            'id="inkPageLabel"', 'id="inkAddPage"', 'id="inkDeletePage"',
        ):
            self.assertIn(token, self.html)
        for token in (
            'pageCount', 'pageIndex:currentPage', '(item.pageIndex||0)===currentPage',
            'Number.isInteger(stroke.pageIndex)',
        ):
            self.assertIn(token, self.js)

    def test_lasso_selection_can_duplicate_and_delete_strokes(self):
        self.assertIn('data-ink-tool="lasso"', self.html)
        for token in (
            'selectedIds', 'inkDuplicateSelection', 'inkDeleteSelection',
            'boundsFor', 'intersects',
        ):
            self.assertIn(token, self.js)

    def test_lasso_selection_can_move_strokes_and_cancel_safely(self):
        for token in ('lassoMoveStart', 'lassoOriginalPoints', 'x:q.x+dx', 'y:q.y+dy'):
            self.assertIn(token, self.js)
        self.assertIn('if(lassoOriginalPoints)doc.strokes.forEach', self.js)

    def test_shape_and_paper_menus_open_as_visible_popovers(self):
        self.assertIn('positionInkMenu', self.js)
        self.assertIn("window.innerWidth-box.width-8", self.js)
        self.assertIn('.ink-more-tools[open] :is(.ink-more-menu,.ink-paper-menu)', self.html)
        for label in ('도형 도구 열기', '용지 설정 열기', '템플릿 이미지 불러오기', '템플릿 이미지 제거'):
            self.assertIn(f'aria-label="{label}"', self.html)

    def test_split_reference_and_sticky_note_tools_are_available(self):
        for token in ('id="inkSourceToggle"', 'id="inkSourceInput"', 'id="inkExportPng"', 'data-ink-tool="sticky"'):
            self.assertIn(token, self.html)
        for token in ("tool==='sticky'", "file.type==='application/pdf'", "workspace?.classList.toggle('split'", "AI_PRONOTE_${currentPage+1}.png"):
            self.assertIn(token, self.js)

    def test_each_page_can_keep_a_paper_background(self):
        self.assertIn('id="inkPaper"', self.html)
        for token in ('value="ruled"', 'value="ruled-wide"', 'value="grid"', 'value="dot"', 'value="manuscript"', 'pageBackgrounds', 'pageColors', "wrap.dataset.paper=paperValue"):
            self.assertIn(token, self.html + self.js)

    def test_pen_and_highlighter_offer_palette_and_custom_color(self):
        self.assertIn('aria-label="빠른 색상"', self.html)
        self.assertIn('type="color" id="inkColor"', self.html)
        self.assertIn("document.querySelectorAll('[data-ink-color]')", self.js)

    def test_primary_tools_use_familiar_icon_buttons_with_accessible_names(self):
        for label in ('펜', '형광펜', '지우개', '올가미', '포스트잇', '실행 취소', '다시 실행'):
            self.assertIn(f'aria-label="{label}"', self.html)
        self.assertIn('class="ink-icon-btn"', self.html)
        for label in ('페이지 추가', '현재 페이지 삭제', '자료와 노트 분할 보기', 'PDF 또는 이미지 자료 열기', '현재 페이지 내보내기'):
            self.assertIn(f'aria-label="{label}"', self.html)

    def test_hidden_text_editor_cannot_cover_the_ink_canvas(self):
        self.assertIn('.mynote-block.fullpage.ink-active .mynote-block-content { display: none!important; }', self.html)
        self.assertIn('.mynote-block .mynote-block-content[hidden] { display: none!important; }', self.html)

    def test_page_template_image_can_be_annotated_and_saved(self):
        for token in ('id="inkTemplateOpen"', 'id="inkTemplateInput"', 'id="inkTemplateImage"'):
            self.assertIn(token, self.html)
        for token in ('pageTemplates', "file.size>5*1024*1024", 'reader.readAsDataURL(file)'):
            self.assertIn(token, self.js)
        for token in ('drawPaper(target)', 'target.drawImage(canvas,0,0)', 'await image.decode()'):
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
