import asyncio
import io
import sys
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server
from fastapi import HTTPException, UploadFile


class VoiceServerTests(unittest.TestCase):
    def setUp(self):
        server._whisper_model = None
        server._model_state = "not_loaded"

    def tearDown(self):
        server._whisper_model = None
        server._model_state = "not_loaded"

    def upload(self, data=b"test"):
        return UploadFile(filename="test.wav", file=io.BytesIO(data))

    def test_health_does_not_load_model(self):
        with patch.object(server, "WhisperModel") as model:
            result = asyncio.run(server.health())
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["stt_model_state"], "not_loaded")
        model.assert_not_called()

    def test_concurrent_model_loading_happens_once(self):
        instance = object()

        def load(*args, **kwargs):
            time.sleep(0.05)
            return instance

        with patch.object(server, "WhisperModel", side_effect=load) as model:
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(
                    lambda _: server.get_whisper_model(), range(4)
                ))
        self.assertTrue(all(item is instance for item in results))
        self.assertEqual(model.call_count, 1)
        self.assertEqual(server._model_state, "ready")

    def test_model_failure_can_retry(self):
        instance = object()
        with patch.object(
            server, "WhisperModel",
            side_effect=[RuntimeError("test failure"), instance],
        ):
            with self.assertRaises(HTTPException) as caught:
                server.get_whisper_model()
            self.assertEqual(caught.exception.status_code, 503)
            self.assertEqual(server._model_state, "failed")
            self.assertIs(server.get_whisper_model(), instance)
        self.assertEqual(server._model_state, "ready")

    def test_empty_stt_closes_upload(self):
        audio = self.upload(b"")
        with self.assertRaises(HTTPException) as caught:
            asyncio.run(server.stt(audio))
        self.assertEqual(caught.exception.status_code, 400)
        self.assertTrue(audio.file.closed)

    def test_stt_results_errors_and_cleanup(self):
        cases = [
            ("아프다", None),
            ("", 422),
            (RuntimeError("test failure"), 500),
            (HTTPException(503, "model unavailable"), 503),
        ]
        for outcome, status in cases:
            with self.subTest(status=status):
                paths = []
                audio = self.upload()

                def transcribe(path):
                    paths.append(Path(path))
                    self.assertTrue(Path(path).exists())
                    if isinstance(outcome, Exception):
                        raise outcome
                    return outcome

                with patch.object(
                    server, "transcribe_file", side_effect=transcribe
                ):
                    if status is None:
                        self.assertEqual(
                            asyncio.run(server.stt(audio)), {"text": "아프다"}
                        )
                    else:
                        with self.assertRaises(HTTPException) as caught:
                            asyncio.run(server.stt(audio))
                        self.assertEqual(caught.exception.status_code, status)

                self.assertTrue(audio.file.closed)
                self.assertEqual(len(paths), 1)
                self.assertFalse(paths[0].exists())

    def test_stt_requests_are_serialized(self):
        active = 0
        peak = 0

        def transcribe(path):
            nonlocal active, peak
            active += 1
            peak = max(peak, active)
            time.sleep(0.05)
            active -= 1
            return "정상"

        async def requests():
            return await asyncio.gather(
                *(server.stt(self.upload()) for _ in range(4))
            )

        with patch.object(server, "transcribe_file", side_effect=transcribe):
            results = asyncio.run(requests())
        self.assertEqual(peak, 1)
        self.assertEqual(results, [{"text": "정상"}] * 4)

    def test_empty_tts(self):
        with self.assertRaises(HTTPException) as caught:
            asyncio.run(server.tts(server.TtsRequest(text="   ")))
        self.assertEqual(caught.exception.status_code, 400)

    def test_tts_results_errors_and_cleanup(self):
        cases = [
            (b"fake-mp3", None),
            (b"", 502),
            (RuntimeError("test failure"), 502),
            (asyncio.TimeoutError(), 504),
        ]
        for outcome, status in cases:
            with self.subTest(status=status):
                paths = []

                class FakeCommunicate:
                    def __init__(self, **kwargs):
                        pass

                    async def save(self, path):
                        paths.append(Path(path))
                        if isinstance(outcome, Exception):
                            raise outcome
                        Path(path).write_bytes(outcome)

                with patch.object(
                    server.edge_tts, "Communicate", FakeCommunicate
                ):
                    request = server.TtsRequest(text="안녕하세요")
                    if status is None:
                        response = asyncio.run(server.tts(request))
                        self.assertEqual(response.body, b"fake-mp3")
                        self.assertEqual(response.media_type, "audio/mpeg")
                    else:
                        with self.assertRaises(HTTPException) as caught:
                            asyncio.run(server.tts(request))
                        self.assertEqual(caught.exception.status_code, status)

                self.assertEqual(len(paths), 1)
                self.assertFalse(paths[0].exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
