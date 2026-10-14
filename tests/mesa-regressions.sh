#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import hashlib, importlib.util, json, pathlib, tempfile, sys
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('mesa', pathlib.Path(sys.argv[1])/'lib/debian-mesa.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.os.geteuid=lambda: 0
with tempfile.TemporaryDirectory() as tmp:
    w=pathlib.Path(tmp); root=w/'root'; (root/'etc').mkdir(parents=True); (root/'etc/arch-release').touch()
    libs=w/'libs'; (libs/'gbm').mkdir(parents=True)
    names=['libEGL_mesa.so.0','libgbm.so.1','libLLVM.so.19.1','libedit.so.2','libxml2.so.2','libz3.so.4','libgallium-25.0.7.so','gbm/dri_gbm.so']
    for name in names: (libs/name).write_bytes(name.encode())
    # Versioned host symlinks are copied as bytes; never dangling guest links.
    (libs/'libgbm.so.1').rename(libs/'libgbm.so.1.0'); (libs/'libgbm.so.1').symlink_to('libgbm.so.1.0')
    def output(*args):
        if args[0]=='dpkg': return 'arm64\n'
        if args[0]=='ldd': return 'libc.so.6 => /usr/lib/libc.so.6 (0x00)\n'
        if args[1]=='-S': return 'test:arm64: '+args[2]+'\n'
        return 'test:arm64 25.0.7-2+deb13u1 mesa 25.0.7-2+deb13u1\n'
    m.output=output
    m.os.umask(0o077)
    m.install(root,libs); target=root/'opt/debian-mesa'; original=target.resolve()
    assert target.stat().st_mode & 0o777 == 0o755
    assert (target/'lib').stat().st_mode & 0o777 == 0o755
    assert (target/'egl/50_debian_mesa.json').stat().st_mode & 0o777 == 0o644
    assert target.is_symlink() and (target/'lib/gbm/dri_gbm.so').is_file()
    assert not (target/'lib/gbm/dri_gbm.so').is_symlink()
    assert not (target/'lib/libgbm.so.1').is_symlink()
    assert not (target/'lib/libc.so.6').exists()
    for entry in json.loads((target/'manifest.json').read_text()):
        assert hashlib.sha256((target/entry['file']).read_bytes()).hexdigest()==entry['sha256']
    m.install(root,libs); assert target.resolve()==original
    (libs/'libgbm.so.1').write_bytes(b'updated package')
    m.install(root,libs); assert target.resolve()!=original and original.exists()
    current=target.resolve()
    (current/'lib/libgbm.so.1').write_bytes(b'corruption')
    try: m.install(root,libs); raise AssertionError('corrupted cached copy accepted')
    except RuntimeError: pass
    (current/'lib/libgbm.so.1').write_bytes(b'updated package')
    (libs/'gbm/dri_gbm.so').unlink()
    try: m.install(root,libs); raise AssertionError('missing backend accepted')
    except RuntimeError: pass
    assert target.resolve()==current, 'failed staging changed active prefix'
    target.unlink(); target.mkdir(); (target/'operator-owned').touch()
    m.install(root,libs); assert (target/'operator-owned').exists()
print('PASS Mesa: hashes, package provenance, actual GBM backend, symlinks, idempotence, atomic update, failure preservation')
PY
