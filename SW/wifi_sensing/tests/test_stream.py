"""Serial transport lifecycle tests with in-memory ports, never physical hardware."""

from collections import deque
import json
from pathlib import Path
import sys
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bridge  # Adds the pinned runtime directory before importing Stream.
from stream import Stream, dummy_frame


class MemoryPort:
    def __init__(self, chunks, exhausted=None):
        self.chunks = deque(chunks)
        self.exhausted = exhausted or (lambda: None)
        self.closed = False
        self.port = None
        self.dtr = self.rts = True
        self.opened_with = None
        self.writes = []

    def open(self):
        self.opened_with = (self.port, self.dtr, self.rts)

    @property
    def in_waiting(self):
        return len(self.chunks[0]) if self.chunks else 0

    def read(self, size):
        if self.chunks:
            chunk = self.chunks.popleft()
            if len(chunk) > size:
                self.chunks.appendleft(chunk[size:])
                chunk = chunk[:size]
            return chunk
        self.exhausted()
        return b''

    def reset_input_buffer(self):
        pass

    def write(self, value):
        self.writes.append(value)
        return len(value)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.closed = True


class StreamTests(unittest.TestCase):
    def test_boot_receiver_waits_for_late_usb_and_stop_cancels_retry(self):
        import serial
        stream = Stream(request_status=False)
        opened = threading.Event()
        stable_path = '/dev/serial/by-id/test-receiver'

        def missing_port(**kwargs):
            opened.set()
            raise serial.SerialException('test USB not attached yet')

        with patch('serial.tools.list_ports.comports', return_value=[]):
            with self.assertRaisesRegex(ValueError, 'USB 포트'):
                stream.start('live', stable_path)
            with self.assertRaises(ValueError):
                stream.start('live', '', wait_for_device=True)
            with patch('serial.Serial', side_effect=missing_port):
                stream.start('live', stable_path, wait_for_device=True)
                self.assertTrue(opened.wait(2))
                stream.stop()
        self.assertFalse(stream.thread.is_alive())
        self.assertFalse(stream.snapshot()['fresh'])
        self.assertEqual(stream.mode, 'live')
        self.assertEqual(stream.received, 0)

    def test_boot_receiver_recovers_when_usb_appears(self):
        import serial
        stream = Stream(request_status=False)
        raw = dummy_frame(10)['raw_line'].encode() + b'\n'
        port = MemoryPort([raw], stream.stop_event.set)
        clock = SimpleNamespace(epoch=0, arrival_jitter=.25,
                                map_time=lambda device, arrival: arrival)
        stable_path = '/dev/serial/by-id/test-receiver'
        with patch('serial.tools.list_ports.comports', return_value=[]):
            with patch('serial.Serial', side_effect=[serial.SerialException('absent'), port]):
                with patch('stream.LiveClock', return_value=clock):
                    with patch.object(stream.stop_event, 'wait', return_value=False):
                        stream.start('live', stable_path, wait_for_device=True)
                        stream.thread.join(timeout=2)
                        self.assertFalse(stream.thread.is_alive())
        self.assertEqual(stream.received, 1)
        self.assertEqual(port.opened_with, (stable_path, False, False))
        self.assertEqual(port.writes, [])

    def test_output_only_receiver_opens_without_reset_or_commands(self):
        stream = Stream(request_status=False)
        iq = json.dumps(dummy_frame(10)['iq'])
        raw = f'10.0,"{iq}"\n'.encode()

        class OutputOnlyPort(MemoryPort):
            def write(self, value):
                raise AssertionError('output-only receivers must not receive commands')

        port = OutputOnlyPort([raw], stream.stop_event.set)
        snapshots = []
        original_append = stream._append

        def record(frame):
            original_append(frame)
            snapshots.append(stream.snapshot())

        clock = SimpleNamespace(epoch=0, arrival_jitter=.25,
                                map_time=lambda device, arrival: arrival)
        with patch('serial.Serial', return_value=port) as create_port:
            with patch('stream.LiveClock', return_value=clock):
                with patch.object(stream, '_append', side_effect=record):
                    stream._serial('MEMORY_PORT', 921600)
        create_port.assert_called_once_with(port=None, baudrate=921600,
                                            timeout=.2, write_timeout=1)
        self.assertEqual(port.opened_with, ('MEMORY_PORT', False, False))
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0]['received'], 1)
        self.assertTrue(snapshots[0]['fresh'])
        self.assertEqual(snapshots[0]['hardware'], 'c6_ht20_soom_input')
        self.assertEqual(snapshots[0]['frames'][0]['csi_profile'], 'soom_original_csv')
        self.assertTrue(port.closed)

    def test_default_receiver_requests_status_and_accepts_c3_frames(self):
        stream = Stream()
        status = json.dumps({'event': 'status', 'chip': 'esp32c3'}).encode() + b'\n'
        raw = json.dumps({'timestamp': 10, 'data': dummy_frame(10)['iq']}).encode() + b'\n'
        port = MemoryPort([status, raw], stream.stop_event.set)
        snapshots = []
        original_append = stream._append

        def record(frame):
            original_append(frame)
            snapshots.append(stream.snapshot())

        clock = SimpleNamespace(epoch=0, arrival_jitter=.25,
                                map_time=lambda device, arrival: arrival)
        with patch('serial.Serial', return_value=port):
            with patch('stream.LiveClock', return_value=clock):
                with patch.object(stream, '_append', side_effect=record):
                    stream._serial('MEMORY_PORT', 921600)
        self.assertEqual(port.opened_with, ('MEMORY_PORT', False, False))
        self.assertEqual(port.writes, [b'{"cmd":"status"}\n'])
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0]['hardware'], 'router_c3')
        self.assertEqual(snapshots[0]['frames'][0]['layout'], 'esp_lltf64')

    def test_partial_lines_survive_serial_timeouts(self):
        stream = Stream()
        port = MemoryPort([b'first', b'', b' frame\r', b'\nsecond\nthi',
                           b'', b'rd\n'], stream.stop_event.set)
        self.assertEqual(list(stream._serial_lines(port)), ['first frame', 'second', 'third'])
        self.assertEqual(stream.rejected, 0)

    def test_noisy_overlong_line_is_bounded_and_next_line_recovers(self):
        stream = Stream()
        chunks = [b'x' * 8192] * 20 + [b'\nvalid\n']
        port = MemoryPort(chunks, stream.stop_event.set)
        self.assertEqual(list(stream._serial_lines(port)), ['valid'])
        self.assertEqual(stream.rejected, 1)

    def test_disconnect_retries_and_never_reuses_previous_epoch_frames(self):
        import serial
        stream = Stream()
        raw = dummy_frame(10)['raw_line'].encode() + b'\n'
        first = MemoryPort([raw], lambda: (_ for _ in ()).throw(serial.SerialException('test unplug')))
        second = MemoryPort([raw], stream.stop_event.set)
        seen = []
        original_append = stream._append

        def record(frame):
            self.assertEqual(len(stream.frames), 0)
            original_append(frame)
            seen.append(dict(frame))

        clock = SimpleNamespace(epoch=0, arrival_jitter=.25,
                                map_time=lambda device, arrival: device)
        with patch('serial.Serial', side_effect=[first, second]) as open_port:
            with patch('stream.LiveClock', return_value=clock):
                with patch.object(stream.stop_event, 'wait', return_value=False):
                    with patch.object(stream, '_append', side_effect=record):
                        stream._serial('MEMORY_PORT', 921600)
        self.assertEqual(open_port.call_count, 2)
        self.assertEqual(len(seen), 2)
        self.assertNotEqual(seen[0]['stream_epoch'], seen[1]['stream_epoch'])
        self.assertTrue(first.closed and second.closed)
        self.assertFalse(stream.snapshot()['connected'])
        self.assertEqual(stream.snapshot()['frames'], [])

    def test_malformed_status_metadata_does_not_crash_snapshot(self):
        stream = Stream()
        invalid = json.dumps({'event': 'status', 'chip': ['invalid'], 'mode': {}}).encode() + b'\n'
        raw = dummy_frame(10)['raw_line'].encode() + b'\n'
        port = MemoryPort([invalid, raw], stream.stop_event.set)
        snapshots = []
        original_append = stream._append

        def record(frame):
            original_append(frame)
            snapshots.append(stream.snapshot())

        clock = SimpleNamespace(epoch=0, arrival_jitter=.25,
                                map_time=lambda device, arrival: device)
        with patch('serial.Serial', return_value=port):
            with patch('stream.LiveClock', return_value=clock):
                with patch.object(stream, '_append', side_effect=record):
                    stream._serial('MEMORY_PORT', 921600)
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0]['hardware'], 'c6_ht20_soom_input')

    def test_stop_joins_waiting_serial_worker(self):
        stream = Stream()
        opened = threading.Event()

        class WaitingPort(MemoryPort):
            def read(self, size):
                opened.set()
                time.sleep(.05)
                return b''

        port = WaitingPort([])
        with patch('serial.tools.list_ports.comports', return_value=[SimpleNamespace(device='MEMORY_PORT')]):
            with patch('serial.Serial', return_value=port):
                stream.start('live', 'MEMORY_PORT')
                self.assertTrue(opened.wait(2))
                started = time.perf_counter()
                stream.stop()
                self.assertLess(time.perf_counter() - started, 1)
        self.assertFalse(stream.thread.is_alive())
        self.assertTrue(port.closed)
        self.assertFalse(stream.snapshot()['connected'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
