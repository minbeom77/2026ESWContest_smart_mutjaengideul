"""Generate offline fixtures from the actual CSI adapter for Flutter tests."""

import argparse
import json
from pathlib import Path
import uuid
from unittest.mock import patch

from adapter import CsiEventAdapter


def generate_case(name, room, *, retry=False, rearm=False):
    adapter = CsiEventAdapter(
        room=room, device=f"fixture_csi_{room}",
        fall_labels={"fall_fixture"}, normal_labels={"normal_fixture"},
        normal_confirmations=2,
    )
    fall = {"label": "fall_fixture", "scores": {"fall_fixture": 0.92},
            "device_time": 12.5, "window_seconds": 3.0}
    normal = {"label": "normal_fixture", "scores": {"normal_fixture": 0.95}}
    emitted = [adapter.update(fall, timestamp=1800000000)]
    assert emitted[0] is not None
    assert adapter.update(fall, timestamp=1800000001) is None
    assert adapter.update({"label": "판단 보류", "reason": "새 신호 대기"},
                          timestamp=1800000002) is None
    assert adapter.update(fall, timestamp=1800000003) is None
    if rearm:
        assert adapter.update(normal, timestamp=1800000004) is None
        assert adapter.update(normal, timestamp=1800000005) is None
        emitted.append(adapter.update(fall, timestamp=1800000006))
        assert emitted[-1] is not None
    expected_count = 2 if rearm else 1
    assert len(emitted) == expected_count
    assert len({x["payload"]["message_id"] for x in emitted}) == expected_count
    for envelope in emitted:
        uuid.UUID(envelope["payload"]["message_id"])
    messages = [emitted[0], emitted[0]] if retry else list(emitted)
    return dict(name=name, expected_count=expected_count,
                messages=messages, expected=emitted, room=room)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    # Stable IDs keep regenerating this test fixture from changing the Git diff.
    ids = [uuid.UUID(f"00000000-0000-4000-8000-{index:012x}")
           for index in range(1, 6)]
    with patch("adapter.uuid.uuid4", side_effect=ids):
        fixture = dict(format_version=1,
                       source="CsiEventAdapter / synthetic input / fixed test IDs",
                       cases=[generate_case("bedroom_payload", "bedroom"),
                              generate_case("bathroom_payload", "bathroom"),
                              generate_case("transport_retry", "bedroom", retry=True),
                              generate_case("new_episode", "bedroom", rearm=True)])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(fixture, ensure_ascii=False, indent=2,
                                  allow_nan=False) + "\n", encoding="utf-8")
    print(f"Generated 4 cases: {args.out}")


if __name__ == "__main__":
    main()
