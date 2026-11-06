#!/usr/bin/env python3
"""Small, offline source guardrail. Never prints matching secret text."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
EXCLUDED = {'.git', '.build', '.swiftpm', 'dist', '__pycache__', '.DS_Store'}
PRIVATE_NAMES = {'.env', 'auth.json', '.credentials.json', 'claude-status.json',
                 'claude-bridge-installation.json', 'api-diagnostic.json', 'api-key-format.json', 'network-events.jsonl', 'display-test.jsonl', 'lease.json', 'ready', 'settings.json', 'preferences.json'}
RULES = {
    'credential-like token': re.compile(r'\bsk-(?:ant-(?:admin\d+|usr|api\d*)-|proj-)[A-Za-z0-9_-]{16,}'),
    'private key block': re.compile(r'-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----'),
    'personal absolute home path': re.compile(r'/Users/[A-Za-z0-9_.-]+/'),
    'personal email address': re.compile(r'\b[A-Za-z0-9_.+-]+@(?:gmail|icloud|outlook|yahoo)\.[A-Za-z]+\b', re.I),
}


def source_files(root=ROOT):
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if any(part in EXCLUDED or part.endswith(('.app', '.dSYM')) for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f'Symlinks need manual review: {relative}')
        if path.is_file() and not path.name.endswith(('.zip', '.sha256', '.pyc')):
            yield path


def audit(root=ROOT):
    findings = []
    files = list(source_files(root))
    for path in files:
        relative = path.relative_to(root)
        if path.suffix in {'.jsonl', '.log', '.plist', '.pem', '.key', '.p8', '.p12', '.mobileprovision'} or path.name.endswith('.jsonl.previous') or path.name in PRIVATE_NAMES or (path.name.startswith('.env.') and path.name != '.env.example'):
            findings.append(f'{relative}: local runtime/config file must not be packaged')
        try:
            content = path.read_text(encoding='utf-8')
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(content.splitlines(), 1):
            for name, pattern in RULES.items():
                if pattern.search(line):
                    findings.append(f'{relative}:{number}: {name}')
    if findings:
        print('\n'.join(findings), file=sys.stderr)
        return False
    print(f'Source audit passed ({len(files)} files; selected patterns only).')
    return True


if __name__ == '__main__':
    try:
        sys.exit(0 if audit() else 1)
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)
