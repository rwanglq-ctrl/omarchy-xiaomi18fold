#!/usr/bin/env bash
# Offline behavioral checks; never touch the real display service or container.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json, os, pathlib, signal, socket, subprocess, sys, tempfile, time
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='display-regressions-') as work:
    w=pathlib.Path(work); drm=w/'drm'; drm.mkdir(); runtime=w/'runtime'; runtime.mkdir(); home=w/'home'; bins=home/'.local/bin'; bins.mkdir(parents=True)
    (home/'.config').mkdir(); mocks=w/'mocks'; mocks.mkdir()
    env=dict(os.environ, HOME=str(home), PATH=str(mocks)+':'+os.environ['PATH'], TEST_STATE=str(w), TEST_UID=str(os.getuid()), XDG_RUNTIME_DIR=str(runtime))
    def script(name, text):
        p=mocks/name; p.write_text('#!/bin/sh\n'+text); p.chmod(0o755)
    for src in (root/'host/bin').iterdir():
        text=src.read_text().replace('@USER@',os.environ.get('USER','tester')).replace('@UID@',str(os.getuid())).replace('@ROOTFS@',str(w/'rootfs'))
        text=text.replace('/sys/class/drm',str(drm)).replace('/run/user/'+str(os.getuid()),str(runtime)).replace('@VERSION@',(root/'VERSION').read_text().strip())
        p=bins/src.name; p.write_text(text); p.chmod(0o755)
    script('sudo', '[ "$1" != -n ] || shift\n[ "$1" != test ] || exit 0\nexec "$@"\n')
    script('machinectl', '''case "$1" in
show) [ -f "$TEST_STATE/machine" ] || exit 1; case "$*" in *Leader*) if [ -f "$TEST_STATE/leader-unknown" ]; then rm -f "$TEST_STATE/leader-unknown"; exit 1; fi; cat "$TEST_STATE/leader" 2>/dev/null || echo 123;; esac;;
kill|terminate) echo "$*" >> "$TEST_STATE/kills"; [ -f "$TEST_STATE/cleanup-fails" ] || rm -f "$TEST_STATE/machine";;
*) exit 90;; esac
''')
    script('nsenter', '''case "$*" in *"-m -p -r -w --"*) ;; *) exit 91;; esac
while [ "$1" != /bin/sh ]; do shift; done
exec "$@"
''')
    script('stat', 'echo "$TEST_UID"\n')
    script('readlink', '''case "$*" in *999*) echo /usr/bin/stale;; *) echo /usr/bin/Hyprland;; esac
''')
    script('hyprctl', r'''case "$*" in *monitors*) [ "$HYPRLAND_INSTANCE_SIGNATURE" = live ] || exit 92;; esac
case "$*" in
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
    live=runtime/'hypr/live'; live.mkdir(parents=True)
    ipc=socket.socket(socket.AF_UNIX); ipc.bind(str(live/'.socket.sock'))
    (live/'hyprland.lock').write_text('123\nwayland-1\n')
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
    # Discovery can fail/hang while an explicit socket+lock probe succeeds.
    for discovery in ['exit 1', '/bin/sleep 10']:
        script('hyprctl', '''case "$*" in *instances*) '''+discovery+''';; *)
[ "$HYPRLAND_INSTANCE_SIGNATURE" = live ] || exit 92
cat "$TEST_STATE/monitors";; esac
''')
        started=time.monotonic()
        assert subprocess.run([str(bins/'arch-output')],env=env,capture_output=True).returncode==0
        assert time.monotonic()-started<5
    # The outer budget must include discovery and every allowed probe's kill
    # grace: three unresponsive instances must not hide the fourth healthy one.
    blocked_sockets=[]
    for name in ['a','b','c']:
        d=runtime/'hypr'/name; d.mkdir()
        s=socket.socket(socket.AF_UNIX); s.bind(str(d/'.socket.sock')); blocked_sockets.append(s)
        (d/'hyprland.lock').write_text('123\nwayland-1\n')
    script('hyprctl', '''case "$*" in
*instances*) exit 1;;
'-i live -j monitors') cat "$TEST_STATE/monitors";;
*) trap '' TERM; /bin/sleep 10;;
esac
''')
    p=subprocess.run([str(bins/'arch-output')],env=env,capture_output=True,text=True,timeout=15)
    assert p.returncode==0 and json.loads(p.stdout)==good,(p.returncode,p.stderr)
    for name,s in zip(['a','b','c'],blocked_sockets):
        s.close(); d=runtime/'hypr'/name
        (d/'.socket.sock').unlink(); (d/'hyprland.lock').unlink(); d.rmdir()
    ipc.close(); (live/'.socket.sock').unlink()
    (mocks/'hyprctl').write_text(saved_ctl)
    p=subprocess.run([str(bins/'arch-output')],env=env,capture_output=True,text=True)
    assert p.returncode==1 and 'command socket absent' in p.stderr
    # Actual startup wedge: only the event socket exists, with no lock or
    # instances response. Preserve evidence without treating stale dirs as live.
    event_ipc=socket.socket(socket.AF_UNIX); event_ipc.bind(str(live/'.socket2.sock'))
    (live/'hyprland.lock').unlink()
    script('hyprctl', 'echo "[]"\n')
    p=subprocess.run([str(bins/'arch-output')],env=env,capture_output=True,text=True)
    assert p.returncode==1 and 'command_socket=absent event_socket=present lock=absent' in p.stderr,p.stderr
    event_ipc.close(); (live/'.socket2.sock').unlink()
    (live/'hyprland.lock').write_text('123\nwayland-1\n')
    ipc=socket.socket(socket.AF_UNIX); ipc.bind(str(live/'.socket.sock'))
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
    p=subprocess.run([str(bins/'arch-output'),'--logs'],env=env,capture_output=True,text=True,check=True)
    assert 'DRM connector error' in p.stdout,'runtime logs lost after teardown'
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
    assert 'DRM connector error' in diagnostic and 'Window private-title' in diagnostic
    assert 'card0-Virtual-2/status: connected' in diagnostic
    assert 'Hyprland monitors all' in diagnostic and 'Virtual-2' in diagnostic
    (w/'machine').unlink()
    # The private collector preserves earlier console output without a machine.
    (w/'machine').unlink(missing_ok=True)
    prior=home/'.local/state/omarchy-alarm/arch-session-previous.log'
    prior.write_text('start-hyprland Window client early failure\n')
    p=subprocess.run([str(bins/'arch-diag'),'--stdout'],env=env,capture_output=True,text=True,check=True)
    assert 'start-hyprland Window client early failure' in p.stdout
    (w/'machine').touch()
    old_enter=(mocks/'nsenter').read_text()
    for failed in ['nsenter','runuser']:
        script('nsenter', 'echo "'+failed+': injected failure" >&2\nexit 9\n')
        p=subprocess.run([str(bins/'arch-diag'),'--stdout'],env=env,capture_output=True,text=True,check=True)
        assert failed+': injected failure' in p.stdout and 'namespace probe failed' in p.stdout
        assert 'DRM connector error' in p.stdout, 'namespace failure lost surviving runtime logs'
        p=subprocess.run([str(bins/'arch-output'),'--logs'],env=env,capture_output=True,text=True,check=True)
        assert 'retrying surviving host runtime logs' in p.stdout and 'DRM connector error' in p.stdout
    (mocks/'nsenter').write_text(old_enter)
    (w/'machine').unlink()
    # Session/launcher lifecycle cases live in session-regressions.sh, which
    # runs the new shared ownership/cleanup path (including real selftest entry).
    for flag in ['LIBGL_ALWAYS_SOFTWARE','GALLIUM_DRIVER=llvmpipe','AQ_NO_MODIFIERS','AQ_NO_ATOMIC']:
        assert '--setenv='+flag in (root/'host/bin/arch-hyprland').read_text()
    # An explicit build prefix supplies the probe client and its own libraries.
    custom=w/'custom'; (custom/'bin').mkdir(parents=True)
    client=custom/'bin/hyprctl'
    client.write_text('#!/bin/sh\ncase "$LD_LIBRARY_PATH" in "'+str(custom)+'/lib"*) ;; *) exit 97;; esac\necho selected > "$TEST_STATE/prefix-probed"\nexec "$TEST_STATE/mocks/hyprctl" "$@"\n')
    client.chmod(0o755)
    (home/'.config/arch-hyprland-prefix').write_text(str(custom)+'\n')
    (w/'machine').touch(); (w/'monitors').write_text(json.dumps(good))
    p=subprocess.run([str(bins/'arch-output')],env=env,capture_output=True,text=True)
    assert p.returncode==0 and (w/'prefix-probed').exists(),p.stderr
    (w/'machine').unlink(); (home/'.config/arch-hyprland-prefix').unlink()
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
print('PASS display: output readiness, stale sockets, safe switch, private diagnostics, raw logs after teardown, renderer defaults, shell PATH')
PY
