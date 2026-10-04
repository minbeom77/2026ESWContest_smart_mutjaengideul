"""Local, incremental Korean captions. Audio and text are never written to disk."""

import asyncio
from contextlib import asynccontextmanager
import json
import os
from pathlib import Path
import unicodedata

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import numpy as np

PROTOCOL = "safehub.pcm.v1"
MAX_FRAME_BYTES = 6400  # 200 ms, signed little-endian PCM, mono, 16 kHz.


class Recognizer:
    def __init__(self, model_path):
        import sherpa_onnx
        from kiwipiepy import Kiwi

        model = Path(model_path)
        self.engine = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=str(model / "tokens.txt"),
            encoder=str(next(model.glob("encoder-*.int8.onnx"))),
            decoder=str(next(model.glob("decoder-*.onnx"))),
            joiner=str(next(model.glob("joiner-*.int8.onnx"))),
            num_threads=2,
            sample_rate=16000,
            feature_dim=80,
            decoding_method="modified_beam_search",
            max_active_paths=8,
            enable_endpoint_detection=True,
            rule1_min_trailing_silence=2.4,
            rule2_min_trailing_silence=0.8,
            rule3_min_utterance_length=20,
        )
        self.spacer = Kiwi(num_workers=1, model_type="cong")
        self.spacer.space("준비되었습니다")  # Load once, before health is ready.

    def session(self):
        return RecognitionSession(self)


class RecognitionSession:
    def __init__(self, recognizer):
        self.recognizer = recognizer
        self.epoch = 0
        self.segment = 0
        self.reset()

    def reset(self, epoch=0):
        self.epoch = epoch
        self.stream = self.recognizer.engine.create_stream()
        self.previous = ""

    def accept(self, pcm):
        engine = self.recognizer.engine
        samples = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768
        self.stream.accept_waveform(16000, samples)
        while engine.is_ready(self.stream):
            engine.decode_stream(self.stream)
        text = unicodedata.normalize("NFC", engine.get_result(self.stream)).strip()
        final = engine.is_endpoint(self.stream)
        result = {"type": "ack", "bytes": len(pcm), "epoch": self.epoch}
        if text != self.previous or (text and final):
            result.update(
                type="caption", segment=self.segment,
                text=self.recognizer.spacer.space(text) if text else "",
                final=final,
            )
            self.previous = text
        if final:
            self.segment += 1
            engine.reset(self.stream)
            self.previous = ""
        return result


def create_app(factory=None):
    @asynccontextmanager
    async def lifespan(app):
        model_path = os.environ.get("STT_MODEL_PATH", "korean-streaming-174m")
        app.state.recognizer = await asyncio.to_thread(
            factory or (lambda: Recognizer(model_path))
        )
        app.state.active = False
        yield

    app = FastAPI(lifespan=lifespan)

    @app.get("/health")
    async def health():
        return {"ready": True, "streaming_protocol": PROTOCOL,
                "streaming_path": "/stt/stream", "sample_rate": 16000,
                "model": "korean-streaming-zipformer-174m-int8", "local_only": True}

    @app.websocket("/stt/stream")
    async def stream_audio(socket: WebSocket):
        await socket.accept()
        if app.state.active:
            await socket.close(code=1013, reason="Microphone session already active")
            return
        app.state.active = True
        try:
            session = app.state.recognizer.session()
            await socket.send_json({"type": "ready", "protocol": PROTOCOL})
            while True:
                message = await asyncio.wait_for(socket.receive(), timeout=45)
                if message["type"] == "websocket.disconnect":
                    break
                if message.get("bytes") is not None:
                    pcm = message["bytes"]
                    if not pcm or len(pcm) % 2 or len(pcm) > MAX_FRAME_BYTES:
                        await socket.close(code=1008, reason="Invalid PCM frame")
                        break
                    result = await asyncio.to_thread(session.accept, pcm)
                    await socket.send_json(result)
                else:
                    control = json.loads(message.get("text") or "{}")
                    epoch = control.get("epoch")
                    if (control.get("type") != "reset" or type(epoch) is not int
                            or epoch < 0):
                        await socket.close(code=1008, reason="Invalid control")
                        break
                    await asyncio.to_thread(session.reset, epoch)
                    await socket.send_json({"type": "reset", "epoch": epoch})
        except (WebSocketDisconnect, asyncio.TimeoutError):
            pass
        except (ValueError, TypeError, AttributeError):
            await socket.close(code=1008, reason="Invalid message")
        finally:
            app.state.active = False

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8766, ws_max_size=MAX_FRAME_BYTES,
                ws_max_queue=8, access_log=False)
