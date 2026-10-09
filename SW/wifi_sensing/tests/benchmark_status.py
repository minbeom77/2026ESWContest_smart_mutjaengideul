"""Repeatable synthetic status cost; this is not Raspberry Pi performance evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import statistics
import sys
import tempfile
import time
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bridge import Controller


def measure(function, repeats):
    samples = []
    for _ in range(repeats):
        started = time.perf_counter()
        function()
        samples.append((time.perf_counter() - started) * 1000)
    return {'median_ms': statistics.median(samples),
            'max_ms': max(samples), 'samples_ms': samples}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    parser.add_argument('--repeats', type=int, default=20)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as folder:
        controller = Controller(folder)
        controller.stop_event.set()
        controller.worker.join()
        from stream import dummy_frame
        # Fill the production-sized ring buffer without waiting for wall time.
        for index in range(8400):
            controller.stream._append(dummy_frame(index / 60))
        controller.stream.connected = True
        controller.stream.mode = 'dummy'
        for index in range(40):
            controller.db.write_json(controller.db.MODELS / f'{index}.json', {
                'model_id': str(index), 'feature_profile': controller.profile,
                'validation_history': list(range(2000)), 'labels': ['A', 'B'],
            })
        try:
            with patch.object(controller.stream, 'now') as now:
                now.return_value = controller.stream.frames[-1]['t']
                controller.status()
                unchanged = measure(controller.status, args.repeats)
                index = 8400

                def new_input():
                    nonlocal index
                    for _ in range(30):
                        controller.stream._append(dummy_frame(index / 60))
                        index += 1
                    now.return_value = controller.stream.frames[-1]['t']
                    controller.status()

                moving = measure(new_input, args.repeats)
                result = {'scope': 'Windows laptop, synthetic CSI, 8400-frame ring, 40 model metadata files',
                          'source_sha256': {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                                            for name in ('bridge.py', 'stream.py')},
                          'unchanged_status': unchanged, 'advancing_30_frames_and_status': moving}
                print(json.dumps(result, indent=2))
                if args.output:
                    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
        finally:
            controller.close()


if __name__ == '__main__':
    main()
