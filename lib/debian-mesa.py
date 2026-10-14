#!/usr/bin/env python3
"""Stage the Debian 13 host's Mesa ABI alongside Arch; never replace pacman files."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def output(*args):
    return subprocess.check_output(args, text=True, env=dict(os.environ, LC_ALL='C'))


def install(root, lib=Path('/usr/lib/aarch64-linux-gnu')):
    if os.geteuid() != 0:
        raise RuntimeError('run through sudo on the Debian host')
    if output('dpkg', '--print-architecture').strip() != 'arm64':
        raise RuntimeError('Debian Mesa staging requires an arm64 host')
    if not (root / 'etc/arch-release').exists():
        raise RuntimeError('destination is not an existing Arch rootfs')
    opt = root / 'opt'
    opt.mkdir(exist_ok=True)
    target = opt / 'debian-mesa'
    if target.exists() and not target.is_symlink():
        print('Preserving existing /opt/debian-mesa directory; move it aside to provision a managed copy.')
        return
    # The working Pad reference uses these Mesa/LLVM compatibility libraries.
    names = ['libEGL_mesa.so.0', 'libgbm.so.1', 'libLLVM.so.19.1',
             'libedit.so.2', 'libxml2.so.2', 'libz3.so.4']
    seeds = [lib / name for name in names] + list(lib.glob('libgallium-*.so'))
    if not list(lib.glob('libgallium-*.so')) or not all(p.is_file() for p in seeds):
        raise RuntimeError('Debian 13 Mesa/LLVM libraries missing; install host apt dependencies first')
    files = {p.name: p for p in seeds}
    backend = lib / 'gbm/dri_gbm.so'
    if not backend.is_file():
        raise RuntimeError('Debian GBM backend missing')
    files['gbm/dri_gbm.so'] = backend
    # Match the seven-library reference instead of copying Debian's libc,
    # libstdc++, libdrm or Wayland over newer Arch ABI providers.
    for seed in files.values():
        deps = output('ldd', str(seed))
        if 'not found' in deps:
            raise RuntimeError('unresolved host dependency: ' + deps)
    provenance = []
    for name, path in sorted(files.items()):
        real = path.resolve(strict=True)
        package = output('dpkg-query', '-S', str(real)).split(': ', 1)[0]
        version = output('dpkg-query', '-W', '-f=${binary:Package} ${Version} ${source:Package} ${source:Version}\n', package).strip()
        provenance.append(dict(file='lib/' + name, source=str(real), package=version,
                               sha256=hashlib.sha256(real.read_bytes()).hexdigest()))
    manifest = json.dumps(provenance, indent=2) + '\n'
    vendor_json = json.dumps({'file_format_version': '1.0.0',
                              'ICD': {'library_path': '/opt/debian-mesa/lib/libEGL_mesa.so.0'}}) + '\n'
    digest = hashlib.sha256((manifest + vendor_json).encode()).hexdigest()[:16]
    dest = opt / ('debian-mesa-' + digest)
    stage = Path(tempfile.mkdtemp(prefix='.debian-mesa-', dir=opt))
    try:
        (stage / 'lib/gbm').mkdir(parents=True)
        (stage / 'egl').mkdir()
        for name, path in files.items():
            shutil.copyfile(path, stage / 'lib' / name)
            (stage / 'lib' / name).chmod(0o644)
        (stage / 'egl/50_debian_mesa.json').write_text(vendor_json)
        (stage / 'manifest.json').write_text(manifest)
        for directory in [stage, stage / 'lib', stage / 'lib/gbm', stage / 'egl']:
            directory.chmod(0o755)
        (stage / 'egl/50_debian_mesa.json').chmod(0o644)
        (stage / 'manifest.json').chmod(0o644)
        if not dest.exists():
            stage.rename(dest)
        # Do not reactivate a damaged cached copy or publish a copy made while
        # host package files were changing underneath us.
        if (dest / 'manifest.json').read_text() != manifest or (dest / 'egl/50_debian_mesa.json').read_text() != vendor_json:
            raise RuntimeError('cached Mesa manifest differs: ' + str(dest))
        for entry in provenance:
            installed = dest / entry['file']
            if installed.is_symlink() or hashlib.sha256(installed.read_bytes()).hexdigest() != entry['sha256']:
                raise RuntimeError('Mesa hash mismatch: ' + str(installed))
        # Atomic activation; an existing compositor can keep its mapped libraries.
        link = stage if not stage.exists() else stage / 'active'
        os.symlink(dest.name, link)
        os.replace(link, target)
        print('Debian Mesa staged at /opt/' + dest.name + '; provenance: /opt/debian-mesa/manifest.json')
    finally:
        if stage.is_dir():
            shutil.rmtree(stage)
        elif stage.is_symlink():
            stage.unlink()


if __name__ == '__main__':
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_absolute() or Path(sys.argv[1]) == Path('/'):
        sys.exit('Usage: debian-mesa.py /absolute/arch/rootfs')
    try:
        install(Path(sys.argv[1]))
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        sys.exit('Debian Mesa staging failed: ' + str(exc))
