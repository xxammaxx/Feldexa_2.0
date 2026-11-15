#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
import hashlib, json, os, subprocess
m = json.load(open('manifest.json', encoding='utf-8'))
failures = []
for item in m['files']:
    path = item['path']
    if not os.path.isfile(path):
        failures.append('missing ' + path)
        continue
    data = open(path, 'rb').read()
    if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
        failures.append('mismatch ' + path)
root = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()
for key in ('apk', 'testApk'):
    item = m[key]
    absolute = os.path.join(root, item['path'])
    if not os.path.isfile(absolute):
        print('ABSENT (build or provide): ' + item['path'])
        continue
    data = open(absolute, 'rb').read()
    ok = len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256']
    print(('OK   ' if ok else 'FAIL ') + item['path'])
    if not ok:
        failures.append('apk ' + item['path'])
if failures:
    print('EVIDENCE VERIFY: FAILED')
    for failure in failures:
        print(' - ' + failure)
    raise SystemExit(1)
print('EVIDENCE VERIFY: OK')
PY
