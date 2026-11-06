#!/usr/bin/env python3
"""Manage this project's per-user login LaunchAgent; no administrator rights."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

LABEL = 'local.insomnia.autostart'
PLIST = Path.home() / 'Library/LaunchAgents/local.insomnia.plist'
TARGET = f'gui/{os.getuid()}/{LABEL}'


def launchctl(*args):
    return subprocess.run(['/bin/launchctl', *args], text=True, capture_output=True)


def existing():
    if not PLIST.exists():
        return None
    with PLIST.open('rb') as stream:
        value = plistlib.load(stream)
    if value.get('Label') != LABEL:
        raise SystemExit(f'Refusing to change an unrelated file: {PLIST}')
    return value


def install(app):
    app = app.expanduser().resolve()
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != 'local.insomnia':
        raise SystemExit('The selected bundle is not Insomnia.')
    if not (app / 'Contents/MacOS' / info['CFBundleExecutable']).is_file():
        raise SystemExit('The app executable is missing; build the app first.')
    existing()  # Refuse an unrelated pre-existing file.
    config = {'Label': LABEL, 'ProgramArguments': ['/usr/bin/open', '-g', str(app)],
              'RunAtLoad': True, 'LimitLoadToSessionType': 'Aqua', 'ProcessType': 'Background'}
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    launchctl('bootout', TARGET)  # Not loaded is an expected first-install condition.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=PLIST.parent, prefix='insomnia-', delete=False) as stream:
            temporary = Path(stream.name)
            plistlib.dump(config, stream)
        temporary.chmod(0o644)
        os.replace(temporary, PLIST)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
    launchctl('enable', TARGET)
    result = launchctl('bootstrap', f'gui/{os.getuid()}', str(PLIST))
    if result.returncode:
        raise SystemExit(f'LaunchAgent was saved but could not be loaded: {result.stderr.strip()}')
    status()


def uninstall():
    if existing() is None:
        print('This LaunchAgent is not installed.')
        return
    launchctl('bootout', TARGET)
    PLIST.unlink()
    print('LaunchAgent removed. The app and its data were preserved.')
    print('A separately enabled SMAppService login item is not changed by this command.')


def status():
    config = existing()
    print(f'LaunchAgent: {PLIST}')
    print('Installed:', bool(config))
    if config:
        print('Application:', config.get('ProgramArguments', [])[-1])
    result = launchctl('print', TARGET)
    print('Loaded in launchd:', result.returncode == 0)
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            if any(key in line for key in ['state =', 'runs =', 'last exit code =']):
                print(line.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    command = sub.add_parser('install', help='Enable login launch for an existing Insomnia.app')
    command.add_argument('app', type=Path)
    sub.add_parser('status', help='Show this LaunchAgent only')
    sub.add_parser('uninstall', help='Remove this LaunchAgent; preserve app and data')
    args = parser.parse_args()
    if args.action == 'install':
        install(args.app)
    elif args.action == 'uninstall':
        uninstall()
    else:
        status()


if __name__ == '__main__':
    main()
