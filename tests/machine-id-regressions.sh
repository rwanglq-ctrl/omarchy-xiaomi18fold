#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import os,pathlib,re,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]); helper=root/'lib/machine-id.sh'
assert (root/'host/bin/arch-machine-id').is_symlink()
assert (root/'host/bin/arch-machine-id').resolve()==helper.resolve()
assert subprocess.run(['bash',str(helper)],capture_output=True).returncode==2
assert subprocess.run(['bash',str(helper),'--check'],capture_output=True).returncode==2
host=pathlib.Path('/etc/machine-id'); before=host.read_bytes()
with tempfile.TemporaryDirectory() as tmp:
    w=pathlib.Path(tmp); (w/'etc').mkdir(); (w/'var/lib/dbus').mkdir(parents=True)
    mid=w/'etc/machine-id'; dbus=w/'var/lib/dbus/machine-id'
    def run(*args):
        return subprocess.run(['bash',str(helper),*args],text=True,capture_output=True)
    for value in [None,b'',b'uninitialized\n',b'a'*31,b'a'*33,b'a'*32+b'\0',b'\n'+b'a'*32,b'A'*32,b'a'*32+b'\n\n',b'a'*31+b' ',b'0'*32]:
        mid.unlink(missing_ok=True); dbus.unlink(missing_ok=True)
        if value is not None: mid.write_bytes(value)
        dbus.symlink_to('/etc/machine-id')
        p=run(str(w)); assert p.returncode==0,p.stderr
        made=mid.read_bytes(); assert re.fullmatch(b'[0-9a-f]{32}\n',made)
        assert mid.stat().st_mode & 0o777 == 0o444
        assert made != before and host.read_bytes()==before
        assert run(str(w)).returncode==0 and mid.read_bytes()==made
    for value in [b'1'*32,b'1'*32+b'\n']:
        mid.unlink(); mid.write_bytes(value)
        assert run(str(w)).returncode==0 and mid.read_bytes()==value
    for bad in ['missing','empty','wrong-link','wrong-value','matching-file']:
        dbus.unlink(missing_ok=True)
        if bad=='empty': dbus.touch()
        if bad=='wrong-link': dbus.symlink_to('/not-a-guest-file')
        if bad=='wrong-value': dbus.write_text('2'*32+'\n')
        if bad=='matching-file': dbus.write_bytes(mid.read_bytes())
        assert run(str(w)).returncode==0
        if bad=='matching-file': assert not dbus.is_symlink()
        else: assert os.readlink(dbus)=='/etc/machine-id'
    p=run('--check',str(w)); assert p.returncode==0 and 'machine-id: valid' in p.stdout
    assert '1'*32 not in p.stdout
    if before.strip(): assert before.decode().strip() not in p.stdout
    mid.unlink(); mid.symlink_to('/etc/machine-id')
    p=run(str(w)); assert p.returncode==0 and not mid.is_symlink()
    assert host.read_bytes()==before,'guest link changed host identity'
    # Refuse linked parent directories before any write outside the rootfs.
    (w/'etc/machine-id').unlink(); (w/'etc').rmdir(); (w/'etc').symlink_to('/etc')
    assert run(str(w)).returncode!=0 and host.read_bytes()==before
    p=run('--check',str(w)); assert p.returncode!=0 and 'linked directory' in p.stderr
print('PASS machine-id: empty/missing/invalid, stable valid IDs, link safety, private checks')
PY
