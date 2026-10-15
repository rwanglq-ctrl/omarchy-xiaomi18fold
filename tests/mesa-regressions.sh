#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import hashlib, importlib.util, json, os, pathlib, tempfile, sys
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
    assert m.verify(target)==0
    opt=root/'opt'
    def entries(): return sorted(p.name for p in opt.iterdir())
    # Pad v0.2.6 state: same manifest, cached libLLVM cut short. Reinstall must
    # publish a verified new generation (v0.2.7 refused it forever), switch the
    # link to it and only then drop the damaged copy.
    (current/'lib/libLLVM.so.19.1').write_bytes(b'libLLVM'[:3])
    assert m.verify(target)==10 and m.damaged(target)=='lib/libLLVM.so.19.1'
    m.install(root,libs); repaired=target.resolve()
    assert repaired.name==current.name+'-2' and m.verify(target)==0 and not current.exists()
    assert (target/'lib/libLLVM.so.19.1').read_bytes()==b'libLLVM.so.19.1'
    assert entries()==sorted(['debian-mesa',original.name,repaired.name])
    m.install(root,libs); assert target.resolve()==repaired, 'a good generation is reused'
    current=repaired
    # The EGL vendor file is verified too: EGL is forced to load it.
    for broken in [b'', b'{"ICD": {"library_path": "/elsewhere"}}']:
        (current/'egl/50_debian_mesa.json').write_bytes(broken)
        assert m.verify(target)==10 and m.damaged(target)=='egl/50_debian_mesa.json'
        m.install(root,libs); current=target.resolve(); assert m.verify(target)==0
    (current/'egl/50_debian_mesa.json').unlink(); assert m.verify(target)==10
    m.install(root,libs); current=target.resolve(); assert m.verify(target)==0
    # A managed cache that lost its manifest is damaged, and reinstall repairs it.
    (target/'manifest.json').unlink(); assert m.verify(target)==10
    m.install(root,libs); current=target.resolve(); assert m.verify(target)==0
    # SIGKILL or a VM stop at any step of a repair must leave the link on a
    # whole copy: the damaged old one or the verified new one, never neither.
    for point in ['copy','rename','replace','rmtree']:
        (current/'lib/libLLVM.so.19.1').write_bytes(b'lib')
        pid=os.fork()
        if pid==0:
            def die(*a,**k): os._exit(9)
            if point=='copy': m.copy_durable=die
            if point=='rename':
                real=m.Path.rename
                m.Path.rename=lambda self,dst: die() if self.name.startswith('.debian-mesa-') else real(self,dst)
            if point=='replace': m.os.replace=die
            if point=='rmtree': m.shutil.rmtree=die
            try: m.install(root,libs)
            finally: os._exit(0)
        os.waitpid(pid,0)
        assert target.is_symlink() and target.resolve().is_dir(),(point,entries())
        assert m.verify(target) in (0,10),(point,m.verify(target))
        m.install(root,libs); current=target.resolve(); assert m.verify(target)==0,point
        assert not any(p.name.startswith('.debian-mesa-') for p in opt.iterdir()),(point,entries())
        base=current.name[:len('debian-mesa-')+16]
        assert [p for p in entries() if p.startswith(base)]==[current.name],('damaged generation kept',point,entries())
    # A copy that comes out short is never published; the active prefix stays.
    real_copy=m.shutil.copyfile
    def short_copy(src,dst):
        real_copy(src,dst)
        if pathlib.Path(dst).name=='libLLVM.so.19.1': pathlib.Path(dst).write_bytes(b'lib')
    m.shutil.copyfile=short_copy
    (libs/'libgbm.so.1').write_bytes(b'third package')
    try: m.install(root,libs); raise AssertionError('short copy published')
    except RuntimeError as exc: assert 'differs from its source' in str(exc)
    m.shutil.copyfile=real_copy
    assert target.resolve()==current and not any(p.name.startswith('.debian-mesa') for p in opt.iterdir())
    # Every staged library and both JSON files are flushed before activation.
    synced=[]; real_fsync=m.os.fsync
    m.os.fsync=lambda fd: (synced.append(os.readlink('/proc/self/fd/%d'%fd)), real_fsync(fd))[1]
    (libs/'libgbm.so.1').write_bytes(b'fourth package')
    m.install(root,libs); m.os.fsync=real_fsync
    for name in names: assert any(s.endswith('/lib/'+name) for s in synced),(name,synced)
    assert any(s.endswith('/manifest.json') for s in synced) and any(s.endswith('/50_debian_mesa.json') for s in synced)
    (libs/'libgbm.so.1').write_bytes(b'updated package')
    m.install(root,libs); current=target.resolve(); assert m.verify(target)==0
    assert m.verify(root/'opt/absent')==12
    (libs/'gbm/dri_gbm.so').unlink()
    try: m.install(root,libs); raise AssertionError('missing backend accepted')
    except RuntimeError: pass
    assert target.resolve()==current, 'failed staging changed active prefix'
    target.unlink(); target.mkdir(); (target/'operator-owned').touch()
    m.install(root,libs); assert (target/'operator-owned').exists()
    assert m.verify(target)==11
print('PASS Mesa: hashes, provenance, GBM backend, symlinks, idempotence, atomic update, generation repair (LLVM/vendor/manifest), crash points, short-copy refusal, fsync, verify codes')
PY
