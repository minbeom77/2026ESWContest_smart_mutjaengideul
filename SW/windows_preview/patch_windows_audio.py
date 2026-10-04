"""Copy and patch the pinned Windows audio plugin without editing the Pub cache."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


CANONICAL_APP = Path(__file__).resolve().parents[1] / "safehub_app"
PLUGIN = "audioplayers_windows"
VERSION = "4.3.0"
CPP_PATH = Path("windows/audioplayers_windows_plugin.cpp")
SOURCE_SHA256 = "7d30e6359d6275a64323718d85eb55c1c79cc07da85511ef03f5439f08cc34d2"
PATCHED_SHA256 = "0b6020adeed64d1d7fe4aa0de3407c957d433fd86018c9a4cad99e845ede204c"
LICENSE_SHA256 = "d6c0bdbc83e6bb5f02eed5caf25e6edf174cb56d0ecd6fe19a2cd05b62bbda41"
OVERRIDES = """# Managed by SafeHub patch_windows_audio.py; Windows host only.
dependency_overrides:
  audioplayers_windows:
    path: vendor/audioplayers_windows
"""
OLD_DECLARATION = "static inline std::unique_ptr<EventStreamHandler<>> globalEvents{};"
NEW_DECLARATION = "static inline EventStreamHandler<>* globalEvents = nullptr;"
OLD_OWNERSHIP = """  globalEvents = std::make_unique<EventStreamHandler<>>();
  auto _obj_stm_handle =
      static_cast<StreamHandler<EncodableValue>*>(globalEvents.get());
  std::unique_ptr<StreamHandler<EncodableValue>> _ptr{_obj_stm_handle};
  _globalEventChannel->SetStreamHandler(std::move(_ptr));"""
NEW_OWNERSHIP = """  auto globalEventHandler = std::make_unique<EventStreamHandler<>>();
  globalEvents = globalEventHandler.get();
  _globalEventChannel->SetStreamHandler(std::move(globalEventHandler));"""


def digest(text):
    """Normalize line endings so the same published source works on any host."""
    return hashlib.sha256(text.replace("\r\n", "\n").encode("utf-8")).hexdigest()


def patched_source(source):
    if digest(source) != SOURCE_SHA256:
        raise ValueError("Audio plugin source SHA256 differs from reviewed 4.3.0.")
    if source.count(OLD_DECLARATION) != 1 or source.count(OLD_OWNERSHIP) != 1:
        raise ValueError("Audio plugin ownership patch no longer matches.")
    return source.replace(OLD_DECLARATION, NEW_DECLARATION).replace(
        OLD_OWNERSHIP, NEW_OWNERSHIP
    )


def resolved_package(host):
    config_path = host / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    for package in config["packages"]:
        if package.get("name") == PLUGIN:
            uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
            if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
                raise ValueError("Expected a local resolved Windows audio package.")
            return Path(url2pathname(uri.path)).resolve(strict=True)
    raise ValueError("Run flutter pub get in the Windows host before applying this patch.")


def manifest(folder):
    return {
        path.relative_to(folder).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(folder.rglob("*"))
        if path.is_file() and path.name != "SAFEHUB_PATCH.json"
    }


def apply_patch(host, package=None, check_only=False):
    host = Path(host).expanduser().resolve(strict=True)
    canonical = CANONICAL_APP.resolve()
    if host == canonical or host in canonical.parents or canonical in host.parents:
        raise ValueError("Use a separate Windows host, never the canonical ATLAS app.")
    if not (host / "pubspec.yaml").is_file() or not (host / "windows").is_dir():
        raise ValueError("Expected a generated Flutter Windows host.")
    target = host / "vendor" / PLUGIN
    if not target.resolve().is_relative_to(host) or target.is_symlink():
        raise ValueError("Vendor path must stay inside this Windows host.")
    overrides_path = host / "pubspec_overrides.yaml"
    if overrides_path.is_symlink() or not overrides_path.resolve().is_relative_to(host):
        raise ValueError("Overrides must be a regular file in this Windows host.")
    if overrides_path.exists() and overrides_path.read_text(encoding="utf-8") != OVERRIDES:
        raise ValueError("Existing pubspec_overrides.yaml is not managed by this script.")

    marker_path = target / "SAFEHUB_PATCH.json"
    if target.exists():
        # Idempotent verification only: never overwrite a changed vendor copy.
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        if (marker.get("package") != PLUGIN or marker.get("version") != VERSION
                or marker.get("source_sha256") != SOURCE_SHA256
                or marker.get("patched_sha256") != PATCHED_SHA256
                or digest((target / CPP_PATH).read_text(encoding="utf-8")) != PATCHED_SHA256
                or digest((target / "LICENSE").read_text(encoding="utf-8")) != LICENSE_SHA256
                or marker.get("files") != manifest(target)
                or not overrides_path.exists()):
            raise ValueError("Existing audio vendor copy differs; inspect it manually.")
        return target

    package = Path(package).expanduser().resolve(strict=True) if package else resolved_package(host)
    if (package == target or package in target.parents or target in package.parents):
        raise ValueError("The package input and vendor output must not overlap.")
    pubspec = (package / "pubspec.yaml").read_text(encoding="utf-8")
    if not re.search(rf"(?m)^name: {PLUGIN}\s*$", pubspec) or not re.search(
        rf"(?m)^version: {re.escape(VERSION)}\s*$", pubspec
    ):
        raise ValueError("Only the reviewed audioplayers_windows 4.3.0 is supported.")
    license_text = (package / "LICENSE").read_text(encoding="utf-8")
    if digest(license_text) != LICENSE_SHA256:
        raise ValueError("Audio plugin MIT license differs from the reviewed package.")
    patched = patched_source((package / CPP_PATH).read_text(encoding="utf-8"))
    if digest(patched) != PATCHED_SHA256:
        raise ValueError("Audio patch result differs from its reviewed SHA256.")
    if check_only:
        return target

    # Preserve the upstream package and its MIT notice in the independent copy.
    shutil.copytree(package, target, ignore=shutil.ignore_patterns(".git", ".dart_tool", "build"))
    (target / CPP_PATH).write_text(patched, encoding="utf-8", newline="\n")
    # A published package can retain monorepo metadata; a path copy is standalone.
    pubspec = re.sub(r"(?m)^resolution: workspace\r?\n", "", pubspec)
    (target / "pubspec.yaml").write_text(pubspec, encoding="utf-8", newline="\n")
    marker_path.write_text(json.dumps({
        "package": PLUGIN,
        "version": VERSION,
        "source_sha256": SOURCE_SHA256,
        "patched_sha256": digest(patched),
        "license": "MIT; Copyright (c) 2017 Blue Fire",
        "patch": "single-owner global event stream handler",
        "files": manifest(target),
    }, indent=2) + "\n", encoding="utf-8")
    overrides_path.write_text(OVERRIDES, encoding="utf-8", newline="\n")
    return target


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-dir", type=Path, required=True)
    parser.add_argument("--package-dir", type=Path,
                        help="Optional original audioplayers_windows 4.3.0 directory")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args(argv)
    try:
        target = apply_patch(args.host_dir, args.package_dir, args.check_only)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Windows audio patch failed: {error}", file=sys.stderr)
        return 1
    print(f"Windows audio {'checked' if args.check_only else 'prepared'}: {target}")
    if not args.check_only:
        print("Run flutter pub get in the host, then rebuild the Windows app.")
    print("Pub cache and canonical ATLAS sources were not modified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
