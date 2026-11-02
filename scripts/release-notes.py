#!/usr/bin/env python3
"""Generate a release body from the matching checked-in changelog section."""
import argparse
import pathlib
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--version', required=True)
parser.add_argument('--zip-name', required=True)
parser.add_argument('--sha256', required=True)
parser.add_argument('--commit', required=True)
args = parser.parse_args()
if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
    parser.error('version must be MAJOR.MINOR.PATCH')
if not re.fullmatch(r'[0-9a-f]{64}', args.sha256):
    parser.error('sha256 must be a lowercase SHA-256 digest')
if args.zip_name != f'Nudge-{args.version}.zip':
    parser.error('zip name must match the release version')
if not re.fullmatch(r'[0-9a-f]{40}', args.commit):
    parser.error('commit must be a full commit SHA')

changelog = (pathlib.Path(__file__).resolve().parent.parent / 'CHANGELOG.md').read_text()
match = re.search(
    rf'^## {re.escape(args.version)}(?:\s|$)[^\n]*\n(.*?)(?=^## |\Z)',
    changelog,
    re.MULTILINE | re.DOTALL,
)
if not match:
    parser.error(f'CHANGELOG.md has no section for {args.version}')

print(f'Nudge {args.version} — signed with Developer ID and notarized by Apple.\n')
print(match.group(1).strip())
print(f'''
## Install

1. Download `{args.zip_name}` from the release assets.
2. Quit Nudge, unzip the download, and replace Nudge.app in Applications.
3. Open Nudge. Your existing counts and team settings are preserved.
4. New teammates choose a unique name and enter the shared team password.

## Verify download integrity

```bash
shasum -a 256 {args.zip_name}
# expected: {args.sha256}
```

Built from commit `{args.commit}`.
''')
