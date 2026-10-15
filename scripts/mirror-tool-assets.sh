#!/usr/bin/env bash
# Operator-side upstream preparation only; never invoked by the CN installer.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$root" "${1:-/tmp/v029-assets}" "${2:-/tmp/v029-evidence/gitee-assets.txt}" <<'PY'
import hashlib, importlib.util, json, pathlib, shutil, sys
root, output, report = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('programs', root / 'lib/tool-programs.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
output.mkdir(parents=True, exist_ok=True)
cache = output / '.download-cache'; cache.mkdir(exist_ok=True)
lines = ['Operator publication list: upload each verified file to its exact Gitee URL below.', 'Each downloaded upstream artifact is verified against the committed manifest before publication.', '']
for tool in json.loads((root / 'packages/tool-programs/manifest.json').read_text())['tools']:
    if 'asset_name' not in tool or tool.get('cn_skip'):
        continue
    target = output / tool['asset_name']
    if target.exists():
        m.verify(target, tool['integrity'])
    else:
        target.hardlink_to(m.download(tool, cache, 'global'))
    digest = hashlib.file_digest(target.open('rb'), 'sha256').hexdigest()
    if tool.get('cn_parts'):
        assembled = hashlib.sha256()
        with target.open('rb') as original:
            for part in tool['cn_parts']:
                chunk = original.read(part['size'])
                piece = output / part['asset_name']
                if not piece.exists():
                    piece.write_bytes(chunk)
                m.verify(piece, part['integrity'])
                if piece.stat().st_size != part['size']:
                    raise SystemExit('Split asset size mismatch: ' + piece.name)
                assembled.update(piece.read_bytes())
                lines += [hashlib.file_digest(piece.open('rb'), 'sha256').hexdigest() + '  ' + piece.name,
                          '  ' + m.cn_url(part)]
            if original.read(1):
                raise SystemExit('Split asset sizes do not cover original')
        if assembled.hexdigest() != digest:
            raise SystemExit('Split asset reconstruction checksum mismatch')
        lines += ['  Reconstruction (do not upload original): ' + target.name + ' SHA256=' + digest]
    else:
        lines += [digest + '  ' + target.name, '  ' + m.cn_url(tool)]
for manifest in ('aur-assets.json', 'lazyvim-assets.json'):
    for item in json.loads((root / 'packages/desktop-extras' / manifest).read_text()):
        target = output / item['file']
        if not target.is_file():
            raise SystemExit('Prepare desktop source bundles first: missing ' + str(target))
        m.verify(target, item['integrity'])
        lines += [hashlib.file_digest(target.open('rb'), 'sha256').hexdigest() + '  ' + target.name,
                  '  ' + m.cn_url(dict(item, cn_url='https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm/releases/download/tools-v0.2.9/' + target.name))]
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text('\n'.join(lines) + '\n')
print(report.read_text())
PY
