import concurrent.futures
import time
import unittest
from pathlib import Path

from fastapi import HTTPException
from fastapi.testclient import TestClient

import main


ROOT = Path(__file__).resolve().parents[1]


class IPadSecurityRegressionTests(unittest.TestCase):
    def setUp(self):
        self.original_mode = main.IPAD_MODE
        self.original_token = main.LAN_TOKEN
        main.IPAD_MODE = True
        main.LAN_TOKEN = "x" * 43
        main._lan_token_consumed = False
        main._lan_sessions.clear()

    def tearDown(self):
        main.IPAD_MODE = self.original_mode
        main.LAN_TOKEN = self.original_token
        main._lan_token_consumed = False
        main._lan_sessions.clear()

    def test_one_time_token_is_atomically_consumed(self):
        def connect():
            try:
                return main.companion_connect("x" * 43).status_code
            except HTTPException as error:
                return error.status_code

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: connect(), range(2)))
        self.assertEqual(sorted(results), [303, 401])
        self.assertEqual(len(main._lan_sessions), 1)

    def test_ipad_session_cannot_reach_host_administration(self):
        session_id = "session-test"
        main._lan_sessions[session_id] = time.time() + 300
        with TestClient(main.app, base_url="https://testserver") as client:
            response = client.post(
                "/api/setup/run",
                cookies={"pronote_lan_session": session_id},
                headers={"origin": "https://testserver"},
                json={"action": "claude-login"},
            )
        self.assertEqual(response.status_code, 403)

    def test_qr_url_contains_no_bearer_token(self):
        launcher = (ROOT / "start_ipad_companion.ps1").read_text(encoding="utf-8")
        self.assertIn('$connectUrl = "https://${address}:${Port}/companion/connect"', launcher)
        self.assertNotIn("connect?token=", launcher)
        self.assertNotIn("ipad_companion_url.txt", launcher)


if __name__ == "__main__":
    unittest.main()
