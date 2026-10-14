#!/usr/bin/env bash
# Offline behavioral checks; never touch the real display service or container.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json, os, pathlib, signal, subprocess, sys, tempfile, time
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='display-regressions-') as work:
    w=pathlib.Path(work); home=w/'home'; bins=home/'.local/bin'; bins.mkdir(parents=True)
    (home/'.config').mkdir(); mocks=w/'mocks'; mocks.mkdir()
    env=dict(os.environ, HOME=str(home), PATH=str(mocks)+':'+os.environ['PATH'], TEST_STATE=str(w), TEST_UID=str(os.getuid()))
    def script(name, text):
        p=mocks/name; p.write_text('#!/bin/sh\n'+text); p.chmod(0o755)
    for src in (root/'host/bin').iterdir():
        text=src.read_text().replace('@USER@',os.environ.get('USER','tester')).replace('@UID@',str(os.getuid())).replace('@ROOTFS@',str(w/'rootfs'))
        p=bins/src.name; p.write_text(text); p.chmod(0o755)
    script('sudo', '[ "$1" != -n ] || shift\n[ "$1" != test ] || exit 0\nexec "$@"\n')
    script('machinectl', '''case "$1" in
show) [ -f "$TEST_STATE/machine" ] || exit 1; case "$*" in *Leader*) cat "$TEST_STATE/leader" 2>/dev/null || echo 123;; esac;;
kill|terminate) echo "$*" >> "$TEST_STATE/kills"; [ -f "$TEST_STATE/cleanup-fails" ] || rm -f "$TEST_STATE/machine";;
*) exit 90;; esac
''')
    script('nsenter', '''while [ "$1" != /bin/sh ]; do shift; done
exec "$@"
''')
    script('stat', 'echo "$TEST_UID"\n')
    script('readlink', '''case "$*" in *999*) echo /usr/bin/stale;; *) echo /usr/bin/Hyprland;; esac
''')
    script('hyprctl', r'''case "$*" in
*-j\ instances*) echo '[{"pid":null,"instance":"bad"},{"pid":"bad","instance":"bad"},{"pid":123,"instance":"../../bad"},{"pid":999,"instance":"stale"},{"pid":123,"instance":"live"}]';;
*-i\ live\ -j\ monitors*) cat "$TEST_STATE/monitors";;
*) echo "$*" >> "$TEST_STATE/bad-probes"; exit 1;; esac
''')
    good=[dict(name='Virtual-1',width=1920,height=1080,dpmsStatus=True,disabled=False)]
    (w/'machine').touch()
    for value, expected in [(good,0),([],1),([dict(good[0],dpmsStatus=False)],1),([dict(good[0],width=0)],1),([dict(good[0],disabled=True)],1),([dict(good[0],name='HEADLESS-1')],1),([dict(good[0],fallback=True)],1),([dict(good[0],width='bad')],1),(None,1),('invalid',1)]:
        (w/'monitors').write_text('invalid' if value=='invalid' else json.dumps(value))
        p=subprocess.run([str(bins/'arch-output')],env=env,capture_output=True)
        assert p.returncode==expected,(value,p.returncode,p.stderr)
    (w/'monitors').write_text(json.dumps([dict(good[0],dpmsStatus=False,activeWorkspace={'name':'private-title'})]))
    p=subprocess.run([str(bins/'arch-output'),'--summary'],env=env,capture_output=True,text=True,check=True)
    assert 'private-title' not in p.stdout and json.loads(p.stdout)[0]['dpmsStatus'] is False
    assert not (w/'bad-probes').exists(),'stale instance queried'
    (w/'monitors').write_text(json.dumps(good))
    assert subprocess.run([str(bins/'arch-output'),'--exclude-leader','123'],env=env,capture_output=True).returncode==1
    assert subprocess.run([str(bins/'arch-output'),'--exclude-leader','456'],env=env,capture_output=True).returncode==0
    assert subprocess.run([str(bins/'arch-output'),'--exclude-leader',''],env=env,capture_output=True).returncode==0
    assert subprocess.run([str(bins/'arch-output'),'--exclude-leader','bad'],env=env,capture_output=True).returncode==2
    saved_ctl=(mocks/'hyprctl').read_text()
    script('hyprctl', '/bin/sleep 10\n')
    started=time.monotonic()
    assert subprocess.run([str(bins/'arch-output')],env=env,capture_output=True).returncode!=0
    assert time.monotonic()-started<6,'unbounded IPC probe'
    (mocks/'hyprctl').write_text(saved_ctl)
    (w/'machine').unlink()
    assert subprocess.run([str(bins/'arch-output')],env=env,capture_output=True).returncode!=0
    # --now must persist selection but must never invoke a restart, even without
    # WAYLAND_DISPLAY or DISPLAY (the Android shell does not reliably expose them).
    script('systemctl', '''echo "$*" >> "$TEST_STATE/systemctl"
case "$*" in *restart*|*stop*) exit 90;; esac
''')
    for mode in ['arch','debian']:
        subprocess.run([str(bins/'hypr-switch'),mode,'--now'],env=env,check=True,capture_output=True)
        assert (home/'.config/hypr-session-mode').read_text().strip()==mode
    assert not (w/'systemctl').exists(),'switch restarted service'
    for args in [('arch','--oops'),('arch','--now','extra'),('oops',)]:
        assert subprocess.run([str(bins/'hypr-switch'),*args],env=env,capture_output=True).returncode==2
    # Real diagnostic collector: private output, no service mutation, tolerates
    # missing desktop and commands that fail.
    script('journalctl', 'echo display-journal\n')
    p=subprocess.run([str(bins/'arch-diag')],env=env,check=True,capture_output=True,text=True)
    logs=list((home/'.local/state/omarchy-alarm').glob('arch-diag-*.log'))
    assert len(logs)==1 and logs[0].stat().st_mode&0o777==0o600
    assert 'No usable Virtual-1' in logs[0].read_text()
    assert 'restart' not in (w/'systemctl').read_text()
    # Speed only the polling clock; real timeout still bounds any stuck command.
    script('date', '''n=$(cat "$TEST_STATE/clock" 2>/dev/null || echo 0)
n=$((n+6)); echo "$n" > "$TEST_STATE/clock"; echo "$n"
''')
    script('sleep', '/bin/sleep 0.02\n')
    script('weston-test', 'echo weston > "$TEST_STATE/weston"\n')
    real_output=(bins/'arch-output').read_text()
    session=bins/'hypr-session'; session.write_text(session.read_text().replace('/usr/bin/weston',str(mocks/'weston-test')))
    (bins/'arch-diag').write_text('#!/bin/sh\necho diagnostic > "$TEST_STATE/diag"\n')
    def run_session(launcher, probe, stop=False, old=False, replace=True, real_probe=False):
        for name in ['machine','clock','weston','kills','diag','ready','leader']:
            (w/name).unlink(missing_ok=True)
        (home/'.config/hypr-session-mode').write_text('arch\n')
        leader_change='printf 456 > "$TEST_STATE/leader"\n' if replace else ''
        (bins/'arch-hyprland').write_text('#!/bin/sh\n'+leader_change+'touch "$TEST_STATE/machine"\n'+launcher)
        (bins/'arch-output').write_text(real_output if real_probe else '#!/bin/sh\n[ "$1" = --exclude-leader ] && [ "$#" = 2 ] || exit 90\n'+probe)
        if old:
            (w/'machine').touch()
            (w/'leader').write_text('123')
        p=subprocess.Popen([str(session)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if stop:
            deadline=time.monotonic()+10
            while not (w/'ready').exists() and time.monotonic()<deadline:
                time.sleep(.02)
            assert (w/'ready').exists(),'session did not reach readiness'
            p.send_signal(signal.SIGTERM)
        out,err=p.communicate(timeout=20)
        return p.returncode,err
    rc,err=run_session('trap "exit 0" TERM\n/bin/sleep 2\n','exit 1\n')
    assert rc==0 and (w/'weston').exists() and (w/'diag').exists(),err
    assert 'SIGTERM' in (w/'kills').read_text()
    rc,err=run_session('exit 1\n','exit 1\n')
    assert rc==0 and (w/'weston').exists(),err
    rc,err=run_session('while [ ! -f "$TEST_STATE/ready" ]; do /bin/sleep .05; done\n/bin/sleep .3\nexit 0\n','touch "$TEST_STATE/ready"\nexit 0\n')
    assert rc==0 and not (w/'weston').exists(),err
    rc,err=run_session('while [ ! -f "$TEST_STATE/ready" ]; do /bin/sleep .05; done\n/bin/sleep .3\nexit 7\n','touch "$TEST_STATE/ready"\nexit 0\n')
    assert rc==7 and not (w/'weston').exists(),err
    rc,err=run_session('/bin/sleep 1\nexit 0\n','printf \'%s\' "$2" > "$TEST_STATE/excluded-used"\nexit 0\n',old=True)
    assert rc==0 and (w/'excluded-used').read_text()=='123' and not (w/'weston').exists(),err
    assert (w/'leader').read_text()=='456','launcher did not change leader'
    (w/'monitors').write_text(json.dumps(good))
    rc,err=run_session('/bin/sleep 2\n','',old=True,replace=False,real_probe=True)
    assert rc==0 and (w/'weston').exists(),'old healthy container satisfied startup gate: '+repr(err)
    # Signal while waiting on an established compositor must not start recovery.
    rc,err=run_session('trap "exit 0" TERM\n/bin/sleep 2\n','touch "$TEST_STATE/ready"\nexit 0\n',stop=True)
    assert rc==143 and not (w/'weston').exists(),err
    (w/'cleanup-fails').touch()
    rc,err=run_session('exit 1\n','exit 1\n')
    assert rc==1 and not (w/'weston').exists(),err
    (w/'cleanup-fails').unlink()
    (w/'machine').unlink(missing_ok=True)
    # Capture real launcher arguments with a harmless nspawn replacement.
    script('systemd-nspawn', 'printf \'%s\\n\' "$@" > "$TEST_STATE/nspawn-args"\n')
    script('sudo', '[ "$1" != -n ] || shift\n[ "$1" != test ] || exit 1\nexec env "$@"\n')
    (bins/'arch-hyprland').write_text((root/'host/bin/arch-hyprland').read_text().replace('@HOME_BIND_DIRS@','').replace('@ROOTFS@',str(w/'rootfs')))
    subprocess.run([str(bins/'arch-hyprland')],env=env,check=True,capture_output=True)
    args=(w/'nspawn-args').read_text()
    for arg in ['--setenv=LIBGL_ALWAYS_SOFTWARE=1','--setenv=GALLIUM_DRIVER=llvmpipe','--setenv=AQ_NO_MODIFIERS=1','--setenv=AQ_NO_ATOMIC=0']:
        assert arg in args,arg
    for knob in ['arch-hardware-rendering','arch-enable-modifiers','arch-no-atomic']:
        (home/'.config'/knob).touch()
    subprocess.run([str(bins/'arch-hyprland')],env=env,check=True,capture_output=True)
    args=(w/'nspawn-args').read_text()
    for arg in ['--setenv=LIBGL_ALWAYS_SOFTWARE=0','--setenv=AQ_NO_MODIFIERS=0','--setenv=AQ_NO_ATOMIC=1']:
        assert arg in args,arg
    assert '--setenv=GALLIUM_DRIVER' not in args
    # Environment knobs are passed by nspawn, not late Lua env setters.
    launcher=(root/'host/bin/arch-hyprland').read_text()
    for flag in ['LIBGL_ALWAYS_SOFTWARE','GALLIUM_DRIVER=llvmpipe','AQ_NO_MODIFIERS','AQ_NO_ATOMIC']:
        assert '--setenv='+flag in launcher
    # Execute the actual generated PATH block with a typical early-return bashrc.
    installer=(root/'host/install.sh').read_text()
    block=installer.split("cat <<'PATHBLOCK'\n",1)[1].split('\nPATHBLOCK',1)[0]
    rc=w/'bashrc'; rc.write_text(block+'\nreturn\n')
    p=subprocess.run(['bash','--noprofile','--rcfile',str(rc),'-ic','case ":$PATH:" in *":$HOME/.local/bin:"*) exit 0;; *) exit 1;; esac'],env=dict(env,PATH='/usr/bin'),capture_output=True)
    assert p.returncode==0,p.stderr
print('PASS display: output readiness, stale sockets, safe switch, private diagnostics, startup recovery, signals, renderer knobs, shell PATH')
PY
