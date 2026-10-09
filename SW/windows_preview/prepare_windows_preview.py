"""Prepare a separate Windows host without changing the ATLAS app sources."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys

from patch_windows_audio import apply_patch as prepare_windows_audio


SOURCE = Path(__file__).resolve().parents[1] / "safehub_app"
ATLAS_PACKAGES = {"audioplayers_atlas", "record_atlas"}


def host_pubspec(text):
    """Remove only the two host-incompatible path dependencies."""
    lines = text.splitlines(keepends=True)
    result, removed = [], set()
    index = 0
    while index < len(lines):
        match = re.fullmatch(r"  ([a-z_]+):\s*", lines[index].rstrip("\r\n"))
        if match and match[1] in ATLAS_PACKAGES:
            removed.add(match[1])
            index += 1
            while index < len(lines):
                line = lines[index]
                if line.strip() and len(line) - len(line.lstrip()) <= 2:
                    break
                index += 1
        else:
            result.append(lines[index])
            index += 1
    if removed != ATLAS_PACKAGES:
        raise ValueError("Expected both ATLAS path dependencies in the source pubspec.")
    return "".join(result)


def preflight(flutter_path, output_dir):
    flutter_path = flutter_path.expanduser().resolve(strict=True)
    output_dir = output_dir.expanduser().resolve()
    if not flutter_path.is_file():
        raise ValueError("--flutter-path must name the Flutter executable (bin/flutter.bat).")
    if output_dir.exists():
        raise ValueError("--output-dir must be a new directory; existing files are never replaced.")
    if SOURCE == output_dir or SOURCE in output_dir.parents or output_dir in SOURCE.parents:
        raise ValueError("The output directory must be separate from the canonical app.")
    for name in ("lib", "assets", "pubspec.yaml"):
        if not (SOURCE / name).exists():
            raise ValueError(f"Missing source input: {name}")
    pubspec = host_pubspec((SOURCE / "pubspec.yaml").read_text(encoding="utf-8"))
    return flutter_path, output_dir, pubspec


def prepare(flutter_path, output_dir, pubspec, build=False, real=False):
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [str(flutter_path), "create", "--platforms=windows", "--no-pub",
         "--project-name=safehub_app", "--org=org.mutjaengideul", str(output_dir)],
        check=True,
    )
    for name in ("lib", "assets"):
        shutil.copytree(SOURCE / name, output_dir / name, dirs_exist_ok=True)
    (output_dir / "pubspec.yaml").write_text(pubspec, encoding="utf-8")

    # This change is limited to the newly generated host runner.
    runner = output_dir / "windows" / "runner" / "main.cpp"
    text = runner.read_text(encoding="utf-8")
    text = re.sub(r"Win32Window::Size size\(\d+,\s*\d+\);",
                  "Win32Window::Size size(1280, 840);", text)
    text = text.replace('window.Create(L"safehub_app",',
                        'window.Create(L"SafeHub - Sign & WiFi Sensing",')
    runner.write_text(text, encoding="utf-8")

    if build:
        subprocess.run([str(flutter_path), "pub", "get"], cwd=output_dir, check=True)
        prepare_windows_audio(output_dir)
        subprocess.run([str(flutter_path), "pub", "get"], cwd=output_dir, check=True)
        subprocess.run(
            [str(flutter_path), "build", "windows", "--release",
             f"--dart-define=APP_LOCAL_PREVIEW={'false' if real else 'true'}"],
            cwd=output_dir, check=True,
        )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter-path", type=Path, required=True,
                        help="Full path to the installed Flutter bin/flutter.bat")
    parser.add_argument("--output-dir", type=Path, required=True,
                        help="New directory outside SW/safehub_app")
    parser.add_argument("--real", action="store_true",
                        help="Build for real device connections with editable settings")
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--build", action="store_true",
                         help="Also resolve packages and build the Windows release app")
    actions.add_argument("--check-only", action="store_true",
                         help="Validate paths and pubspec without writing or running Flutter")
    args = parser.parse_args(argv)
    try:
        flutter, output, pubspec = preflight(args.flutter_path, args.output_dir)
        if args.check_only:
            print("Input checks passed. No files changed and Flutter was not started.")
            return 0
        if sys.platform != "win32":
            raise ValueError("Prepare the Windows preview on Windows.")
        prepare(flutter, output, pubspec, args.build, args.real)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"Windows preview preparation failed: {exc}", file=sys.stderr)
        print("An incomplete output folder is preserved for inspection.", file=sys.stderr)
        return 1
    print(f"Windows host: {output}")
    print("The canonical ATLAS project has not been changed.")
    if not args.build:
        mode = 'false' if args.real else 'true'
        print("Run flutter pub get, patch_windows_audio.py --host-dir <this host>, "
              "then flutter pub get again before building.")
        print("Build with flutter build windows --release "
              f"--dart-define=APP_LOCAL_PREVIEW={mode} from this host folder.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
