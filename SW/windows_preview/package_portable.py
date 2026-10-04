"""Bundle a Windows x64 app with an isolated Python runtime and its dependencies."""

import argparse
import compileall
import hashlib
import importlib.metadata
import importlib.util
import json
import py_compile
from pathlib import Path
import shutil
import subprocess
import sys

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

REPO = Path(__file__).resolve().parents[2]
SW = REPO / 'SW'
# NumPy testing helpers are imported by SciPy's array API at runtime.
RUNTIME_SUPPORT = {'numpy/_core/tests/__init__.py', 'numpy/_core/tests/_natype.py'}


def fresh_settings(port):
    """Point the UI at this package's bridge, regardless of build defaults."""
    return {'CSI_SERVICE_URL': f'http://127.0.0.1:{port}'}


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_manifest(output, distributions):
    service = output / 'service'
    manifest = dict(commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO,
                                                   encoding='utf-8').strip(),
                    scope='Windows x64 real-mode portable package; no personal data',
                    python=sys.version, distributions={name: dist.version for name, dist in distributions.items()},
                    packaging_sources={name: sha256(Path(__file__).with_name(name))
                                       for name in ('Launcher.cs', 'package_portable.py')},
                    files={path.relative_to(output).as_posix(): {
                               'size': path.stat().st_size,
                               **({'sha256': sha256(path)} if path.suffix in ('.exe', '.dll', '.pyd')
                                  or path.is_relative_to(service) else {})}
                           for path in output.rglob('*') if path.is_file() and path.name != 'package-manifest.json'})
    (output / 'package-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest


def dependency_closure(requirements):
    """Resolve installed runtime dependencies, excluding optional extras."""
    selected = {}
    pending = [Requirement(line) for line in requirements]
    while pending:
        requirement = pending.pop()
        if requirement.marker and not requirement.marker.evaluate({'extra': ''}):
            continue
        name = canonicalize_name(requirement.name)
        distribution = importlib.metadata.distribution(requirement.name)
        if not requirement.specifier.contains(distribution.version):
            raise ValueError(f'Installed version does not satisfy {requirement}')
        if name in selected:
            continue
        selected[name] = distribution
        pending.extend(Requirement(value) for value in distribution.requires or [])
    return selected


def validate_output_paths(output, distributions):
    """Catch Windows bytecode temporary-path limits before copying libraries."""
    for distribution in distributions.values():
        for entry in distribution.files or []:
            relative = Path(entry)
            if (relative.is_absolute() or relative.suffix != '.py'
                    or any(part in ('..', 'test', 'tests', '__pycache__') for part in relative.parts)):
                continue
            source = output / 'python/Lib/site-packages' / relative
            cache = importlib.util.cache_from_source(str(source))
            if len(cache.encode('utf-16-le')) // 2 + 16 >= 260:
                raise ValueError('Use a shorter output path, such as C:/SafeHubPortable.')


def copy_python(base, destination, distributions):
    destination.mkdir()
    for name in ('python.exe', 'pythonw.exe', 'python3.dll', 'python312.dll', 'LICENSE.txt'):
        shutil.copy2(base / name, destination / name)
    shutil.copytree(base / 'DLLs', destination / 'DLLs',
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '*.lib', '*.pdb'))
    shutil.copytree(base / 'Lib', destination / 'Lib',
                    ignore=shutil.ignore_patterns('site-packages', '__pycache__', '*.pyc', 'test', 'tests', 'idlelib'))
    site = destination / 'Lib/site-packages'
    site.mkdir()
    for distribution in distributions.values():
        installed_site = Path(distribution.locate_file('')).resolve()
        for entry in distribution.files or []:
            source = Path(distribution.locate_file(entry)).resolve()
            if not source.is_relative_to(installed_site):
                continue
            relative = source.relative_to(installed_site)
            if (not source.is_file()
                    or source.suffix in ('.pyc', '.lib', '.pdb', '.h', '.hpp', '.a')
                    or '__pycache__' in relative.parts
                    or (any(part in ('test', 'tests') for part in relative.parts)
                        and relative.as_posix() not in RUNTIME_SUPPORT)):
                continue
            target = site / source.relative_to(installed_site)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    # Ignore the host's registry, PYTHONPATH and user site-packages.
    (destination / 'python312._pth').write_text(
        '.\nLib\nDLLs\nLib/site-packages\n../service\nimport site\n', encoding='ascii')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', required=True, type=Path)
    parser.add_argument('--crt', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--port', type=int, default=8768)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or output.is_relative_to(REPO) or not 1 <= args.port <= 65535:
        parser.error('Use a new folder outside the repository and a valid port.')
    requirements = [line.strip() for line in (SW / 'wifi_sensing/requirements.txt').read_text().splitlines()
                    if line.strip() and not line.lstrip().startswith('#')]
    distributions = dependency_closure(requirements)
    validate_output_paths(output, distributions)
    output.mkdir(parents=True)
    shutil.copytree(args.build, output / 'app')
    service = output / 'service'
    service.mkdir()
    for name in ('bridge.py', 'stream.py', 'README.md', 'requirements.txt'):
        shutil.copy2(SW / 'wifi_sensing' / name, service / name)
    tracked = subprocess.check_output(['git', 'ls-files', '-z', '--', 'SW/wifi_sensing/runtime'],
                                     cwd=REPO, encoding='utf-8').rstrip('\0').split('\0')
    for name in tracked:
        source = REPO / name
        target = service / source.relative_to(SW / 'wifi_sensing')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    base = Path(sys._base_executable).parent
    copy_python(base, output / 'python', distributions)
    for destination in (output / 'python', output / 'app'):
        for dll in args.crt.glob('*.dll'):
            shutil.copy2(dll, destination / dll.name)
    data = output / 'data'
    data.mkdir()
    (data / 'connection-settings.json').write_text(
        json.dumps(fresh_settings(args.port)) + '\n', encoding='utf-8')
    config = dict(python_exe='python/python.exe', python_site_packages='python/Lib/site-packages',
                  bridge_script='service/bridge.py', data_dir='data/csi',
                  app_exe='app/safehub_app.exe', settings_file='data/connection-settings.json',
                  real_only=True, isolated_python=True, port=args.port, startup_timeout_seconds=180)
    (output / 'config.json').write_text(json.dumps(config, indent=2) + '\n', encoding='utf-8')
    compiler = Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe')
    subprocess.run([str(compiler), '/nologo', '/target:winexe', '/platform:x64', '/optimize+',
                    '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
                    '/reference:System.Web.Extensions.dll',
                    '/out:' + str(output / 'SafeHub 시작.exe'), str(Path(__file__).with_name('Launcher.cs'))],
                   check=True)
    licenses = output / 'licenses'
    shutil.copytree(Path(__file__).with_name('licenses'), licenses)
    shutil.copy2(SW / 'wifi_sensing/runtime/LICENSE', licenses / 'CSI-MIT.txt')
    shutil.copy2(Path(__file__).with_name('audioplayers_windows-4.3.0-ownership.patch'),
                 licenses / 'audioplayers_windows-ownership.patch')
    (licenses / 'runtime-sources.txt').write_text(
        'Python license: ../python/LICENSE.txt\nPython package licenses: ../python/Lib/site-packages/*dist-info\n'
        'Visual C++ application-local runtime: Microsoft.VC145.CRT\n'
        'https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files\n'
        'Flutter/plugin licenses: ../app/data/flutter_assets/NOTICES.Z\n', encoding='utf-8')
    (output / '먼저 읽기.txt').write_text(
        'SafeHub · Windows 10/11 64비트 전달본\n\n'
        '1. ZIP을 전부 압축 풀고 폴더 안의 SafeHub 시작.exe를 실행하세요.\n'
        '2. Python이나 Visual Studio 설치는 필요하지 않습니다.\n'
        '   처음 실행하는 PC에서는 준비에 최대 3분 정도 걸릴 수 있습니다.\n'
        '3. 실제 모드입니다. 보드·카메라 서버가 없으면 연결 대기로 표시합니다.\n'
        '4. 연결 설정에서 본인의 MQTT·카메라·음성 서비스 주소를 입력하세요.\n'
        '5. 와이파이 센싱에서 펌웨어가 준비된 ESP32 수신기의 COM 포트를 선택하세요.\n'
        '6. 신호 수집 → 기록 선택·학습 → 현재 행동 순서로 사용하세요.\n\n'
        '수어 인식 서버·ESP32 펌웨어·카메라·스피커 등 장비는 별도로 준비해야 합니다.\n'
        '보낸 사람의 기록·모델·비밀번호는 포함하지 않았습니다.\n'
        '새 설정과 기록은 data, 실행 로그는 logs에 생성됩니다. 폴더 전체를 함께 옮기세요.\n'
        'macOS·Linux·라즈베리파이용 실행파일이 아닙니다.\n', encoding='utf-8-sig')
    if not compileall.compile_dir(output / 'python/Lib', quiet=1, stripdir=str(output), workers=1,
                                 invalidation_mode=py_compile.PycInvalidationMode.CHECKED_HASH):
        raise ValueError('Bundled Python bytecode compilation failed.')
    manifest = write_manifest(output, distributions)
    print(json.dumps(dict(path=str(output), files=len(manifest['files']), packages=manifest['distributions']), indent=2))


if __name__ == '__main__':
    main()
