#!/usr/bin/env bash
# Offline behavioral checks; never touch the real display service or container.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json, os, pathlib, signal, subprocess, sys, tempfile, time
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='display-regressions-') as work:
    w=pathlib.Path(work); drm=w/'drm'; drm.mkdir(); runtime=w/'runtime'; runtime.mkdir(); home=w/'home'; bins=home/'.local/bin'; bins.mkdir(parents=True)
    (home/'.config').mkdir(); mocks=w/'mocks'; mocks.mkdir()
    env=dict(os.environ, HOME=str(home), PATH=str(mocks)+':'+os.environ['PATH'], TEST_STATE=str(w), TEST_UID=str(os.getuid()), XDG_RUNTIME_DIR=str(runtime))
    def script(name, text):
        p=mocks/name; p.write_text('#!/bin/sh\n'+text); p.chmod(0o755)
    for src in (root/'host/bin').iterdir():
        text=src.read_text().replace('@USER@',os.environ.get('USER','tester')).replace('@UID@',str(os.getuid())).replace('@ROOTFS@',str(w/'rootfs'))
        text=text.replace('/sys/class/drm',str(drm)).replace('XDG_RUNTIME_DIR=/run/user/'+str(os.getuid()),'XDG_RUNTIME_DIR='+str(runtime))
        p=bins/src.name; p.write_text(text); p.chmod(0o755)
    script('sudo', '[ "$1" != -n ] || shift\n[ "$1" != test ] || exit 0\nexec "$@"\n')
    script('machinectl', '''case "$1" in
show) [ -f "$TEST_STATE/machine" ] || exit 1; case "$*" in *Leader*) if [ -f "$TEST_STATE/leader-unknown" ]; then rm -f "$TEST_STATE/leader-unknown"; exit 1; fi; cat "$TEST_STATE/leader" 2>/dev/null || echo 123;; esac;;
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
*-i\ live\ -j\ monitors\ all) echo all >> "$TEST_STATE/all-probes"; cat "$TEST_STATE/monitors";;
*-i\ live\ -j\ monitors) cat "$TEST_STATE/monitors";;
*) echo "$*" >> "$TEST_STATE/bad-probes"; exit 1;; esac
''')
    for name, status in [('Virtual-1','disconnected'),('Virtual-2','connected'),('Virtual-16','disconnected')]:
        d=drm/('card0-'+name); d.mkdir(); (d/'status').write_text(status+'\n')
    p=subprocess.run([str(bins/'arch-output'),'--connected'],env=env,capture_output=True,text=True,check=True)
    assert p.stdout.strip()=='Virtual-2',p.stdout
    good=[dict(name='Virtual-2',width=1920,height=1080,dpmsStatus=True,disabled=False)]
    (w/'machine').touch()
    for value, expected in [(good,0),([dict(good[0],name='Virtual-16')],0),([dict(good[0],name='eDP-1')],0),([dict(good[0],name='Virtual-1')],0),([],1),([dict(good[0],dpmsStatus=False)],1),([dict(good[0],width=0)],1),([dict(good[0],height=0)],1),([dict(good[0],name='FALLBACK')],1),([dict(good[0],name='headless-2')],1),([dict(good[0],name='')],1),([{k:v for k,v in good[0].items() if k!='dpmsStatus'}],1),([dict(good[0],disabled=True)],1),([dict(good[0],name='HEADLESS-1')],1),([dict(good[0],fallback=True)],1),([dict(good[0],width='bad')],1),(None,1),('invalid',1)]:
        (w/'monitors').write_text('invalid' if value=='invalid' else json.dumps(value))
        p=subprocess.run([str(bins/'arch-output')],env=env,capture_output=True)
        assert p.returncode==expected,(value,p.returncode,p.stderr)
    (w/'monitors').write_text(json.dumps([dict(good[0],dpmsStatus=False,activeWorkspace={'name':'private-title'})]))
    p=subprocess.run([str(bins/'arch-output'),'--summary'],env=env,capture_output=True,text=True,check=True)
    assert 'private-title' not in p.stdout and json.loads(p.stdout)[0]['dpmsStatus'] is False
    p=subprocess.run([str(bins/'arch-output'),'--all'],env=env,capture_output=True,text=True,check=True)
    assert json.loads(p.stdout)[0]['activeWorkspace']['name']=='private-title'
    assert (w/'all-probes').read_text().splitlines()==['all','all']
    (w/'monitors').write_text(json.dumps([dict(good[0],name='FALLBACK',fallback=True)]))
    assert subprocess.run([str(bins/'arch-output'),'--summary'],env=env,capture_output=True).returncode==0
    assert subprocess.run([str(bins/'arch-output')],env=env,capture_output=True).returncode==1
    report=[dict(good[0],name='Virtual-1'),good[0]]
    (w/'monitors').write_text(json.dumps(report))
    p=subprocess.run([str(bins/'arch-output')],env=env,capture_output=True,text=True,check=True)
    assert json.loads(p.stdout)[0]['name']=='Virtual-2'
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
    logdir=runtime/'hypr'/'crashed'; logdir.mkdir(parents=True)
    (logdir/'hyprland.log').write_text('DRM connector error\nWindow private-title\n')
    script('hyprctl', 'exit 1\n')
    p=subprocess.run([str(bins/'arch-output'),'--logs'],env=env,capture_output=True,text=True,check=True)
    assert 'DRM connector error' in p.stdout,'logs lost when IPC failed'
    for i in range(6):
        d=runtime/'hypr'/('old_'+str(i)); d.mkdir()
        f=d/'hyprland.log'; f.write_text('old-'+str(i)+'\n'); os.utime(f,(100+i,100+i))
    p=subprocess.run([str(bins/'arch-output'),'--logs'],env=env,capture_output=True,text=True,check=True)
    assert 'DRM connector error' in p.stdout and 'old-5' in p.stdout and 'old-0' not in p.stdout
    assert p.stdout.count('--- ')==4,'log count is not bounded'

    (mocks/'hyprctl').write_text(saved_ctl)
    (w/'machine').unlink()
    assert subprocess.run([str(bins/'arch-output')],env=env,capture_output=True).returncode!=0
    assert subprocess.run([str(bins/'arch-output'),'--connected'],env=env,capture_output=True).returncode==0
    (drm/'card0-Virtual-2/status').write_text('disconnected\n')
    assert subprocess.run([str(bins/'arch-output'),'--connected'],env=env,capture_output=True).returncode==1
    (drm/'card0-Virtual-16/status').write_text('connected\n')
    p=subprocess.run([str(bins/'arch-output'),'--connected'],env=env,capture_output=True,text=True,check=True)
    assert p.stdout.strip()=='Virtual-16'
    (drm/'card0-Virtual-2/status').write_text('connected\n')
    (drm/'card0-Virtual-16/status').write_text('disconnected\n')
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
    assert 'No monitor report' in logs[0].read_text()
    assert 'restart' not in (w/'systemctl').read_text()
    (w/'machine').touch()
    p=subprocess.run([str(bins/'arch-diag')],env=env,check=True,capture_output=True,text=True)
    diagnostic=max((home/'.local/state/omarchy-alarm').glob('arch-diag-*.log'),key=lambda p:p.stat().st_mtime_ns).read_text()
    assert 'DRM connector error' in diagnostic and 'Window private-title' not in diagnostic
    assert 'card0-Virtual-2/status: connected' in diagnostic
    assert 'Hyprland monitors all' in diagnostic and 'Virtual-2' in diagnostic
    (w/'machine').unlink()
    # Speed only the polling clock; real timeout still bounds any stuck command.
    script('date', '''n=$(cat "$TEST_STATE/clock" 2>/dev/null || echo 0)
n=$((n+6)); echo "$n" > "$TEST_STATE/clock"; echo "$n"
''')
    script('sleep', '/bin/sleep 0.02\n')
    script('weston-test', 'echo weston > "$TEST_STATE/weston"\n')
    real_output=(bins/'arch-output').read_text()
    session=bins/'hypr-session'; session.write_text(session.read_text().replace('/usr/bin/weston',str(mocks/'weston-test')))
    (bins/'arch-diag').write_text('#!/bin/sh\n[ -f "$TEST_STATE/machine" ] && echo before-cleanup > "$TEST_STATE/diag-order"\necho diagnostic > "$TEST_STATE/diag"\n')
    def run_session(launcher, probe, stop=False, old=False, replace=True, real_probe=False, leader_failure=False):
        for name in ['machine','clock','weston','kills','diag','diag-order','ready','leader','leader-unknown']:
            (w/name).unlink(missing_ok=True)
        (home/'.config/hypr-session-mode').write_text('arch\n')
        leader_change='printf 456 > "$TEST_STATE/leader"\n' if replace else ''
        (bins/'arch-hyprland').write_text('#!/bin/sh\n'+leader_change+'touch "$TEST_STATE/machine"\n'+launcher)
        (bins/'arch-output').write_text(real_output if real_probe else '#!/bin/sh\n[ "$1" = --exclude-leader ] && [ "$#" = 2 ] || exit 90\n'+probe)
        if old:
            (w/'machine').touch()
            (w/'leader').write_text('123')
        if leader_failure:
            (w/'leader-unknown').touch()
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
    assert (w/'diag-order').read_text().strip()=='before-cleanup'
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
    rc,err=run_session('/bin/sleep 1\nexit 0\n','',real_probe=True)
    assert rc==0 and not (w/'weston').exists(),'Virtual-2 gate failed: '+repr(err)
    rc,err=run_session('/bin/sleep 2\n','',old=True,replace=False,real_probe=True,leader_failure=True)
    assert rc==0 and (w/'weston').exists() and b'unknown previous leader' in err,err
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
    (home/'.profile').write_text(block+'\n')
    p=subprocess.run(['bash','--noprofile','-c','. "$HOME/.profile"; command -v arch-output'],env=dict(env,PATH='/usr/bin'),capture_output=True,text=True)
    assert p.returncode==0 and str(bins/'arch-output') in p.stdout,p.stderr
    monitors=(root/'config/hypr/monitors.lua').read_text()
    assert 'output = "Virtual-' not in monitors and 'output = ""' in monitors
    assert 'no_hardware_cursors = true' in monitors
    assert 'hypr-switch arch --now' not in (root/'install.sh').read_text()
print('PASS display: output readiness, stale sockets, safe switch, private diagnostics, startup recovery, signals, renderer knobs, shell PATH')
PY
