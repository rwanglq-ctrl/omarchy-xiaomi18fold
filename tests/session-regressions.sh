#!/usr/bin/env bash
# Real rendered lifecycle scripts, isolated filesystem and command mocks; no host seat.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json,os,pathlib,signal,socket,subprocess,sys,tempfile,time
root=pathlib.Path(sys.argv[1]); uid=str(os.getuid())
emulated=os.environ.get('ALARM_TEST_EMULATED')=='1'
gate_seconds=8 if emulated else 2
with tempfile.TemporaryDirectory(prefix='session-regressions-') as tmp:
    w=pathlib.Path(tmp); home=w/'home'; bins=home/'.local/bin'; bins.mkdir(parents=True)
    runtime=w/'runtime'; runtime.mkdir(); mocks=w/'mocks'; mocks.mkdir()
    (home/'.config').mkdir(); (home/'.config/hypr-session-mode').write_text('arch\n')
    fs=w/'rootfs'; (fs/'usr/bin').mkdir(parents=True); (fs/'etc').mkdir()
    (fs/'usr/bin/start-hyprland').write_text('#!/bin/sh\nexit 0\n'); (fs/'usr/bin/start-hyprland').chmod(0o755)
    drm=w/'drm'; drm.mkdir()
    for connector in ['Virtual-1','Virtual-2']:
        d=drm/('card0-'+connector); d.mkdir(); (d/'status').write_text('disconnected\n')
    live=runtime/'hypr/live'; live.mkdir(parents=True)
    ipc=socket.socket(socket.AF_UNIX); ipc.bind(str(live/'.socket.sock'))
    (live/'hyprland.lock').write_text('123\nwayland-1\n')
    for name in ['dri','input','udev']: (w/name).mkdir()
    (w/'udmabuf').touch(); seat=socket.socket(socket.AF_UNIX); seat.bind(str(w/'seatd.sock'))
    env=dict(os.environ,HOME=str(home),PATH=str(mocks)+':'+os.environ['PATH'],TEST_STATE=str(w),XDG_RUNTIME_DIR=str(runtime))
    env.pop('INVOCATION_ID',None); env.pop('OMARCHY_SESSION_INTERNAL',None)
    def script(name,body):
        p=mocks/name;p.write_text('#!/bin/bash\n'+body);p.chmod(0o755)
    for src in (root/'host/bin').iterdir():
        s=src.read_text()
        for key,value in {'@USER@':os.environ.get('USER','tester'),'@UID@':uid,'@ROOTFS@':str(fs),'@HOME@':str(home),'@CHOME@':'/home/tester','@HOME_BIND_DIRS@':'','@VERSION@':(root/'VERSION').read_text().strip()}.items(): s=s.replace(key,value)
        for key,value in {'/run/user/'+uid:str(runtime),'/sys/class/drm':str(drm),'/dev/dri':str(w/'dri'),'/dev/udmabuf':str(w/'udmabuf'),'/dev/input':str(w/'input'),'/run/udev':str(w/'udev'),'/run/seatd.sock':str(w/'seatd.sock')}.items(): s=s.replace(key,value)
        # Accelerate only harness deadlines, not the production decision logic.
        s=s.replace('$(monotonic_seconds) + 30','$(monotonic_seconds) + '+str(gate_seconds)).replace('$(monotonic_seconds) + 3','$(monotonic_seconds) + 2').replace('$(monotonic_seconds) + 15','$(monotonic_seconds) + '+str(gate_seconds))
        p=bins/src.name;p.write_text(s);p.chmod(0o755)
    script('sudo','[ "$1" != -n ] || shift\n[ ! -f "$TEST_STATE/sudo-fails" ] || exit 1\nexec env "$@"\n')
    script('date','[ ! -f "$TEST_STATE/wall-clock-jump" ] || [ "$1" != +%s ] || { echo 0; exit; }\nexec /bin/date "$@"\n')
    script('sleep','exec /bin/sleep .04\n')
    script('systemctl', r'''echo "$*" >> "$TEST_STATE/systemctl"
case "$*" in
*'stop weston.socket'*) rm -f "$TEST_STATE/socket-active";;
*'stop weston.service'*)
 if [ -f "$TEST_STATE/socket-active" ]; then touch "$TEST_STATE/display-active"; else rm -f "$TEST_STATE/display-active"; fi;;
*'restart weston.socket'*) touch "$TEST_STATE/socket-active";;
*'restart weston.service'*) touch "$TEST_STATE/display-active";;
*reset-failed*) exit 0;;
*is-active*) [ ! -f "$TEST_STATE/display-active" ] || { echo active; exit 0; }; echo inactive; exit 3;;
esac
''')
    script('fuser','if [[ $1 != -s ]]; then echo "$TEST_OWNER_PID"; exit; fi\n[ -f "$TEST_STATE/seat-busy" ]\n')
    env['TEST_OWNER_PID']=str(os.getpid())
    script('machinectl',r'''
case "$1" in
list) if [ -f "$TEST_STATE/registry-transient" ]; then
 n=$(cat "$TEST_STATE/registry-transient"); echo $((n+1)) > "$TEST_STATE/registry-transient"; (( n >= 2 )) || exit 1
 fi
 [ ! -f "$TEST_STATE/registry-fails" ] || exit 1; [ ! -f "$TEST_STATE/machine" ] || echo 'arch-desktop container root'; exit 0;;
show) [ -f "$TEST_STATE/machine" ] || exit 1; case "$*" in *Leader*) [ ! -f "$TEST_STATE/unknown-leader" ] || exit 1; cat "$TEST_STATE/machine";; esac;;
kill|terminate)
 echo "$*" >> "$TEST_STATE/kills"
 [ -f "$TEST_STATE/machine" ] || exit 0
 [ ! -f "$TEST_STATE/cleanup-fails" ] || exit 0
 pid=$(cat "$TEST_STATE/machine")
 case "$*" in
 *SIGKILL*) kill -KILL "$pid" 2>/dev/null || :; rm -f "$TEST_STATE/machine";;
 *SIGTERM*) kill -TERM "$pid" 2>/dev/null || :;;
 *terminate*) rm -f "$TEST_STATE/machine";;
 esac;;
esac
''')
    script('systemd-nspawn',r'''
[ ! -e /proc/$$/fd/8 ] || exit 98
printf '%s\n' "$@" > "$TEST_STATE/nspawn-args"
echo 'Window client launch stderr evidence' >&2
[ ! -f "$TEST_STATE/registration-fails" ] || exit 17
echo $$ > "$TEST_STATE/machine"
# Keep failed-cleanup registration even when the owner terminates its child.
# Model stale machined state without leaking a process that holds test pipes.
trap '[ -f "$TEST_STATE/cleanup-fails" ] || rm -f "$TEST_STATE/machine"; exit 0' TERM
[ ! -f "$TEST_STATE/needs-kill" ] || trap '' TERM
echo 'stage=container-entry'; echo 'stage=start-hyprland'
[ ! -f "$TEST_STATE/early-exit" ] || exit 7
[ -f "$TEST_STATE/no-output" ] || touch "$TEST_STATE/ready"
if [ -f "$TEST_STATE/normal-exit" ]; then
 while [ ! -f "$TEST_STATE/probed" ]; do /bin/sleep .1; done
 /bin/sleep .3; exit 7
fi
while :; do /bin/sleep .1; done
''')
    # Run the REAL arch-output through the REAL gate; mock only external tools.
    script('nsenter', r'''if [ -f "$TEST_STATE/watchdog-restart" ]; then
 if [ ! -f "$TEST_STATE/watchdog-gap" ]; then
   mv "$TEST_STATE/runtime/hypr/live" "$TEST_STATE/restarting"
   touch "$TEST_STATE/watchdog-gap"
 elif [ -d "$TEST_STATE/restarting" ]; then
   mv "$TEST_STATE/restarting" "$TEST_STATE/runtime/hypr/live"
 fi
fi
printf '%s\n' "$*" >> "$TEST_STATE/nsenter-args"
case "$*" in *"-m -p -r -w --"*) ;; *) exit 91;; esac
while [ "$1" != /bin/sh ]; do shift; done
exec "$@"
''')
    script('stat', '[ "$1" != -c ] || [ "$2" != %u ] || { id -u; exit; }; exec /usr/bin/stat "$@"\n')
    script('readlink', 'echo /usr/bin/Hyprland\n')
    script('hyprctl', r'''echo "$*" >> "$TEST_STATE/hyprctl-args"
case "$*" in
'-j instances') echo '[{"pid":123,"instance":"live"}]';;
'-i live -j monitors'*)
 [ "$HYPRLAND_INSTANCE_SIGNATURE" = live ] || exit 92
 [ -f "$TEST_STATE/machine" ] && [ -f "$TEST_STATE/ready" ] || exit 1
 touch "$TEST_STATE/probed"
 cat "$TEST_STATE/monitors";;
*) exit 93;; esac
''')
    (bins/'arch-diag').write_text('''#!/bin/bash
[ ! -e /proc/$$/fd/8 ] || exit 98
[ "$1" = --stdout ] || exit 90
touch "$TEST_STATE/diag-started"
[ ! -f "$TEST_STATE/slow-diag" ] || /bin/sleep 1
echo 'Window client diagnostic evidence'
echo '--- diagnostic snapshot complete ---'
[ ! -f "$TEST_STATE/machine" ] || touch "$TEST_STATE/diag-before-kill"
''')
    script('weston-test','if [[ ${LISTEN_FDS:-} == 1 ]]; then [[ $LISTEN_PID == $$ && -S /proc/self/fd/3 ]] || exit 98; fi\necho fallback > "$TEST_STATE/weston"\n')
    p=bins/'hypr-session'; p.write_text(p.read_text().replace('/usr/bin/weston',str(mocks/'weston-test')).replace('set -u\n', '''set -u
# Test-only simulation of a wall clock repeatedly stepping backwards.
if [[ -f $TEST_STATE/wall-clock-jump ]]; then
  set -T
  trap 'SECONDS=0' DEBUG
fi
''', 1))
    state=home/'.local/state/omarchy-alarm'
    flags=['sudo-fails','display-active','seat-busy','registry-fails','unknown-leader','cleanup-fails','registration-fails','needs-kill','early-exit','no-output','normal-exit','wall-clock-jump','registry-transient','slow-diag','socket-active','watchdog-restart','watchdog-gap']
    def reset(*enabled):
        for name in flags+['machine','ready','probed','kills','weston','diag-before-kill','nspawn-args','diag-started','systemctl','nsenter-args','hyprctl-args']:(w/name).unlink(missing_ok=True)
        for name in enabled:(w/name).touch()
        (drm/'card0-Virtual-1/status').write_text('disconnected\n')
        (drm/'card0-Virtual-2/status').write_text('connected\n')
        (w/'monitors').write_text(json.dumps([dict(name='Virtual-2',width=1024,height=768,dpmsStatus=True)]))
    def run(args=('--selftest',),stop=None,activation=False):
        old=set(state.glob('arch-session-*.log')) if state.exists() else set()
        cmd=[str(bins/'arch-selftest')] if args==('wrapper',) else [str(bins/'hypr-session'),*args]
        pass_fds=()
        if activation:
            cmd=['bash','-c','exec 3<&'+str(seat.fileno())+'; export LISTEN_PID=$$ LISTEN_FDS=1; exec "$@"','activation',*cmd]
            pass_fds=(seat.fileno(),)
        def reset_signals():
            for sig in [signal.SIGHUP,signal.SIGINT,signal.SIGTERM]:signal.signal(sig,signal.SIG_DFL)
        p=subprocess.Popen(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,preexec_fn=reset_signals,pass_fds=pass_fds)
        try:
            if stop:
                end=time.monotonic()+10
                signal_point = 'diag-started' if (w/'slow-diag').exists() else 'ready'
                while not (w/signal_point).exists() and time.monotonic()<end:time.sleep(.005)
                assert (w/signal_point).exists(),'no signal point reached'
                p.send_signal(stop)
            out,err=p.communicate(timeout=30)
            logs=set(state.glob('arch-session-*.log'))-old
            text=''.join(f.read_text() for f in logs)
            for f in logs:assert f.stat().st_mode&0o777==0o600
            return p.returncode,out.decode(),err.decode(),text,logs
        finally:
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
    reset(); rc,out,err,text,logs=run()
    assert rc==0 and len(logs)==1 and out.strip()==str(next(iter(logs))),(rc,out,err,text)
    assert 'stage=output-ready' in text and 'stage=selftest-ready' in text
    assert 'Window client launch stderr evidence' in text and 'Window client diagnostic evidence' in text
    assert text.index('snapshot complete')<text.index('stage=cleanup-begin')
    assert not (w/'machine').exists() and not (w/'weston').exists()
    args=(w/'nspawn-args').read_text()
    for value in ['--setenv=LIBSEAT_BACKEND=seatd','--as-pid2']:
        assert value in args,value
    for flag in ['LIBGL_ALWAYS_SOFTWARE','GALLIUM_DRIVER','AQ_NO_MODIFIERS','AQ_NO_ATOMIC','WAYLAND_DISPLAY']:
        assert '--setenv='+flag not in args
    # Reproduce the parent-display trap using a real listening UNIX socket.
    # An unset selector reaches the idle activation socket; the actual nspawn
    # environment must reject it before any Wayland roundtrip can block.
    activation_socket=socket.socket(socket.AF_UNIX)
    activation_socket.bind(str(runtime/'wayland-0')); activation_socket.listen(1)
    reset(); result=run(); assert result[0]==0,result
    args=(w/'nspawn-args').read_text()
    assert args.index('--bind='+str(runtime)+'\n') < args.index('--bind-ro=/dev/null:'+str(runtime/'wayland-0'))
    def parent_connect(display):
        target=display if display is not None else 'wayland-0'
        if not target.startswith('/'): target=str(runtime/target)
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(.2)
            try: client.connect(target); return True
            except OSError: return False
    assert parent_connect(None), 'fixture must accept an implicit wayland-0 connection'
    assert not parent_connect('/dev/null'), 'private mask must reject a parent connection'
    # Execute the emitted container entry shell with a hostile inherited FD
    # selector, then observe the environment seen by the actual launcher.
    entry=args.splitlines()[args.splitlines().index('-c')+1]
    p=subprocess.run(['sh','-c',entry,'arch-launch','sh','-c','test -z "${WAYLAND_SOCKET+x}${WAYLAND_DISPLAY+x}"'],env=dict(env,WAYLAND_SOCKET='3',WAYLAND_DISPLAY='wayland-0'),capture_output=True)
    assert p.returncode==0,p.stderr
    activation_socket.close()
    for knob in ['arch-software-rendering','arch-no-modifiers','arch-no-atomic']:(home/'.config'/knob).touch()
    reset(); result=run(); assert result[0]==0,result
    args=(w/'nspawn-args').read_text()
    for value in ['--setenv=LIBGL_ALWAYS_SOFTWARE=1','--setenv=AQ_NO_MODIFIERS=1','--setenv=AQ_NO_ATOMIC=1']:assert value in args
    assert '--setenv=GALLIUM_DRIVER=llvmpipe' in args
    for knob in ['arch-software-rendering','arch-no-modifiers','arch-no-atomic']:(home/'.config'/knob).unlink()
    # Provisioned Mesa and an explicitly selected build use their own libraries
    # and matching watchdog, without modifying the packaged binaries.
    mesa=fs/'opt/debian-mesa/lib'; mesa.mkdir(parents=True); (mesa/'libgbm.so.1').touch()
    reset(); result=run(); assert result[0]==0,result
    args=(w/'nspawn-args').read_text()
    for value in ['LD_LIBRARY_PATH=/opt/debian-mesa/lib','GBM_BACKENDS_PATH=/opt/debian-mesa/lib/gbm','__EGL_VENDOR_LIBRARY_FILENAMES=/opt/debian-mesa/egl/50_debian_mesa.json']:
        assert '--setenv='+value in args
    prefix=fs/'opt/hyprland-test/bin'; prefix.mkdir(parents=True)
    for name in ['Hyprland','start-hyprland']:
        (prefix/name).write_text('#!/bin/sh\n'); (prefix/name).chmod(0o755)
    (home/'.config/arch-hyprland-prefix').write_text('/opt/hyprland-test\n')
    reset(); result=run(); assert result[0]==0,result
    args=(w/'nspawn-args').read_text()
    assert '/opt/hyprland-test/bin/start-hyprland\n--path\n/opt/hyprland-test/bin/Hyprland' in args
    assert '--setenv=LD_LIBRARY_PATH=/opt/hyprland-test/lib:/opt/debian-mesa/lib' in args
    (home/'.config/arch-use-arch-mesa').touch()
    reset(); result=run(); assert result[0]==0,result
    args=(w/'nspawn-args').read_text()
    assert 'GBM_BACKENDS_PATH=' not in args and '--setenv=LD_LIBRARY_PATH=/opt/hyprland-test/lib\n' in args
    (home/'.config/arch-hyprland-prefix').unlink(); (home/'.config/arch-use-arch-mesa').unlink()
    # A failed first compositor leaves only its event socket; the watchdog
    # creates a new live instance on the following gate attempt.
    abandoned=runtime/'hypr/abandoned'; abandoned.mkdir()
    old_event=socket.socket(socket.AF_UNIX); old_event.bind(str(abandoned/'.socket2.sock'))
    reset('watchdog-restart'); result=run(); assert result[0]==0,result
    assert 'ipc-wait:' in result[3] and 'stage=output-ready' in result[3]
    assert '-i abandoned' not in (w/'hyprctl-args').read_text()
    old_event.close()
    for flag,token in [('sudo-fails','sudo-needs-password'),('registration-fails','registration-failed'),('early-exit','stage=start-hyprland'),('no-output','gate-timeout')]:
        reset(flag); rc,out,err,text,logs=run()
        assert rc!=0 and token in text,(flag,rc,err,text)
        if flag=='early-exit': assert rc==7 and ('stage=launcher-exit' in text or 'stage=registration-failed' in text)
        assert len(logs)==1 and out.strip()==str(next(iter(logs)))
        assert not (w/'machine').exists() and not (w/'weston').exists()
    for name in ['udmabuf','dri','input','udev','seatd.sock']:
        path=w/name;path.rename(w/(name+'.saved'))
        reset(); rc,_,_,text,_=run(); assert rc!=0 and 'missing-device' in text,(name,rc,text)
        (w/(name+'.saved')).rename(path)
    import fcntl
    with (runtime/'omarchy-alarm-session.lock').open('w') as held:
        fcntl.flock(held,fcntl.LOCK_EX | fcntl.LOCK_NB)
        reset(); rc,_,err,_,logs=run(); assert rc==2 and 'session-busy' in err and not logs and 'pid='+str(os.getpid()) in err and 'cmdline=' in err
    lock=runtime/'omarchy-alarm-session.lock'
    inode=lock.stat().st_ino
    dead=subprocess.Popen(['/bin/true']); dead.wait()
    lock.write_text(str(dead.pid)+'\n')
    reset(); rc,_,err,_,_=run()
    assert rc==0 and 'session-stale' in err and lock.stat().st_ino==inode,(rc,err)
    for flag in ['display-active','seat-busy','registry-fails']:
        reset(flag); rc,_,_,_,logs=run(); assert rc==2 and not logs,(flag,rc)
    reset('unknown-leader'); (w/'machine').write_text('999999')
    rc,_,err,_,logs=run(); assert rc==2 and 'registration-collision' in err and not logs
    assert not (w/'kills').exists(),'refusal killed unowned machine'
    for sig,code in [(signal.SIGTERM,143),(signal.SIGINT,130),(signal.SIGHUP,129),(signal.SIGUSR1,124)]:
        reset(); rc,_,_,text,_=run(stop=sig)
        assert rc==code and not (w/'machine').exists() and not (w/'weston').exists(),(sig,rc,text)
        if sig==signal.SIGUSR1: assert 'stage=selftest-timeout' in text
    reset('no-output','wall-clock-jump'); rc,_,_,text,_=run(); assert rc!=0 and 'stage=gate-timeout' in text
    assert not (w/'machine').exists()
    reset('needs-kill'); rc,_,_,text,_=run()
    assert rc==0 and 'SIGKILL' in (w/'kills').read_text() and not (w/'machine').exists(),text
    reset('registration-fails'); rc,_,_,text,_=run(args=())
    assert rc==0 and (w/'weston').exists() and 'stage=fallback-Weston' in text,text
    reset('registration-fails'); rc,_,err,text,_=run(args=(),activation=True)
    assert rc==0 and (w/'weston').exists(),(rc,err,text)
    reset('registration-fails','slow-diag'); rc,_,_,text,_=run(args=(),stop=signal.SIGTERM)
    assert rc==143 and not (w/'weston').exists() and not (w/'machine').exists(),(rc,text)
    reset('no-output','cleanup-fails'); rc,_,_,text,_=run(args=())
    assert rc==1 and not (w/'weston').exists() and 'cleanup-failed' in text,text
    reset('normal-exit'); rc,_,_,text,_=run(args=())
    assert rc==7 and not (w/'weston').exists(),text
    # Service cleanup is scoped to INVOCATION_ID, including when main was killed.
    reset(); (w/'machine').write_text('999999'); (state/'desktop-owner').write_text('other')
    p=subprocess.run([str(bins/'hypr-session'),'--cleanup'],env=dict(env,INVOCATION_ID='ours'),capture_output=True)
    assert p.returncode==0 and not (w/'kills').exists()
    (state/'desktop-owner').write_text('ours')
    p=subprocess.run([str(bins/'hypr-session'),'--cleanup'],env=dict(env,INVOCATION_ID='ours'),capture_output=True,timeout=8)
    assert p.returncode==0 and 'SIGKILL' in (w/'kills').read_text() and not (w/'machine').exists(),p.stdout
    assert '--kill-after=60' in (bins/'arch-selftest').read_text()
    assert 'SuccessExitStatus=143' in (root/'host/systemd/weston.service.d/hyprland.conf').read_text()
    assert 'hypr-session --cleanup' in (root/'host/systemd/weston.service.d/hyprland.conf').read_text()
    (home/'.config/hypr-session-mode').write_text('debian\n')
    reset('registry-fails'); rc,_,err,_,logs=run(args=()); assert rc==2 and 'registry-unavailable' in err and not logs
    assert not (w/'weston').exists()
    reset(); (w/'registry-transient').write_text('0')
    rc,_,err,_,logs=run(args=()); assert rc==0 and (w/'weston').exists(),(rc,err)
    (home/'.config/hypr-session-mode').write_text('arch\n')
    # One installed gate, two simulated boots with the connected output flipped.
    for connector in ['Virtual-2','Virtual-1']:
        reset('socket-active','display-active')
        for name in ['Virtual-1','Virtual-2']:
            (drm/('card0-'+name)/'status').write_text(('connected' if name==connector else 'disconnected')+'\n')
        (w/'monitors').write_text(json.dumps([dict(name=connector,width=1280,height=720,dpmsStatus=True)]))
        rc,out,err,text,logs=run(args=('wrapper',))
        assert rc==0 and 'stage=selftest-ready' in text,(rc,err,text)
        calls=(w/'systemctl').read_text().splitlines()
        assert calls[0:2]==['--user stop weston.socket','--user stop weston.service'],calls
        assert calls[-2:]==['--user restart weston.socket','--user restart weston.service'],calls
        assert (w/'socket-active').exists() and (w/'display-active').exists()
        assert connector in (w/'nsenter-args').read_text()
        other='Virtual-1' if connector=='Virtual-2' else 'Virtual-2'
        assert other not in (w/'nsenter-args').read_text()
        assert 'Virtual-' not in (w/'hyprctl-args').read_text()
    for flag in ['registration-fails','no-output','seat-busy']:
        reset(flag,'socket-active','display-active')
        rc,_,err,text,_=run(args=('wrapper',))
        assert rc!=0 and (w/'socket-active').exists() and (w/'display-active').exists(),(flag,rc,err,text)
    for sig,code in [(signal.SIGTERM,143),(signal.SIGHUP,129),(signal.SIGINT,130),(signal.SIGUSR1,124)]:
        reset('socket-active','display-active')
        rc,_,err,text,_=run(args=('wrapper',),stop=sig)
        assert rc==code and not (w/'machine').exists(),(sig,rc,err,text)
        assert (w/'socket-active').exists() and (w/'display-active').exists()
    ipc.close()
    seat.close()
print('PASS session: foreground evidence, preflights, ownership, signals, kill escalation, fallback, renderer knobs')
PY
