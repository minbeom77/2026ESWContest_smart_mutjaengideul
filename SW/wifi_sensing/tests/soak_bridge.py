"""Bounded synthetic HTTP soak in a private temporary workspace and random port.

This measures this host's software lifecycle, not RF behavior or Raspberry Pi speed.
"""

import argparse
from collections import deque
import ctypes
from datetime import datetime, timedelta, timezone
import hashlib
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bridge import Controller, Handler, RUNTIME


class SoakInterrupted(Exception):
    def __init__(self, details):
        super().__init__(details['reason'])
        self.details = details


def host_clocks():
    """Keep sleep-inclusive elapsed time separate from Windows awake time.

    Microsoft documents GetTickCount64 as including sleep/hibernation, while
    QueryUnbiasedInterruptTime excludes them. Neither is changed by wall-clock edits.
    https://learn.microsoft.com/windows/win32/sysinfo/windows-time
    """
    if os.name == 'nt':
        tick = ctypes.windll.kernel32.GetTickCount64
        tick.argtypes = []
        tick.restype = ctypes.c_ulonglong
        unbiased = ctypes.windll.kernel32.QueryUnbiasedInterruptTime
        unbiased.argtypes = [ctypes.POINTER(ctypes.c_ulonglong)]
        unbiased.restype = ctypes.c_int

        def awake():
            value = ctypes.c_ulonglong()
            if not unbiased(ctypes.byref(value)):
                raise ctypes.WinError()
            return value.value / 10_000_000

        return lambda: tick() / 1000, awake, 'windows_tick_and_unbiased'
    if hasattr(time, 'CLOCK_BOOTTIME'):
        return lambda: time.clock_gettime(time.CLOCK_BOOTTIME), None, 'boottime_only'
    # A long wall-clock gap is unobserved time, not proof of system suspend.
    return time.time, None, 'wall_clock_only'


class SoakClock:
    def __init__(self, seconds, wall_clock=None, awake_clock=None):
        if wall_clock is None:
            wall_clock, awake_clock, self.source = host_clocks()
        else:
            self.source = 'injected_test_clock'
        self.wall_clock, self.awake_clock = wall_clock, awake_clock
        self.seconds = seconds
        self.started = self.previous_wall = wall_clock()
        self.awake_started = self.previous_awake = awake_clock() if awake_clock else None
        self.suspended_seconds = 0.0
        self.events = deque(maxlen=20)

    def elapsed(self):
        return max(0.0, self.wall_clock() - self.started)

    def remaining(self):
        return max(0.0, self.seconds - self.elapsed())

    def metrics(self):
        return {'clock_source': self.source, 'wall_elapsed_seconds': round(self.elapsed(), 3),
                'awake_elapsed_seconds': (round(self.awake_clock() - self.awake_started, 3)
                                          if self.awake_clock else None),
                'suspend_seconds_from_clocks': round(self.suspended_seconds, 3),
                'observation_gaps': list(self.events)}

    def check(self):
        wall = self.wall_clock()
        awake = self.awake_clock() if self.awake_clock else None
        wall_delta = wall - self.previous_wall
        awake_delta = awake - self.previous_awake if awake is not None else None
        suspended = max(0.0, wall_delta - awake_delta) if awake_delta is not None else None
        self.previous_wall, self.previous_awake = wall, awake
        reason = ('clock_discontinuity' if wall_delta < -1 else
                  'suspend' if suspended is not None and suspended >= 1 else 'unobserved_gap')
        if suspended is not None and suspended >= 1:
            self.suspended_seconds += suspended
        if wall_delta >= 3 or reason in ('suspend', 'clock_discontinuity'):
            event = {'elapsed_seconds': round(wall - self.started, 3), 'reason': reason,
                     'wall_gap_seconds': round(wall_delta, 3),
                     'awake_gap_seconds': round(awake_delta, 3) if awake_delta is not None else None,
                     'suspend_seconds_from_clocks': round(suspended, 3) if suspended is not None else None}
            self.events.append(event)
            # Ordinary multi-second load is recorded without calling it suspend.
            # A continuous run cannot be certified across a long unobserved gap.
            if reason in ('suspend', 'clock_discontinuity') or wall_delta >= 15:
                raise SoakInterrupted(event)


def rss_bytes():
    if os.name == 'nt':
        from ctypes import wintypes

        class MemoryCounters(ctypes.Structure):
            _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD),
                        ('PeakWorkingSetSize', ctypes.c_size_t), ('WorkingSetSize', ctypes.c_size_t),
                        ('QuotaPeakPagedPoolUsage', ctypes.c_size_t), ('QuotaPagedPoolUsage', ctypes.c_size_t),
                        ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t), ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                        ('PagefileUsage', ctypes.c_size_t), ('PeakPagefileUsage', ctypes.c_size_t)]

        counters = MemoryCounters()
        counters.cb = ctypes.sizeof(counters)
        process = ctypes.windll.kernel32.GetCurrentProcess
        process.restype = wintypes.HANDLE
        query = ctypes.windll.psapi.GetProcessMemoryInfo
        query.argtypes = [wintypes.HANDLE, ctypes.POINTER(MemoryCounters), wintypes.DWORD]
        if not query(process(), ctypes.byref(counters), counters.cb):
            raise ctypes.WinError()
        return counters.WorkingSetSize
    statm = Path('/proc/self/statm')
    if statm.exists():
        return int(statm.read_text().split()[1]) * os.sysconf('SC_PAGE_SIZE')
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=int, default=300)
    parser.add_argument('--checkpoint-seconds', type=int, default=60)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not 15 <= args.seconds <= 3600:
        parser.error('--seconds must be 15..3600')
    if not 1 <= args.checkpoint_seconds <= 60:
        parser.error('--checkpoint-seconds must be 1..60')
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    checkpoints, errors = deque(maxlen=121), deque(maxlen=20)
    source_hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                     for name in ('bridge.py', 'stream.py', 'runtime/LOCAL_SOURCE_MANIFEST.json',
                                  'runtime/LOCAL_MODIFICATIONS.json', 'runtime/soom_engine.py',
                                  'tests/soak_bridge.py')}
    result = {'scope': 'synthetic input only; current host; no physical devices',
              'source_sha256': source_hashes, 'requested_seconds': args.seconds,
              'started_utc': datetime.now(timezone.utc).isoformat(),
              'status': 'starting', 'poll_interval_seconds': .5}
    controller = server = server_thread = None
    observed = {'received': 0, 'max_arrival_gap_seconds': 0.0, 'arrival_gaps_over_150ms': 0}
    arrival_lock = threading.Lock()
    last_arrival = None
    polls = failures = saved_checks = stale_polls = 0
    max_poll_seconds = 0.0
    poll_samples = deque(maxlen=120)
    capture_started = False
    started = time.perf_counter()
    cpu_started = time.process_time()
    run_clock = None

    def write_report(status):
        elapsed = run_clock.elapsed() if run_clock else time.perf_counter() - started
        with arrival_lock:
            arrivals = dict(observed)
        sample = {'elapsed_seconds': round(elapsed, 3), 'rss_bytes': rss_bytes(),
                  'cpu_seconds': round(time.process_time() - cpu_started, 3),
                  'thread_count': threading.active_count(), 'http_polls': polls,
                  'http_failures': failures, 'max_poll_seconds': round(max_poll_seconds, 4),
                  'stale_polls_after_warmup': stale_polls,
                  'recent_mean_poll_seconds': round(sum(poll_samples) / len(poll_samples), 4) if poll_samples else None,
                  **arrivals}
        sample['received_hz'] = round(arrivals['received'] / elapsed, 3) if elapsed >= 1 else None
        sample['cpu_percent_one_core'] = round(sample['cpu_seconds'] / elapsed * 100, 2) if elapsed >= 1 else None
        if controller is not None:
            with controller.stream.lock:
                sample['buffer_frames'] = len(controller.stream.frames)
            with controller.waveform_lock:
                sample['preprocessing'] = dict(controller.waveform_stats)
            sample['record_count'] = len(controller.record_summaries())
            sample['model_metadata_cache_entries'] = len(controller.model_index)
        checkpoints.append(sample)
        result.update(status=status, latest=sample, checkpoints=list(checkpoints),
                      errors=list(errors), saved_record_checks=saved_checks)
        if run_clock is not None:
            result['clock_diagnostics'] = run_clock.metrics()
        result['timing_warnings'] = [name for name, condition in (
            ('append_gap_over_150ms', arrivals['max_arrival_gap_seconds'] > .15),
            ('append_gap_over_freshness_750ms', arrivals['max_arrival_gap_seconds'] > .75),
            ('stale_input_observed', stale_polls > 0),
            ('poll_exceeded_500ms_target', max_poll_seconds > .5),
            ('poll_exceeded_app_5s_timeout', max_poll_seconds > 5),
        ) if condition]
        result['functional_result'] = ('INCOMPLETE' if status == 'INTERRUPTED' else
                                       'FAIL' if failures else 'PASS' if status == 'PASS' else 'RUNNING')
        temporary = output.with_name(output.name + '.tmp')
        temporary.write_text(json.dumps(result, indent=2), encoding='utf-8')
        temporary.replace(output)

    # TemporaryDirectory owns only this test-created workspace; no user paths are opened.
    try:
        with tempfile.TemporaryDirectory(prefix='safehub-soak-') as folder:
            try:
                controller = Controller(folder, allow_training=False, allow_dummy=True)
                from soom_engine import verify_runtime
                result['runtime_verification'] = verify_runtime()
                server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
                server.controller = controller
                server_thread = threading.Thread(target=server.serve_forever, daemon=True)
                server_thread.start()
                base = f'http://127.0.0.1:{server.server_port}'

                def request(path, body=None, timeout=10):
                    req = urllib.request.Request(base + path,
                        data=None if body is None else json.dumps(body).encode(),
                        headers={'Content-Type': 'application/json'})
                    with urllib.request.urlopen(req, timeout=timeout) as response:
                        return json.load(response)

                append = controller.stream._append

                def observe(frame):
                    nonlocal last_arrival
                    arrived = time.perf_counter()
                    with arrival_lock:
                        if last_arrival is not None:
                            gap = arrived - last_arrival
                            observed['max_arrival_gap_seconds'] = max(observed['max_arrival_gap_seconds'], gap)
                            observed['arrival_gaps_over_150ms'] += int(gap > .15)
                        last_arrival = arrived
                        observed['received'] += 1
                    append(frame)

                controller.stream._append = observe
                request('/command/connect', {'mode': 'dummy'})
                started, cpu_started = time.perf_counter(), time.process_time()
                run_clock = SoakClock(args.seconds)
                collection_start = datetime.now(timezone.utc)
                result['collection_started_utc'] = collection_start.isoformat()
                result['collection_deadline_utc'] = (collection_start + timedelta(seconds=args.seconds)).isoformat()
                next_poll, next_checkpoint = started, started
                write_report('running')
                while True:
                    run_clock.check()
                    if run_clock.remaining() <= 0:
                        break
                    time.sleep(max(0, next_poll - time.perf_counter()))
                    run_clock.check()
                    if run_clock.remaining() <= 0:
                        break
                    tick = time.perf_counter()
                    try:
                        state = request('/state', timeout=max(.05, min(10, run_clock.remaining())))
                        run_clock.check()
                        if run_clock.remaining() <= 0:
                            break
                        polls += 1
                        assert state['mode'] == 'dummy' and state['hardware'] == 'synthetic'
                        assert not state['training_allowed']
                        assert not state['storage_warnings']
                        if time.perf_counter() - started > 4 and not state['fresh']:
                            stale_polls += 1
                        if state['waveform'] is not None:
                            assert len(state['waveform']['signal']) == 240
                            if not capture_started:
                                request('/command/capture', {'label': '정지', 'seconds': 4, 'round': 'synthetic-soak'})
                                capture_started = True
                        if state['capture'] and state['capture']['state'] == 'failed':
                            raise AssertionError('synthetic capture failed')
                        for record in state['records']:
                            assert record['collection']['mode'] == 'dummy'
                        if state['capture'] and state['capture']['saved']:
                            assert len(state['records']) == 1
                            saved_checks += 1
                        assert len(controller.stream.frames) <= 8400
                    except SoakInterrupted:
                        raise
                    except Exception as exc:
                        # If an in-flight request crossed host sleep, keep its
                        # observed timeout but classify the run as interrupted.
                        try:
                            run_clock.check()
                        except SoakInterrupted as interrupted:
                            interrupted.details['request_error_type'] = type(exc).__name__
                            raise
                        failures += 1
                        errors.append({'elapsed_seconds': round(time.perf_counter() - started, 3),
                                       'phase': 'HTTP poll', 'type': type(exc).__name__})
                    duration = time.perf_counter() - tick
                    poll_samples.append(duration)
                    max_poll_seconds = max(max_poll_seconds, duration)
                    next_poll = max(next_poll + .5, time.perf_counter())
                    if time.perf_counter() >= next_checkpoint:
                        write_report('running')
                        next_checkpoint = time.perf_counter() + args.checkpoint_seconds
                request('/command/disconnect', {}, timeout=2)
                run_clock.check()
                state = request('/state', timeout=2)
                run_clock.check()
                assert not state['connected'] and state['waveform'] is None
                assert state['recognition']['result'] is None
                assert saved_checks > 0, 'capture did not complete'
                write_report('PASS' if failures == 0 else 'FAIL')
            except SoakInterrupted as interrupted:
                result['interruption'] = interrupted.details
                # Do not resume collection or synthesize a replacement run.
                if controller is not None:
                    controller.stream.stop()
                write_report('INTERRUPTED')
            finally:
                if server is not None:
                    server.shutdown()
                    server.server_close()
                if server_thread is not None:
                    server_thread.join(timeout=5)
                if controller is not None:
                    controller.close()
                    result['cleanup'] = {'worker_stopped': not controller.worker.is_alive(),
                                         'stream_stopped': not (controller.stream.thread and controller.stream.thread.is_alive())}
        result['cleanup']['temporary_data_removed'] = not Path(folder).exists()
        output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    except Exception as exc:
        result.update(status='FAIL', functional_result='FAIL', fatal_error=type(exc).__name__)
        output.write_text(json.dumps(result, indent=2), encoding='utf-8')
        raise
    print(json.dumps({'status': result['status'], 'elapsed_seconds': result['latest']['elapsed_seconds'],
                      'http_polls': polls, 'http_failures': failures, 'cleanup': result['cleanup']}))
    if result['status'] != 'PASS':
        raise SystemExit(2 if result['status'] == 'INTERRUPTED' else 1)


if __name__ == '__main__':
    main()
