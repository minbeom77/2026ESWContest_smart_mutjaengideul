"""Compare Python reference outputs with the C++ regression fixtures."""

from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

import numpy as np


PYTHON_DIR = Path(__file__).resolve().parents[1]
REPO = PYTHON_DIR.parents[1]
FIXTURES = REPO / "SW/rpi4_sign_cpp/tests/fixtures"
EXPORT = """
import importlib.util
from pathlib import Path
import sys
spec = importlib.util.spec_from_file_location('fixture_export', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.OUTPUT_DIR = Path(sys.argv[2])
module.main()
"""


class ReferenceOutputTests(unittest.TestCase):
    def compare_export(self, script, fixture):
        expected = FIXTURES / fixture
        with tempfile.TemporaryDirectory() as folder:
            actual = Path(folder) / "output"
            run = subprocess.run(
                [sys.executable, "-c", EXPORT,
                 str(PYTHON_DIR / "tools" / script), str(actual)],
                cwd=folder, capture_output=True, text=True, timeout=90,
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            expected_names = {p.name for p in expected.iterdir() if p.is_file()}
            actual_names = {p.name for p in actual.iterdir() if p.is_file()}
            self.assertEqual(actual_names, expected_names)
            for name in sorted(expected_names):
                with self.subTest(file=name):
                    left, right = actual / name, expected / name
                    if name.endswith(".txt"):
                        self.assertEqual(left.read_text(encoding="utf-8").splitlines(),
                                         right.read_text(encoding="utf-8").splitlines())
                        continue
                    self.assertEqual(left.stat().st_size, right.stat().st_size)
                    if re.search(r"_(?:id|ids)(?:_|\.bin)|flags|counts|rescued", name):
                        self.assertEqual(left.read_bytes(), right.read_bytes())
                        continue
                    dtype = (np.float64 if name.endswith(
                        ("_margins.bin", "_confidence.bin", "_both_ratio.bin"))
                        else np.float32)
                    np.testing.assert_allclose(
                        np.fromfile(left, dtype=dtype), np.fromfile(right, dtype=dtype),
                        rtol=0, atol=1e-5, equal_nan=True,
                    )

    def test_fifteen_class_reference_predictions(self):
        self.compare_export("class_15_frozen_expected_export.py", "class_15_inference_frozen")

    def test_hand_selection_and_coordinates(self):
        self.compare_export("hand_input_frozen_expected_export.py", "hand_input_frozen")

    def test_negative_overlap_input(self):
        self.compare_export("temp_negative_python_fixture_export.py", "temp_negative_synthetic")

    def test_positive_reference_input(self):
        self.compare_export("temp_positive_fixture_export.py", "temp_positive_real01")

    def test_cpp_fixture_generators_load_reference_from_another_directory(self):
        code = """
import importlib.util
from pathlib import Path
import sys
folder = Path(sys.argv[1])
for name in ('generate_hot_rescue_fixture.py', 'generate_last40_fixture.py',
             'generate_handshape40_fixture.py', 'verify_hot_fixture_candidates.py'):
    spec = importlib.util.spec_from_file_location('generator', folder / name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.load_frozen_07g()
"""
        with tempfile.TemporaryDirectory() as folder:
            run = subprocess.run(
                [sys.executable, "-c", code, str(FIXTURES.parent)],
                cwd=folder, capture_output=True, text=True, timeout=90,
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_vision_adapter_loads_reference_from_another_directory(self):
        code = """
import sys
sys.path.insert(0, sys.argv[1])
from offline_sign_pipeline import load_runtime
runtime = load_runtime()
references = runtime.load_onehand_calibration()
assert references['local'].shape == (42, 80, 84)
"""
        with tempfile.TemporaryDirectory() as folder:
            run = subprocess.run(
                [sys.executable, "-c", code, str(REPO / "SW/rpi4_vision_atlas")],
                cwd=folder, capture_output=True, text=True, timeout=90,
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
