import os
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


class TtsRequest(BaseModel):
    text: str


def get_whisper_model() -> WhisperModel:
    global _whisper_model

    if _whisper_model is None:
        model_name = os.getenv("WHISPER_MODEL", "base")

        print(f"[STT] Whisper 모델 로딩: {model_name}")

        _whisper_model = WhisperModel(
            model_name,
            device="cpu",
            compute_type="int8",
        )

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
    return {"status": "ok"}
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

        text = await run_in_threadpool(
            transcribe_file,
            temporary_path,
        )

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

        await communicate.save(temporary_path)

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
