"""Standard-library tests; all writes stay in automatically created temp hosts."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import patch_windows_audio as audio_patch


class WindowsAudioPatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="safehub-audio-patch-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.host = root / "host"
        (self.host / "windows").mkdir(parents=True)
        (self.host / "pubspec.yaml").write_text("name: safehub_app\n", encoding="utf-8")
        self.package = root / "package"
        (self.package / "windows").mkdir(parents=True)
        self.source = audio_patch.OLD_DECLARATION + "\n" + audio_patch.OLD_OWNERSHIP
        self.patched = audio_patch.NEW_DECLARATION + "\n" + audio_patch.NEW_OWNERSHIP
        (self.package / audio_patch.CPP_PATH).write_text(self.source, encoding="utf-8")
        (self.package / "pubspec.yaml").write_text(
            "name: audioplayers_windows\nresolution: workspace\nversion: 4.3.0\n",
            encoding="utf-8",
        )
        (self.package / "LICENSE").write_text("fixture MIT notice\n", encoding="utf-8")
        (self.package / "other.txt").write_text("upstream asset\n", encoding="utf-8")
        self.addCleanup(patch.stopall)
        patch.object(audio_patch, "SOURCE_SHA256", audio_patch.digest(self.source)).start()
        patch.object(audio_patch, "PATCHED_SHA256", audio_patch.digest(self.patched)).start()
        patch.object(audio_patch, "LICENSE_SHA256", audio_patch.digest("fixture MIT notice\n")).start()

    def test_copy_preserves_input_license_and_host_pubspec_and_is_idempotent(self):
        original_files = audio_patch.manifest(self.package)
        target = audio_patch.apply_patch(self.host, self.package)
        self.assertEqual(audio_patch.manifest(self.package), original_files)
        self.assertEqual((self.host / "pubspec.yaml").read_text(), "name: safehub_app\n")
        self.assertEqual((target / audio_patch.CPP_PATH).read_text(), self.patched)
        self.assertEqual((target / "LICENSE").read_bytes(), (self.package / "LICENSE").read_bytes())
        self.assertNotIn("resolution: workspace", (target / "pubspec.yaml").read_text())
        self.assertEqual(audio_patch.apply_patch(self.host), target)

    def test_check_only_does_not_create_vendor_or_overrides(self):
        audio_patch.apply_patch(self.host, self.package, check_only=True)
        self.assertFalse((self.host / "vendor").exists())
        self.assertFalse((self.host / "pubspec_overrides.yaml").exists())

    def test_modified_source_or_license_is_rejected_before_writes(self):
        for name in [audio_patch.CPP_PATH, Path("LICENSE")]:
            with self.subTest(name=name):
                path = self.package / name
                old = path.read_bytes()
                path.write_bytes(old + b"modified")
                with self.assertRaises(ValueError):
                    audio_patch.apply_patch(self.host, self.package)
                self.assertFalse((self.host / "vendor").exists())
                path.write_bytes(old)

    def test_existing_user_override_is_preserved(self):
        overrides = self.host / "pubspec_overrides.yaml"
        overrides.write_text("dependency_overrides: {other: any}\n")
        with self.assertRaises(ValueError):
            audio_patch.apply_patch(self.host, self.package)
        self.assertEqual(overrides.read_text(), "dependency_overrides: {other: any}\n")
        self.assertFalse((self.host / "vendor").exists())

    def test_modified_vendor_file_is_rejected_and_not_overwritten(self):
        target = audio_patch.apply_patch(self.host, self.package)
        changed = target / "other.txt"
        changed.write_text("user edit")
        with self.assertRaises(ValueError):
            audio_patch.apply_patch(self.host, self.package)
        self.assertEqual(changed.read_text(), "user edit")

    def test_canonical_project_is_never_modified(self):
        with patch.object(audio_patch, "CANONICAL_APP", self.host):
            with self.assertRaises(ValueError):
                audio_patch.apply_patch(self.host, self.package)
        self.assertFalse((self.host / "vendor").exists())

    def test_resolved_package_path_can_be_read_without_running_flutter(self):
        (self.host / ".dart_tool").mkdir()
        (self.host / ".dart_tool/package_config.json").write_text(json.dumps({
            "packages": [{"name": audio_patch.PLUGIN, "rootUri": self.package.as_uri()}]
        }))
        target = audio_patch.apply_patch(self.host)
        self.assertTrue((target / audio_patch.CPP_PATH).is_file())


if __name__ == "__main__":
    unittest.main()
