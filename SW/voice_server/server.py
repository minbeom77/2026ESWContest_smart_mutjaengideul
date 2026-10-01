import asyncio
import logging
import os
import threading
import tempfile
from pathlib import Path

import edge_tts
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response
from faster_whisper import WhisperModel
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool


app = FastAPI(title="SafeHub Voice Server")

_whisper_model = None
_model_lock = threading.Lock()
_transcription_lock = threading.Lock()
_model_state = "not_loaded"
logger = logging.getLogger("safehub.voice")


class TtsRequest(BaseModel):
    text: str


def get_whisper_model() -> WhisperModel:
    global _whisper_model, _model_state

    with _model_lock:
        if _whisper_model is None:
            model_name = os.getenv("WHISPER_MODEL", "base")
            _model_state = "loading"
            print(f"[STT] Whisper 모델 로딩: {model_name}")

            try:
                _whisper_model = WhisperModel(
                    model_name,
                    device="cpu",
                    compute_type="int8",
                )
            except Exception as exc:
                _model_state = "failed"
                logger.exception("STT 모델 로딩 실패")
                raise HTTPException(
                    status_code=503,
                    detail="STT 모델을 준비하지 못했습니다. 서버 로그를 확인하세요.",
                ) from exc

            _model_state = "ready"
            print("[STT] Whisper 모델 로딩 완료")

        return _whisper_model


def transcribe_file(path: str) -> str:
    model = get_whisper_model()

    segments, _ = model.transcribe(
        path,
        language="ko",
        beam_size=1,
        vad_filter=True,
    )

    return " ".join(
        segment.text.strip()
        for segment in segments
        if segment.text.strip()
    ).strip()


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "stt_model": os.getenv("WHISPER_MODEL", "base"),
        "stt_model_state": _model_state,
        "tts_requires_internet": True,
    }

@app.post("/stt")
async def stt(audio: UploadFile = File(...)):
    suffix = Path(audio.filename or "audio.wav").suffix or ".wav"
    temporary_path = None

    try:
        audio_bytes = await audio.read()

        if not audio_bytes:
            raise HTTPException(
                status_code=400,
                detail="음성 파일이 비어 있습니다.",
            )

        with tempfile.NamedTemporaryFile(
            suffix=suffix,
            delete=False,
        ) as temporary_file:
            temporary_file.write(audio_bytes)
            temporary_path = temporary_file.name

        def transcribe_serially():
            with _transcription_lock:
                return transcribe_file(temporary_path)

        try:
            text = await run_in_threadpool(transcribe_serially)
        except HTTPException:
            raise
        except Exception as exc:
            logger.exception("STT 변환 실패")
            raise HTTPException(
                status_code=500,
                detail="음성 변환 중 오류가 발생했습니다.",
            ) from exc

        if not text:
            raise HTTPException(
                status_code=422,
                detail="음성을 인식하지 못했습니다.",
            )

        print(f"[STT] 인식 결과: {text}")
        return {"text": text}

    finally:
        await audio.close()

        if temporary_path:
            Path(temporary_path).unlink(missing_ok=True)

@app.post("/tts")
async def tts(request: TtsRequest):
    text = request.text.strip()

    if not text:
        raise HTTPException(
            status_code=400,
            detail="TTS 문장이 비어 있습니다.",
        )

    temporary_path = None

    try:
        with tempfile.NamedTemporaryFile(
            suffix=".mp3",
            delete=False,
        ) as temporary_file:
            temporary_path = temporary_file.name

        communicate = edge_tts.Communicate(
            text=text,
            voice="ko-KR-SunHiNeural",
        )

        try:
            await asyncio.wait_for(
                communicate.save(temporary_path),
                timeout=30,
            )
        except asyncio.TimeoutError as exc:
            raise HTTPException(
                status_code=504,
                detail="TTS 음성 생성 시간이 초과되었습니다.",
            ) from exc
        except Exception as exc:
            logger.exception("TTS 음성 생성 실패")
            raise HTTPException(
                status_code=502,
                detail="TTS 서비스에 연결하거나 음성을 생성하지 못했습니다.",
            ) from exc

        audio_bytes = Path(temporary_path).read_bytes()

        if not audio_bytes:
            raise HTTPException(
                status_code=502,
                detail="TTS 음성을 생성하지 못했습니다.",
            )

        print(f"[TTS] 생성 완료: {text}")

        return Response(
            content=audio_bytes,
            media_type="audio/mpeg",
        )

    finally:
        if temporary_path:
            Path(temporary_path).unlink(missing_ok=True)
