"""Synthetic integration evidence only; does not measure action accuracy."""

from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer
from http.client import HTTPConnection
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bridge import Controller, Handler, RUNTIME, main


class IntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.app = Controller(cls.temp.name, allow_training=True)
        cls.app.stop_event.set()
        cls.app.worker.join()
        import torch
        torch.set_num_threads(1)

    @classmethod
    def tearDownClass(cls):
        cls.app.close()
        cls.temp.cleanup()

    def setUp(self):
        self.app.stream.stop()
        self.app.recognition.stop()
        self.app.capture = None
        self.app.model = self.app.bundle = None
        self.app.training = {'state': 'idle'}
        self.app.allow_training = True
        self.app.allow_dummy = True

    def frames(self, start=10, seconds=4):
        from stream import dummy_frame
        return [dict(dummy_frame(start + i / 60), device_t=start + i / 60)
                for i in range(int(seconds * 60) + 1)]

    def attach(self, frames):
        stream = self.app.stream
        stream.connected = True
        stream.mode = 'dummy'
        with stream.lock:
            stream.frames.extend(frames)

    def test_01_source_hashes_match_laptop_snapshot(self):
        from soom_engine import verify_runtime, verify_vendor
        verified = verify_runtime()
        self.assertEqual(verified['baseline_files'], 29)
        self.assertEqual(verified['modified_files'], 1)
        self.assertEqual(len(verify_vendor()['files']), 6)

    def test_02_live_preview_equals_latest_engine_and_toggles(self):
        import numpy as np
        from signal_pipeline import latest_signal
        frames = self.frames()
        self.attach(frames)
        with patch.object(self.app.stream, 'now', return_value=14):
            shown = self.app.status()['waveform']['signal']
            expected = latest_signal(frames, 'raw_iq_52', 4)['signal']
            self.assertTrue(np.array_equal(shown, expected))
            raw = self.app.status(dict(denoise=False, normalize=False, pca=False, lowpass=False))['waveform']['signal']
            self.assertFalse(np.array_equal(shown, raw))
            self.assertEqual(len(raw), 240)

    def test_home_summary_skips_waveform_and_clears_stale_result(self):
        self.attach(self.frames())
        with patch.object(self.app.stream, 'now', return_value=14), \
                patch.object(self.app, '_waveform') as waveform:
            summary = self.app.status(include_waveform=False)
            self.assertTrue(summary['fresh'])
            self.assertIsNone(summary['waveform'])
            waveform.assert_not_called()
        self.app.recognition.result = {'label': 'old result'}
        with patch.object(self.app.stream, 'now', return_value=20):
            summary = self.app.status(include_waveform=False)
            self.assertFalse(summary['fresh'])
            self.assertIsNone(summary['recognition']['result'])

    def test_03_capture_saves_and_batch_delete_restores(self):
        stream = self.app.stream
        self.attach(self.frames(0))
        with patch.object(stream, 'now', return_value=4):
            self.app.command('capture', {'label': '정지', 'seconds': 8, 'round': 'round-a'})
        self.attach(self.frames(7, 8))
        with patch.object(stream, 'now', return_value=15):
            self.app._advance()
        self.assertTrue(self.app.capture_saved)
        self.assertEqual(len(self.app.db.CACHE), 0)
        record = self.app.records()[-1]
        self.assertEqual(record['collection']['mode'], 'dummy')
        ids = [record['id']]
        self.app.command('delete_records', {'ids': ids})
        self.assertFalse(any(r['id'] in ids for r in self.app.records()))
        self.app.command('restore_records', {'ids': ids})
        self.assertTrue(any(r['id'] in ids for r in self.app.records()))

    def test_04_gap_clears_waveform_prediction_and_cancels_capture(self):
        self.attach(self.frames())
        with patch.object(self.app.stream, 'now', return_value=14):
            self.app.command('capture', {'label': '정지', 'seconds': 8, 'round': 'gap'})
        self.app.recognition.result = {'label': '낙상', 'score': .99}
        with patch.object(self.app.stream, 'now', return_value=16):
            self.app._advance()
            state = self.app.status()
        self.assertIsNone(state['waveform'])
        self.assertIsNone(state['recognition']['result'])
        self.assertEqual(self.app.capture.state, 'failed')

    def test_05_reconnect_cannot_finish_old_capture(self):
        self.attach(self.frames())
        with patch.object(self.app.stream, 'now', return_value=14):
            self.app.command('capture', {'label': '정지', 'seconds': 8, 'round': 'reset'})
        self.app.stream.reset()
        self.attach(self.frames(20))
        with patch.object(self.app.stream, 'now', return_value=24):
            self.app._advance()
        self.assertEqual(self.app.capture.state, 'failed')

    def test_06_selected_training_export_and_portable_inference(self):
        import numpy as np
        from signal_pipeline import latest_signal
        from edge_runtime import infer, load_bundle
        records = []
        for group in range(3):
            for label in ('합성 A', '합성 B'):
                sid = uuid.uuid4().hex
                record = dict(id=sid, source_id=sid, experiment_id=f'round-{group}',
                              label=label, name=label, representation='raw_iq_52',
                              frames=self.frames(10 + group * 8),
                              collection=dict(mode='dummy', hardware='synthetic'))
                self.app.db.write_json(self.app.db.SEGMENTS / f'{sid}.json', record)
                records.append(record)
        self.app._fit(records)
        self.assertEqual(self.app.training['state'], 'complete', self.app.training)
        model = self.app.model
        self.assertEqual(set(model['segment_ids']), {r['id'] for r in records})
        with np.load(self.app.db.MODELS / model['processed_signals_file'], allow_pickle=False) as audit:
            groups = [set(audit['groups'][audit['split'] == split]) for split in ('train', 'validation', 'test')]
            self.assertTrue(all(not groups[i] & groups[j] for i in range(3) for j in range(i)))
            index = int(np.flatnonzero(audit['record_ids'] == records[0]['id'])[0])
            expected = latest_signal(records[0]['frames'], 'raw_iq_52', 4)['components']
            np.testing.assert_allclose(audit['signals'][index], np.asarray(expected).T, atol=1e-5)
        import zipfile
        exported = self.app.command('export_model', {})['path']
        folder = Path(self.temp.name) / 'portable'
        with zipfile.ZipFile(exported) as archive:
            for name in ('LICENSE', 'NOTICE.md', 'THIRD_PARTY_NOTICES.txt',
                         'LOCAL_SOURCE_MANIFEST.json', 'LOCAL_MODIFICATIONS.json',
                         'reference/soom_engine.py', 'soom_engine.py'):
                self.assertEqual(archive.read(name), (RUNTIME / name).read_bytes())
            archive.extractall(folder)
        bundle = load_bundle(folder / 'model')
        python_result = self.app.teaching.predict_frames(model, records[0]['frames'], 'raw_iq_52')
        portable_result = infer(records[0]['frames'], bundle)
        np.testing.assert_allclose(list(python_result['scores'].values()), list(portable_result['scores'].values()), atol=1e-5)
        self.app.command('import_model', {'path': str(folder / 'model')})
        self.assertIsNotNone(self.app.bundle)
        self.assertEqual(self.app.model['feature_profile'], self.app.profile)

    def test_failed_export_preserves_previous_complete_bundle(self):
        from bridge import export_model_bundle
        output = Path(self.temp.name) / 'previous.zip'
        output.write_bytes(b'previous complete export')
        with patch('edge_export.export_bundle', side_effect=OSError('disk unavailable')):
            with self.assertRaises(OSError):
                export_model_bundle({}, output)
        self.assertEqual(output.read_bytes(), b'previous complete export')
        self.assertEqual(list(output.parent.glob('tmp*.zip')), [])

    def test_07_pi_rejects_training_and_dummy_live_models_cannot_mix(self):
        self.app.allow_training = False
        with self.assertRaisesRegex(ValueError, 'PC'):
            self.app.command('train', {'ids': []})
        self.app.model = {'model_id': 'abc', 'collection': {'mode': 'live', 'hardware': 'c6_ht20_soom_input'}}
        self.attach(self.frames())
        with patch.object(self.app.stream, 'now', return_value=14):
            with self.assertRaisesRegex(ValueError, '모의/실측'):
                self.app.command('recognize', {})
        records = self.app.records()
        self.assertFalse(self.app.services.selection_state([
            records[0], dict(records[0], collection={'mode': 'live', 'hardware': 'c6_ht20_soom_input'})], 4)[0])

    def test_08_http_contract_and_browser_mutation_rejection(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.controller = self.app
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(base + '/state') as response:
                self.assertEqual(json.load(response)['profile'], self.app.profile)
            request = urllib.request.Request(base + '/command/add_behavior', data=b'{"name":"demo"}', headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(request) as response:
                self.assertTrue(json.load(response)['ok'])
            request.add_header('Origin', 'http://example.com')
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(request)
            self.assertEqual(error.exception.code, 403)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_09_polling_uses_metadata_cache_and_buffer_is_bounded(self):
        from stream import dummy_frame
        self.app.record_summaries()
        with patch.object(Path, 'read_text', side_effect=AssertionError('raw files reread')):
            self.assertTrue(self.app.record_summaries())
        frame = dummy_frame(10)
        for _ in range(9000):
            self.app.stream._append(frame)
        self.assertEqual(len(self.app.stream.frames), 8400)

    def test_10_disconnecting_during_preprocessing_cannot_show_old_waveform(self):
        from signal_pipeline import latest_signal
        self.attach(self.frames())
        def disconnect(*args, **kwargs):
            result = latest_signal(*args, **kwargs)
            self.app.stream.stop()
            return result
        with patch.object(self.app.stream, 'now', return_value=14):
            with patch('signal_pipeline.latest_signal', side_effect=disconnect):
                state = self.app.status()
        self.assertIsNone(state['waveform'])
        self.assertFalse(state['fresh'])

    def test_11_real_only_rejects_dummy_without_interrupting_current_input(self):
        self.app.allow_dummy = False
        self.app.capture = Mock(state='recording')
        previous = self.app.stream.snapshot()
        with patch.object(self.app.stream, 'start') as start:
            with patch.object(self.app.recognition, 'stop') as stop:
                with self.assertRaisesRegex(ValueError, '실제 장비 연결 모드'):
                    self.app.command('connect', {'mode': 'dummy'})
                start.assert_not_called()
                stop.assert_not_called()
        self.app.capture.cancel.assert_not_called()
        self.assertEqual(self.app.stream.snapshot()['session'], previous['session'])
        self.assertEqual(self.app.stream.snapshot()['epoch'], previous['epoch'])
        self.app.capture = None
        self.assertFalse(self.app.status()['dummy_allowed'])

    def test_12_real_only_keeps_serial_connect_path(self):
        self.app.allow_dummy = False
        with patch.object(self.app.stream, 'start') as start:
            self.app.command('connect', {'mode': 'live', 'port': 'TEST_PORT',
                                         'baud': 921600})
        start.assert_called_once_with('live', 'TEST_PORT', 921600)

    def test_13_cli_real_only_flag_and_compatible_default(self):
        cases = [([], True, False), (['--real-only'], False, False),
                 (['--passive-receiver'], True, True),
                 (['--real-only', '--passive-receiver'], False, True)]
        for flag, allowed, passive in cases:
            with self.subTest(real_only=not allowed, passive_receiver=passive):
                with patch('sys.argv', ['bridge.py', '--data-dir', self.temp.name] + flag):
                    with patch('bridge.Controller') as controller:
                        with patch('bridge.ThreadingHTTPServer') as server:
                            server.return_value.serve_forever.side_effect = KeyboardInterrupt
                            main()
                        controller.assert_called_once_with(Path(self.temp.name), False,
                                                           allow_dummy=allowed,
                                                           passive_receiver=passive)
                        controller.return_value.close.assert_called_once()

    def test_14_real_only_http_rejects_synthetic_request(self):
        self.app.allow_dummy = False
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.controller = self.app
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(base + '/state') as response:
                self.assertFalse(json.load(response)['dummy_allowed'])
            request = urllib.request.Request(base + '/command/connect',
                                             data=b'{"mode":"dummy"}',
                                             headers={'Content-Type': 'application/json'})
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(request)
            self.assertEqual(error.exception.code, 400)
            self.assertIn('실제 장비 연결 모드', json.load(error.exception)['error'])
            self.assertFalse(self.app.stream.snapshot()['connected'])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_15_training_blocks_model_replacement_and_inference(self):
        self.app.training = {'state': 'running'}
        for action, payload in [('recognize', {}), ('select_model', {'id': 'old'}),
                                ('import_model', {'path': self.temp.name})]:
            with self.subTest(action=action):
                with self.assertRaisesRegex(ValueError, '학습 완료 후'):
                    self.app.command(action, payload)
        self.app.recognition.begin('old-session', 0, 'old-model', 0)
        with patch.object(self.app.services, 'train_selected',
                          return_value={'model_id': 'new-model'}):
            self.app._fit([])
        self.assertFalse(self.app.recognition.running)
        self.assertIsNone(self.app.recognition.result)
        self.assertEqual(self.app.model['model_id'], 'new-model')

    def test_16_bad_catalog_files_do_not_hide_valid_data(self):
        bad_record = self.app.db.SEGMENTS / 'broken-test.json'
        bad_model = self.app.db.MODELS / 'broken-test.json'
        try:
            bad_record.write_text('{unfinished', encoding='utf-8')
            bad_model.write_text('[]', encoding='utf-8')
            state = self.app.status()
            self.assertTrue(state['records'])
            self.assertTrue(state['models'])
            self.assertEqual(len(state['storage_warnings']), 2)
            self.assertNotIn(self.temp.name, '\n'.join(state['storage_warnings']))
            self.assertEqual(bad_record.read_text(), '{unfinished')
            # Invalid content is cached too, but a corrected file is reread.
            self.app.models()
            with patch.object(Path, 'read_text', side_effect=AssertionError('unchanged metadata reread')):
                self.app.models()
            # The cache keys on (mtime_ns, size). Both JSON strings are two bytes,
            # so explicitly change mtime even if rapid writes share a timestamp.
            previous_stat = bad_model.stat()
            bad_model.write_text('{}', encoding='utf-8')
            os.utime(bad_model, ns=(previous_stat.st_atime_ns,
                                   previous_stat.st_mtime_ns + 2_000_000_000))
            self.assertNotEqual(bad_model.stat().st_mtime_ns, previous_stat.st_mtime_ns)
            self.assertEqual(len(self.app.status()['storage_warnings']), 1)
        finally:
            bad_record.unlink(missing_ok=True)
            bad_model.unlink(missing_ok=True)

    def test_17_repeated_and_concurrent_polling_share_identical_waveform(self):
        import numpy as np
        from signal_pipeline import latest_signal
        self.attach(self.frames(0, 139))
        with patch.object(self.app.stream, 'now', return_value=139):
            with patch('signal_pipeline.latest_signal', wraps=latest_signal) as process:
                with ThreadPoolExecutor(max_workers=3) as pool:
                    states = list(pool.map(lambda _: self.app.status(), range(3)))
                self.assertEqual(process.call_count, 1)
                expected = latest_signal(list(self.app.stream.frames), 'raw_iq_52', 4)
                for state in states:
                    np.testing.assert_array_equal(state['waveform']['signal'], expected['signal'])
                self.app.status({'denoise': False})
                self.assertEqual(process.call_count, 2)
        with patch.object(self.app.stream, 'now', return_value=141):
            self.assertIsNone(self.app.status()['waveform'])

    def test_18_new_input_invalidates_cache_and_idle_worker_skips_copy(self):
        from signal_pipeline import latest_signal
        self.attach(self.frames())
        with patch.object(self.app.stream, 'now', return_value=14):
            with patch('signal_pipeline.latest_signal', wraps=latest_signal) as process:
                self.app.status()
                self.app.stream._append(self.frames(14 + 1 / 60, 1)[0])
                self.app.status()
                self.assertEqual(process.call_count, 2)
        with patch.object(self.app.stream, 'snapshot', side_effect=AssertionError('idle full-buffer copy')):
            self.app._advance()

    def test_19_training_reads_only_selected_records(self):
        records = self.app.records()
        ids = [records[0]['id']]
        real_read = Path.read_text
        def selected_only(path, *args, **kwargs):
            if path.parent == self.app.db.SEGMENTS:
                self.assertIn(path.stem, ids)
            return real_read(path, *args, **kwargs)
        with patch.object(Path, 'read_text', selected_only):
            selected = self.app.records(ids)
        self.assertEqual([r['id'] for r in selected], ids)

    def test_20_recent_snapshot_preserves_last_window_and_can_skip_frames(self):
        self.attach(self.frames(0, 139))
        with patch.object(self.app.stream, 'now', return_value=139):
            state = self.app.stream.snapshot(max_seconds=4.025)
            self.assertTrue(state['fresh'])
            self.assertLessEqual(len(state['frames']), 243)
            self.assertGreaterEqual(state['frames'][-1]['t'] - state['frames'][0]['t'], 4)
            self.assertEqual(self.app.stream.snapshot(include_frames=False)['frames'], [])

    def test_21_closed_controller_rejects_commands(self):
        self.app.closed = True
        try:
            with self.assertRaisesRegex(ValueError, '종료 중'):
                self.app.command('connect', {'mode': 'dummy'})
            self.assertFalse(self.app.stream.connected)
        finally:
            self.app.closed = False

    def test_22_failed_http_bind_closes_controller(self):
        with patch('sys.argv', ['bridge.py', '--data-dir', self.temp.name]):
            with patch('bridge.Controller') as controller:
                with patch('bridge.ThreadingHTTPServer', side_effect=OSError('test occupied port')):
                    with self.assertRaises(OSError):
                        main()
                controller.return_value.close.assert_called_once()

    def test_23_missing_selected_model_clears_selection_and_prediction(self):
        self.app.model = {'model_id': 'missing-model'}
        self.app.recognition.begin('session', 0, 'missing-model', 0)
        self.app.recognition.result = {'label': 'old-result'}
        state = self.app.status()
        self.assertIsNone(state['model'])
        self.assertFalse(state['recognition']['running'])
        self.assertIsNone(state['recognition']['result'])

    def test_24_valid_json_with_invalid_model_fields_is_quarantined(self):
        path = self.app.db.MODELS / 'invalid-fields.json'
        try:
            metadata = {'model_id': path.stem, 'feature_profile': self.app.profile, 'labels': None}
            path.write_text(json.dumps(metadata), encoding='utf-8')
            self.assertTrue(self.app.status()['storage_warnings'])
            metadata.update(labels=['A', 'B'], balanced_accuracy=float('nan'))
            path.write_text(json.dumps(metadata), encoding='utf-8')
            state = self.app.status()
            self.assertFalse(any(m['model_id'] == path.stem for m in state['models']))
            self.assertTrue(state['storage_warnings'])
            metadata.update(model_id='duplicate-id', balanced_accuracy=.8)
            path.write_text(json.dumps(metadata), encoding='utf-8')
            self.assertTrue(self.app.status()['storage_warnings'])
        finally:
            path.unlink(missing_ok=True)

    def test_25_passive_receiver_configures_stream_status_request(self):
        for passive in (False, True):
            with self.subTest(passive_receiver=passive):
                with patch('stream.Stream') as stream:
                    controller = Controller(self.temp.name, passive_receiver=passive)
                    try:
                        stream.assert_called_once_with(request_status=not passive)
                    finally:
                        controller.close()

    def test_26_boot_receiver_starts_after_http_bind_and_cleans_up(self):
        argv = ['bridge.py', '--data-dir', self.temp.name, '--real-only',
                '--passive-receiver', '--receiver-port', '/dev/serial/by-id/receiver']
        with patch('sys.argv', argv), patch('bridge.Controller') as controller:
            with patch('bridge.ThreadingHTTPServer') as server:
                server.return_value.serve_forever.side_effect = KeyboardInterrupt
                main()
            controller.assert_called_once_with(Path(self.temp.name), False,
                                               allow_dummy=False, passive_receiver=True)
            controller.return_value.stream.start.assert_called_once_with(
                'live', '/dev/serial/by-id/receiver', 921600, wait_for_device=True)
            controller.return_value.close.assert_called_once()
            server.return_value.server_close.assert_called_once()
        with patch('sys.argv', argv), patch('bridge.Controller') as controller:
            with patch('bridge.ThreadingHTTPServer', side_effect=OSError('occupied')):
                with self.assertRaises(OSError):
                    main()
            controller.return_value.stream.start.assert_not_called()
            controller.return_value.close.assert_called_once()

    def test_27_native_client_empty_query_does_not_change_command_name(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.controller = self.app
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        connection = HTTPConnection('127.0.0.1', server.server_port, timeout=5)
        name = 'Native transport check'
        try:
            for action, suffix, present in [('add_behavior', '?', True),
                                             ('remove_behavior', '?client=native', False)]:
                connection.request('POST', '/command/' + action + suffix,
                                   json.dumps({'name': name}),
                                   {'Content-Type': 'application/json'})
                response = connection.getresponse()
                result = json.loads(response.read())
                self.assertEqual(response.status, 200, result)
                self.assertTrue(result['ok'])
                self.assertEqual(name in self.app.status()['behaviors'], present)
        finally:
            connection.close()
            self.app.command('remove_behavior', {'name': name})
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main(verbosity=2)
