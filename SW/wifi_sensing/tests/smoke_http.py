"""Start the actual process and collect a synthetic recording over HTTP."""
import json
import os
from pathlib import Path
import site
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
with socket.socket() as port_probe:
    port_probe.bind(('127.0.0.1', 0))
    port = port_probe.getsockname()[1]
base = f'http://127.0.0.1:{port}'


def request(path, body=None):
    req = urllib.request.Request(
        base + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=8) as response:
        return json.load(response)


def until(predicate, timeout=30):
    deadline = time.perf_counter() + timeout
    last = None
    while time.perf_counter() < deadline:
        try:
            last = request('/state')
            if predicate(last):
                return last
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(.25)
    raise AssertionError(f'HTTP smoke timed out: {last}')


with tempfile.TemporaryDirectory() as folder:
    with (Path(folder) / 'process.log').open('w') as log:
        process = subprocess.Popen([
            # Avoid the Windows venv launcher leaving its child alive on terminate.
            sys._base_executable, str(root / 'bridge.py'), '--port', str(port),
            '--data-dir', folder,
        ], stdout=log, stderr=log, env={
            **os.environ, 'PYTHONPATH': os.pathsep.join(site.getsitepackages()),
        })
        try:
            until(lambda state: state['training_allowed'] is False, timeout=60)
            request('/command/connect', {'mode': 'dummy'})
            state = until(lambda state: state['waveform'] is not None)
            assert len(state['waveform']['signal']) == 240
            request('/command/capture', {'label': '정지', 'seconds': 4, 'round': 'http-smoke'})
            state = until(lambda state: state['capture'] and state['capture']['saved'])
            assert len(state['records']) == 1
            assert state['records'][0]['collection']['mode'] == 'dummy'
            request('/command/disconnect', {})
            state = request('/state')
            assert state['waveform'] is None and state['recognition']['result'] is None
            print(json.dumps({'result': 'PASS', 'mode': 'synthetic_only',
                              'checks': ['process startup', 'live dummy HTTP waveform',
                                         'timed capture saved', 'disconnect clears state']}, indent=2))
        finally:
            process.terminate()
            process.wait(timeout=15)
