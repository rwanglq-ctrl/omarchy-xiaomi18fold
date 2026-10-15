#!/usr/bin/env python3
"""Stage the Debian 13 host's Mesa ABI alongside Arch; never replace pacman files.

Installed by omarchy-alarm-nspawn as ~/.local/bin/arch-mesa-check for --verify.
"""
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


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


VENDOR = 'egl/50_debian_mesa.json'
VENDOR_ICD = {'file_format_version': '1.0.0',
              'ICD': {'library_path': '/opt/debian-mesa/lib/libEGL_mesa.so.0'}}


def damaged(prefix):
    """Return the first staged file that does not match the manifest, else None.

    A truncated libLLVM (Pad, v0.2.6) still loads, then kills Hyprland with
    SIGBUS before init: no crash report and no flushed log. Hashing every
    staged file takes about 0.3 s on the Pad.
    """
    entries = json.loads((prefix / 'manifest.json').read_text())
    if not isinstance(entries, list) or not entries:
        return 'manifest.json'
    # EGL is pointed at this vendor file, so a lost one must not pass either.
    try:
        vendor = json.loads((prefix / VENDOR).read_text())
    except (OSError, ValueError):
        return VENDOR
    if vendor != VENDOR_ICD:
        return VENDOR
    for entry in entries:
        name = entry['file']
        if not name.startswith('lib/') or '..' in Path(name).parts:
            return name
        path = prefix / name
        if path.is_symlink() or not path.is_file() or sha256(path) != entry['sha256']:
            return name
    return None


def copy_durable(source, destination):
    # The Android Terminal VM can stop before ext4 writeback. Flush each copy
    # before it can be activated, so a stop cannot publish a short file.
    shutil.copyfile(source, destination)
    destination.chmod(0o644)
    with open(destination, 'rb') as stream:
        os.fsync(stream.fileno())


def write_durable(path, text):
    with open(path, 'w') as stream:
        stream.write(text)
        stream.flush()
        os.fsync(stream.fileno())


def cache_matches(prefix, manifest, vendor_json):
    try:
        return ((prefix / 'manifest.json').read_text() == manifest and
                (prefix / 'egl/50_debian_mesa.json').read_text() == vendor_json and
                damaged(prefix) is None)
    except (OSError, ValueError, KeyError, TypeError):
        return False


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


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
                               sha256=sha256(real)))
    manifest = json.dumps(provenance, indent=2) + '\n'
    vendor_json = json.dumps(VENDOR_ICD) + '\n'
    digest = hashlib.sha256((manifest + vendor_json).encode()).hexdigest()[:16]
    base = 'debian-mesa-' + digest
    # Generations of the same content: the plain name, or base-N after a repair.
    generations = [p for p in opt.iterdir() if p.is_dir() and not p.is_symlink() and
                   (p.name == base or (p.name.startswith(base + '-') and p.name[len(base) + 1:].isdigit()))]
    dest = next((p for p in sorted(generations) if cache_matches(p, manifest, vendor_json)), None)
    # Temporaries of an install that was killed or stopped mid-way.
    for leftover in opt.glob('.debian-mesa-*'):
        if leftover.is_dir() and not leftover.is_symlink():
            shutil.rmtree(leftover)
        else:
            leftover.unlink()
    stage = Path(tempfile.mkdtemp(prefix='.debian-mesa-', dir=opt))
    try:
        if dest is None:
            (stage / 'lib/gbm').mkdir(parents=True)
            (stage / 'egl').mkdir()
            for name, path in files.items():
                copy_durable(path, stage / 'lib' / name)
            write_durable(stage / VENDOR, vendor_json)
            write_durable(stage / 'manifest.json', manifest)
            for directory in [stage, stage / 'lib', stage / 'lib/gbm', stage / 'egl']:
                directory.chmod(0o755)
            (stage / VENDOR).chmod(0o644)
            (stage / 'manifest.json').chmod(0o644)
            # Do not publish a copy made while host package files were changing.
            broken = damaged(stage)
            if broken:
                raise RuntimeError('Mesa copy differs from its source: ' + str(stage / broken))
            for directory in [stage / 'lib/gbm', stage / 'lib', stage / 'egl', stage]:
                sync_directory(directory)
            # v0.2.6 activated copies unverified; one on the Pad lost the end of
            # libLLVM. Never reuse or overwrite a damaged generation in place:
            # publish a new one, so the active link always names a whole copy.
            name, generation = base, 1
            while (opt / name).exists() or (opt / name).is_symlink():
                generation += 1
                name = base + '-' + str(generation)
            if generations:
                print('Replacing damaged cached Mesa copy /opt/' + ', /opt/'.join(sorted(p.name for p in generations)))
            dest = opt / name
            stage.rename(dest)
            sync_directory(opt)
            broken = damaged(dest)
            if broken:
                raise RuntimeError('Mesa hash mismatch: ' + str(dest / broken))
        # Atomic activation; an existing compositor can keep its mapped libraries.
        link = stage if not stage.exists() else stage / 'active'
        os.symlink(dest.name, link)
        os.replace(link, target)
        sync_directory(opt)
        # Only now, with the link on a verified copy, drop damaged generations.
        for old in generations:
            if old != dest and not cache_matches(old, manifest, vendor_json):
                shutil.rmtree(old)
        print('Debian Mesa staged at /opt/' + dest.name + '; provenance: /opt/debian-mesa/manifest.json')
    finally:
        if stage.is_dir():
            shutil.rmtree(stage)
        elif stage.is_symlink():
            stage.unlink()


# Exit codes are distinct from Python's own 1/2 so a broken verifier is never
# read as "intact" or "damaged".
INTACT, DAMAGED, OPERATOR_OWNED, ABSENT = 0, 10, 11, 12


def verify(prefix):
    """arch-mesa-check --verify PREFIX: 0 intact, 10 damaged, 11 operator-owned, 12 absent."""
    if not prefix.exists() and not prefix.is_symlink():
        print('absent: ' + str(prefix) + ' (Arch Mesa is used)')
        return ABSENT
    if not prefix.is_symlink() and prefix.is_dir() and not (prefix / 'manifest.json').exists():
        print('unverified: operator-owned ' + str(prefix) + ' has no manifest')
        return OPERATOR_OWNED
    try:
        broken = damaged(prefix)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        broken = 'manifest.json (' + type(exc).__name__ + ')'
    if broken:
        print('damaged: ' + broken)
        return DAMAGED
    print('intact: ' + str(prefix))
    return INTACT


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--verify':
        sys.exit(verify(Path(sys.argv[2])))
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_absolute() or Path(sys.argv[1]) == Path('/'):
        sys.exit('Usage: debian-mesa.py /absolute/arch/rootfs | debian-mesa.py --verify PREFIX')
    try:
        install(Path(sys.argv[1]))
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        sys.exit('Debian Mesa staging failed: ' + str(exc))
