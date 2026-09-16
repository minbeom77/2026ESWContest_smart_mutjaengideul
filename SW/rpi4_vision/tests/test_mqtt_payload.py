import json

from mqtt_sender import build_translation_payload


def test_build_translation_payload():
    payload = build_translation_payload("안녕하세요")

    assert payload is not None
    assert json.loads(payload) == {
        "text": "안녕하세요",
    }


def test_build_translation_payload_trims_text():
    payload = build_translation_payload("  감사합니다  ")

    assert payload is not None
    assert json.loads(payload) == {
        "text": "감사합니다",
    }


def test_empty_translation_returns_none():
    assert build_translation_payload("   ") is None
