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
    for name in ['dri','input','udev']: (w/name).mkdir()
    (w/'udmabuf').touch(); seat=socket.socket(socket.AF_UNIX); seat.bind(str(w/'seatd.sock'))
    env=dict(os.environ,HOME=str(home),PATH=str(mocks)+':'+os.environ['PATH'],TEST_STATE=str(w))
    env.pop('INVOCATION_ID',None); env.pop('OMARCHY_SESSION_INTERNAL',None)
    def script(name,body):
        p=mocks/name;p.write_text('#!/bin/bash\n'+body);p.chmod(0o755)
    for src in (root/'host/bin').iterdir():
        s=src.read_text()
        for key,value in {'@USER@':os.environ.get('USER','tester'),'@UID@':uid,'@ROOTFS@':str(fs),'@HOME@':str(home),'@CHOME@':'/home/tester','@HOME_BIND_DIRS@':'','@VERSION@':(root/'VERSION').read_text().strip()}.items(): s=s.replace(key,value)
        for key,value in {'/run/user/'+uid:str(runtime),'/dev/dri':str(w/'dri'),'/dev/udmabuf':str(w/'udmabuf'),'/dev/input':str(w/'input'),'/run/udev':str(w/'udev'),'/run/seatd.sock':str(w/'seatd.sock')}.items(): s=s.replace(key,value)
        # Accelerate only harness deadlines, not the production decision logic.
        s=s.replace('$(monotonic_seconds) + 30','$(monotonic_seconds) + '+str(gate_seconds)).replace('$(monotonic_seconds) + 3','$(monotonic_seconds) + 2')
        p=bins/src.name;p.write_text(s);p.chmod(0o755)
    script('sudo','[ "$1" != -n ] || shift\n[ ! -f "$TEST_STATE/sudo-fails" ] || exit 1\nexec env "$@"\n')
    script('date','[ ! -f "$TEST_STATE/wall-clock-jump" ] || [ "$1" != +%s ] || { echo 0; exit; }\nexec /bin/date "$@"\n')
    script('sleep','exec /bin/sleep .04\n')
    script('systemctl','[ ! -f "$TEST_STATE/display-active" ] || { echo active; exit 0; }\necho inactive; exit 3\n')
    script('fuser','[ -f "$TEST_STATE/seat-busy" ]\n')
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
    # IPC predicate has its own real-script JSON matrix in display-regressions.sh.
    (bins/'arch-output').write_text('''#!/bin/bash
case "${1:-}" in --*) echo "probe $1"; exit 0;; esac
[ -f "$TEST_STATE/machine" ] && [ -f "$TEST_STATE/ready" ] || exit 1
touch "$TEST_STATE/probed"
printf '[{"name":"Virtual-2","width":1024,"height":768,"dpmsStatus":true}]\\n'
''')
    (bins/'arch-diag').write_text('''#!/bin/bash
[ "$1" = --stdout ] || exit 90
touch "$TEST_STATE/diag-started"
[ ! -f "$TEST_STATE/slow-diag" ] || /bin/sleep 1
echo 'Window client diagnostic evidence'
echo '--- diagnostic snapshot complete ---'
[ ! -f "$TEST_STATE/machine" ] || touch "$TEST_STATE/diag-before-kill"
''')
    script('weston-test','echo fallback > "$TEST_STATE/weston"\n')
    p=bins/'hypr-session'; p.write_text(p.read_text().replace('/usr/bin/weston',str(mocks/'weston-test')).replace('set -u\n', '''set -u
# Test-only simulation of a wall clock repeatedly stepping backwards.
if [[ -f $TEST_STATE/wall-clock-jump ]]; then
  set -T
  trap 'SECONDS=0' DEBUG
fi
''', 1))
    state=home/'.local/state/omarchy-alarm'
    flags=['sudo-fails','display-active','seat-busy','registry-fails','unknown-leader','cleanup-fails','registration-fails','needs-kill','early-exit','no-output','normal-exit','wall-clock-jump','registry-transient','slow-diag']
    def reset(*enabled):
        for name in flags+['machine','ready','probed','kills','weston','diag-before-kill','nspawn-args','diag-started']:(w/name).unlink(missing_ok=True)
        for name in enabled:(w/name).touch()
    def run(args=('--selftest',),stop=None):
        old=set(state.glob('arch-session-*.log')) if state.exists() else set()
        cmd=[str(bins/'arch-selftest')] if args==('--selftest',) else [str(bins/'hypr-session'),*args]
        def reset_signals():
            for sig in [signal.SIGHUP,signal.SIGINT,signal.SIGTERM]:signal.signal(sig,signal.SIG_DFL)
        p=subprocess.Popen(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,preexec_fn=reset_signals)
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
    for value in ['--setenv=LIBGL_ALWAYS_SOFTWARE=1','--setenv=GALLIUM_DRIVER=llvmpipe','--setenv=AQ_NO_MODIFIERS=1','--setenv=AQ_NO_ATOMIC=0','--as-pid2']:
        assert value in args,value
    for knob in ['arch-hardware-rendering','arch-enable-modifiers','arch-no-atomic']:(home/'.config'/knob).touch()
    reset(); result=run(); assert result[0]==0,result
    args=(w/'nspawn-args').read_text()
    for value in ['--setenv=LIBGL_ALWAYS_SOFTWARE=0','--setenv=AQ_NO_MODIFIERS=0','--setenv=AQ_NO_ATOMIC=1']:assert value in args
    assert '--setenv=GALLIUM_DRIVER' not in args
    for knob in ['arch-hardware-rendering','arch-enable-modifiers','arch-no-atomic']:(home/'.config'/knob).unlink()
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
        reset(); rc,_,err,_,logs=run(); assert rc==2 and 'session-busy' in err and not logs
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
    seat.close()
print('PASS session: foreground evidence, preflights, ownership, signals, kill escalation, fallback, renderer knobs')
PY
