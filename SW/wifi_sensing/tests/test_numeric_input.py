"""Compare numeric conversion with the preserved adapter, without RF claims."""

import copy
import importlib.util
import itertools
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

RUNTIME = Path(__file__).resolve().parents[1] / 'runtime'
sys.path.insert(0, str(RUNTIME))
import soom_engine as active
import signal_pipeline
from soom_processing import preprocess_stages


def load_engine(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reference = load_engine(RUNTIME / 'reference/soom_engine.py', 'reference_engine')


def frames(count=241, epoch=10):
    rng = np.random.default_rng(3019)
    iq = rng.integers(-128, 128, (count, 128)).tolist()
    return [dict(t=epoch + i / 60, device_t=epoch + i / 60,
                 iq=row, amp=[0] * 52) for i, row in enumerate(iq)]


class NumericInputTests(unittest.TestCase):
    def assert_equal_conversion(self, records):
        old = reference.preprocessor_dataframe(records)
        new = active.preprocessor_dataframe(records)
        np.testing.assert_array_equal(old['timestamp'], new['timestamp'])
        np.testing.assert_array_equal(np.vstack(old['amplitude']),
                                      np.vstack(new['amplitude']))
        return old, new

    def test_boundaries_random_values_and_timestamp_rounding(self):
        for epoch in (0, 10.123456789, 1754212000.1234567):
            records = frames(epoch=epoch)
            records[0]['iq'] = [-128, 127] * 64
            records[1]['iq'] = [0] * 128
            records[2]['iq'] = [127.0] * 128
            with self.subTest(epoch=epoch):
                self.assert_equal_conversion(records)

    def test_device_timestamp_precedence_and_no_mutation(self):
        records = frames()
        for record in records:
            record['t'] += 1_000_000
        before = copy.deepcopy(records)
        self.assert_equal_conversion(records)
        self.assertEqual(records, before)
        self.assertTrue(np.any(np.vstack(active.preprocessor_dataframe(records)['amplitude'])))

    def test_legacy_bool_rows_keep_original_zero_fallback(self):
        records = frames(2)
        records[0]['iq'][10] = True
        self.assert_equal_conversion(records)
        self.assertTrue(np.all(active.preprocessor_dataframe(records)['amplitude'][0] == 0))

    def test_invalid_records_keep_original_exception_type(self):
        cases = [[], [dict(t=0, iq=[0] * 127)], [dict(t=0, iq=None)]]
        for value in (128, -129, .5, float('nan'), float('inf'), None, 'x',
                      np.int64(1), 10 ** 100):
            record = frames(2)
            record[0]['iq'][0] = value
            cases.append(record)
        for timestamp in (float('nan'), float('inf'), 'bad', -1):
            record = frames(2)
            record[1]['device_t'] = timestamp
            cases.append(record)
        for index, records in enumerate(cases):
            with self.subTest(case=index):
                with self.assertRaises(Exception) as old_error:
                    reference.preprocessor_dataframe(records)
                with self.assertRaises(type(old_error.exception)):
                    active.preprocessor_dataframe(records)

    def test_all_stage_toggle_combinations_are_identical(self):
        old, new = self.assert_equal_conversion(frames())
        processor = active.RealtimePreprocessor()
        old_sample = processor._resample_multichannel_signal(old, 240)
        new_sample = processor._resample_multichannel_signal(new, 240)
        np.testing.assert_array_equal(old_sample, new_sample)
        for flags in itertools.product((False, True), repeat=4):
            options = dict(zip(('denoise', 'normalize', 'pca', 'lowpass'), flags))
            for carrier in (0, 25, 51):
                with self.subTest(flags=flags, carrier=carrier):
                    np.testing.assert_array_equal(
                        preprocess_stages(old_sample, subcarrier=carrier, **options),
                        preprocess_stages(new_sample, subcarrier=carrier, **options))
        np.testing.assert_array_equal(processor.run(old, 240), processor.run(new, 240))

    def test_display_training_input_and_fixed_model_scores_are_identical(self):
        import torch
        from cnn_runtime import probabilities
        torch.set_num_threads(1)
        records = frames()
        with patch.object(signal_pipeline, 'preprocessor_dataframe', reference.preprocessor_dataframe):
            old_display = signal_pipeline.latest_signal(records, 'raw_iq_52')
            old_features = np.asarray(signal_pipeline.window_features(records, 'raw_iq_52'))
        new_display = signal_pipeline.latest_signal(records, 'raw_iq_52')
        new_features = np.asarray(signal_pipeline.window_features(records, 'raw_iq_52'))
        np.testing.assert_array_equal(old_display['components'], new_display['components'])
        np.testing.assert_array_equal(old_features, new_features)
        torch.manual_seed(3019)
        model = active.Simple1DCNN(num_classes=2, input_length=240).eval()
        weights = {key: value.detach().numpy() for key, value in model.state_dict().items()}
        old_scores = probabilities(weights, old_features, 1)
        new_scores = probabilities(weights, new_features, 1)
        np.testing.assert_array_equal(old_scores, new_scores)
        with torch.no_grad():
            pc_scores = torch.softmax(model(torch.from_numpy(new_features)), dim=1).numpy()
        np.testing.assert_allclose(new_scores, pc_scores, atol=1e-6, rtol=1e-5)

    def test_manifest_detects_active_and_reference_tampering(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ('soom_engine.py', 'LOCAL_SOURCE_MANIFEST.json', 'LOCAL_MODIFICATIONS.json'):
                shutil.copyfile(RUNTIME / name, root / name)
            for name in active.json.loads((RUNTIME / 'LOCAL_SOURCE_MANIFEST.json').read_text())['files']:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(RUNTIME / name, target)
            (root / 'reference').mkdir()
            shutil.copyfile(RUNTIME / 'reference/soom_engine.py', root / 'reference/soom_engine.py')
            checker = load_engine(root / 'soom_engine.py', 'isolated_engine')
            with patch.object(checker, 'verify_vendor', return_value={}):
                self.assertEqual(checker.verify_runtime()['modified_files'], 1)
                for name in ('soom_engine.py', 'reference/soom_engine.py'):
                    target = root / name
                    original = target.read_bytes()
                    target.write_bytes(original + b'\n# altered\n')
                    with self.assertRaises(ValueError):
                        checker.verify_runtime()
                    target.write_bytes(original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
