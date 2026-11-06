#!/usr/bin/env python3
"""Package reviewed source and hidden GitHub files, never runtime or Git history."""
from pathlib import Path
import os
import re
import zipfile
import importlib.util

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('insomnia_source_audit', ROOT / 'scripts/audit-source.py')
audit_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_module)
if not audit_module.audit(ROOT):
    raise SystemExit('Source package refused: review audit findings first.')
version = (ROOT / 'VERSION').read_text().strip()
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
    raise SystemExit('Invalid VERSION')
output = Path(os.environ.get('INSOMNIA_OUTPUT_DIR', ROOT / 'dist'))
if not output.is_absolute():
    output = ROOT / output
output.mkdir(parents=True, exist_ok=True)
archive_path = output / f'Insomnia-v{version}-source.zip'
with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
    for source in audit_module.source_files(ROOT):
        relative = source.relative_to(ROOT)
        # The output folder may have been customized outside the usual dist/ path.
        if source == archive_path or output in source.parents:
            continue
        archive.write(source, Path('Insomnia') / relative)
print(f'Source archive: {archive_path}')
