"""Alternate reference/numeric runs on fresh synthetic windows on this host."""

import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import sys
import time
from unittest.mock import patch

from test_numeric_input import active, frames, reference, signal_pipeline, RUNTIME


def summarize(samples):
    ordered = sorted(samples)
    return dict(median_ms=statistics.median(samples), max_ms=max(samples),
                p95_ms=ordered[min(len(ordered) - 1, int(len(ordered) * .95))],
                samples_ms=samples)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repeats', type=int, default=30)
    args = parser.parse_args()
    if args.repeats < 5:
        parser.error('Use at least five repeats.')
    import torch
    import numpy as np
    import scipy
    torch.set_num_threads(1)
    functions = {'reference': reference.preprocessor_dataframe,
                 'numeric': active.preprocessor_dataframe}
    results = {}
    for scope in ('iq_conversion', 'complete_4s_processing'):
        samples = {name: [] for name in functions}
        for iteration in range(args.repeats + 5):
            records = frames(epoch=10 + iteration * 4)
            order = list(functions) if iteration % 2 else list(reversed(functions))
            for name in order:
                function = functions[name]
                with patch.object(signal_pipeline, 'preprocessor_dataframe', function):
                    started = time.perf_counter()
                    if scope == 'iq_conversion':
                        function(records)
                    else:
                        signal_pipeline.latest_signal(records, 'raw_iq_52')
                    elapsed = (time.perf_counter() - started) * 1000
                if iteration >= 5:
                    samples[name].append(elapsed)
        results[scope] = {name: summarize(values) for name, values in samples.items()}
    result = dict(scope='Windows laptop synthetic I/Q; not RF, UI rendering, or Pi performance',
                  methodology='241 fresh frames; alternate order; 5 warmups; one Torch thread; no cache',
                  environment=dict(python=sys.version, platform=platform.platform(),
                                   numpy=np.__version__, scipy=scipy.__version__, torch=torch.__version__),
                  source_sha256={name: hashlib.sha256((RUNTIME / name).read_bytes()).hexdigest()
                                 for name in ('soom_engine.py', 'reference/soom_engine.py', 'signal_pipeline.py')},
                  repeats=args.repeats, results=results)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({scope: {name: values['median_ms'] for name, values in runs.items()}
                      for scope, runs in results.items()}))


if __name__ == '__main__':
    main()
