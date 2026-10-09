"""Exercise bootstrap ordering with systemctl stubbed and a temporary /data tree."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class BootTests(unittest.TestCase):
    def run_boot(self, *, local_stt=False, reload_fails=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            unit_dir = root / "data/share/usr/lib/systemd/system"
            unit_dir.mkdir(parents=True)
            if local_stt:
                (unit_dir / "safehub-stt.service").touch()
            calls = root / "calls"
            systemctl = root / "systemctl"
            systemctl.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$*" >> "$SAFEHUB_TEST_CALLS"\n'
                'if [ "$1" = daemon-reload ] && '
                '[ "$SAFEHUB_TEST_RELOAD_FAIL" = 1 ]; then exit 1; fi\n',
                encoding="utf-8",
            )
            systemctl.chmod(0o755)
            # Relocate only the filesystem prefix, without touching /data on the host.
            source = Path(__file__).with_name("boot.sh").read_text(encoding="utf-8")
            script = root / "boot.sh"
            script.write_text(source.replace("/data/", f"{root}/data/"), encoding="utf-8")
            result = subprocess.run(
                ["sh", str(script)],
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "SAFEHUB_TEST_CALLS": str(calls),
                     "SAFEHUB_TEST_RELOAD_FAIL": "1" if reload_fails else "0"},
                capture_output=True, text=True, check=False,
            )
            return result.returncode, calls.read_text().splitlines()

    def test_local_stt_starts_after_reload_and_base_services(self):
        code, calls = self.run_boot(local_stt=True)
        self.assertEqual(code, 0)
        self.assertEqual(calls, [
            "daemon-reload",
            "--no-block start safehub-mqtt.service safehub-csi.service safehub-ui.service",
            "--no-block start safehub-stt.service",
        ])

    def test_external_stt_host_does_not_start_missing_unit(self):
        code, calls = self.run_boot()
        self.assertEqual(code, 0)
        self.assertEqual(calls, [
            "daemon-reload",
            "--no-block start safehub-mqtt.service safehub-csi.service safehub-ui.service",
        ])

    def test_failed_reload_prevents_service_start(self):
        code, calls = self.run_boot(local_stt=True, reload_fails=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, ["daemon-reload"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
