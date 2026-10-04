"""Check dependency selection and the portable Python search-path boundary."""

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from package_portable import copy_python, dependency_closure, fresh_settings, validate_output_paths


class PortablePackageTests(unittest.TestCase):
    def test_fresh_settings_follow_the_local_bridge_port(self):
        self.assertEqual(fresh_settings(18768), {'CSI_SERVICE_URL': 'http://127.0.0.1:18768'})

    def test_long_bytecode_temporary_paths_are_rejected_before_copying(self):
        distribution = Mock(files=['torch/ao/pruning/_experimental/data_sparsifier/lightning/callbacks/_data_sparstity_utils.py'])
        validate_output_paths(Path('C:/SafeHub'), {'torch': distribution})
        with self.assertRaises(ValueError):
            validate_output_paths(Path('C:/') / ('long' * 40), {'torch': distribution})

    def test_transitive_markers_and_version_conflicts(self):
        distributions = {
            'app': Mock(version='1.0', requires=['dep>=2', 'never; python_version < "0"']),
            'dep': Mock(version='2.0', requires=[]),
        }
        with patch('package_portable.importlib.metadata.distribution', side_effect=distributions.__getitem__):
            self.assertEqual(set(dependency_closure(['app==1.0'])), {'app', 'dep'})
            with self.assertRaises(ValueError):
                dependency_closure(['dep>=3'])

    def test_python_copy_excludes_host_site_and_outside_record_entries(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            base = root / 'base'
            base.mkdir()
            for name in ('python.exe', 'pythonw.exe', 'python3.dll', 'python312.dll', 'LICENSE.txt'):
                (base / name).write_bytes(b'fixture')
            (base / 'DLLs').mkdir()
            (base / 'Lib/site-packages').mkdir(parents=True)
            (base / 'Lib/site-packages/private.json').write_text('private')
            (base / 'Lib/os.py').write_text('stdlib')
            installed = root / 'installed'
            installed.mkdir()
            (installed / 'public.py').write_text('module')
            support = installed / 'numpy/_core/tests'
            support.mkdir(parents=True)
            (support / '_natype.py').write_text('required runtime helper')
            (support / 'test_unused.py').write_text('unused test')
            (root / 'private.json').write_text('private')
            distribution = Mock(files=['public.py', '../private.json',
                                       'numpy/_core/tests/_natype.py', 'numpy/_core/tests/test_unused.py'])
            distribution.locate_file.side_effect = lambda entry: installed / entry
            destination = root / 'portable'
            copy_python(base, destination, {'public': distribution})
            self.assertEqual((destination / 'Lib/site-packages/public.py').read_text(), 'module')
            self.assertFalse(list(destination.rglob('private.json')))
            self.assertTrue((destination / 'Lib/site-packages/numpy/_core/tests/_natype.py').is_file())
            self.assertFalse(list(destination.rglob('test_unused.py')))
            paths = (destination / 'python312._pth').read_text().splitlines()
            self.assertIn('../service', paths)
            self.assertTrue(all(not Path(path).is_absolute() for path in paths))


if __name__ == '__main__':
    unittest.main(verbosity=2)
