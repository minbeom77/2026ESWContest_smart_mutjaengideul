"""Copy production Dart sources into a fresh, non-ATLAS host test folder."""
import argparse
from pathlib import Path
import re
import shutil


CSI_FILES = (
    'lib/services/wifi_sensing_service.dart',
    'lib/ui/widgets/wifi_sensing_panel.dart',
    'test/wifi_sensing_panel_test.dart',
    'test/wifi_sensing_service_test.dart',
    'assets/fonts/Pretendard-Regular.otf',
)
CSI_PUBSPEC = '''name: safehub_app
environment:
  sdk: '>=3.6.2 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.2
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
  assets:
    - assets/fonts/Pretendard-Regular.otf
'''
ATLAS_DEPENDENCIES = {'audioplayers_atlas', 'record_atlas'}


def host_pubspec(text: str) -> str:
    """Remove only the two ATLAS path dependencies from the original YAML."""
    lines = text.splitlines(keepends=True)
    output = []
    removed = set()
    section = None
    index = 0
    while index < len(lines):
        line = lines[index]
        top_level = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):', line)
        if top_level:
            section = top_level.group(1)
        dependency = re.match(r'^  ([A-Za-z_][A-Za-z0-9_]*):\s*$', line)
        if (section == 'dependencies' and dependency
                and dependency.group(1) in ATLAS_DEPENDENCIES):
            name = dependency.group(1)
            if name in removed:
                raise ValueError(f'Duplicate dependency: {name}')
            if (index + 1 >= len(lines)
                    or not re.match(r'^    path:\s*\S.*$', lines[index + 1])):
                raise ValueError(f'Expected one path entry for {name}')
            following = index + 2
            if (following < len(lines) and lines[following].strip()
                    and lines[following].startswith('    ')):
                raise ValueError(f'Unexpected extra dependency options: {name}')
            removed.add(name)
            index += 2
            continue
        output.append(line)
        index += 1
    if removed != ATLAS_DEPENDENCIES:
        raise ValueError('The two expected ATLAS path dependencies were not found')
    return ''.join(output)


def validate_target(target: Path, source: Path) -> None:
    repository = source.parents[1]
    if target == Path(target.anchor):
        raise ValueError('A filesystem root cannot be used as the output folder')
    if (target == repository or repository in target.parents
            or target in repository.parents):
        raise ValueError('Use an output folder outside the source repository')
    if target.exists():
        if not target.is_dir() or any(target.iterdir()):
            raise ValueError('The output folder must be new or completely empty')


def prepare(source: Path, target: Path, *, full: bool = False) -> int:
    source = source.resolve()
    target = target.expanduser().resolve()
    validate_target(target, source)
    if full:
        files = sorted(
            path.relative_to(source)
            for directory in ('lib', 'test', 'assets')
            for path in (source / directory).rglob('*')
            if path.is_file()
        )
        files.append(Path('analysis_options.yaml'))
        pubspec = host_pubspec((source / 'pubspec.yaml').read_text(encoding='utf-8'))
    else:
        files = [Path(relative) for relative in CSI_FILES]
        pubspec = CSI_PUBSPEC
    for relative in files:
        path = source / relative
        if not path.is_file() or not path.resolve().is_relative_to(source):
            raise ValueError(f'Invalid source file: {relative}')

    target.mkdir(parents=True, exist_ok=True)
    for relative in files:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.parent.resolve().is_relative_to(target):
            raise ValueError(f'Output path leaves the target folder: {relative}')
        # Exclusive creation also refuses files added after the empty-folder check.
        with (source / relative).open('rb') as original:
            with destination.open('xb') as copied:
                shutil.copyfileobj(original, copied)
        shutil.copystat(source / relative, destination)
    with (target / 'pubspec.yaml').open('x', encoding='utf-8', newline='\n') as output:
        output.write(pubspec)
    return len(files)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='New or empty folder outside the repository')
    parser.add_argument('--full', action='store_true', help='Copy the complete SafeHub app and tests')
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / 'safehub_app'
    try:
        count = prepare(source, args.output, full=args.full)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f'{args.output.expanduser().resolve()} ({count} source files)')


if __name__ == '__main__':
    main()
