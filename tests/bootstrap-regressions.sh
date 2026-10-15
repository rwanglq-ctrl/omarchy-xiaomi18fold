#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import os,pathlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]); entry=(root/'install.sh').read_text(); realgit=shutil.which('git')
assert realgit,'git is required to verify real branch/tag/SHA checkout'
with tempfile.TemporaryDirectory(prefix='bootstrap-regressions-') as tmp:
    w=pathlib.Path(tmp); repo=w/'repo'; repo.mkdir(); bins=w/'bin'; bins.mkdir(); scratch=w/'scratch'; scratch.mkdir()
    def git(*args):return subprocess.check_output([realgit,'-C',str(repo),*args],text=True).strip()
    git('init','-q','-b','main');git('config','commit.gpgsign','false');git('config','user.name','tests');git('config','user.email','tests@example.com')
    (repo/'install.sh').write_text('''#!/bin/bash
[ -z "$(cat)" ] || exit 99
printf 'CHECKED_OUT='
git -C "$(dirname "$0")" rev-parse HEAD
''')
    git('add','.');git('commit','-qm','first'); first=git('rev-parse','HEAD');git('tag','v-test');git('branch','topic')
    (repo/'second').touch();git('add','.');git('commit','-qm','second');second=git('rev-parse','HEAD')
    osfile=w/'os-release';osfile.write_text('ID=debian\nVERSION_ID=13\n')
    for name in ['bash','sh','uname','mktemp','rm','timeout','env','cat','chmod','ln','cp','dirname']:
        path=shutil.which(name); assert path,name; (bins/name).symlink_to(path)
    def script(name,text):
        path=bins/name;path.write_text('#!/bin/bash\n'+text);path.chmod(0o755)
    wrapper=w/'git-wrapper'
    wrapper.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$GIT_LOG"
if [ "$1" = clone ]; then
 [ ! -f "$FAIL_CLONE" ] || exit 128
 args=("$@")
 args[${#args[@]}-2]="file://$FIXTURE"
 exec "$REAL_GIT" "${args[@]}"
fi
exec "$REAL_GIT" "$@"
''');wrapper.chmod(0o755)
    script('sudo','[ "$1" != -n ] || shift\nexec "$@"\n')
    script('curl','printf "%s\\n" "$*" >> "$CURL_LOG"\nexit 22\n')
    script('apt-get','''echo "$*" >> "$APT_LOG"
case "$*" in *install*) cp "$WRAPPER" "$MOCK_BIN/git";; esac
''')
    env=dict(os.environ,PATH=str(bins),TMPDIR=str(scratch),OMARCHY_ALARM_OS_RELEASE=str(osfile),OMARCHY_ALARM_ARCH='aarch64',OMARCHY_ALARM_REPO='file://'+str(repo),REAL_GIT=realgit,FIXTURE=str(repo),GIT_LOG=str(w/'git.log'),CURL_LOG=str(w/'curl.log'),APT_LOG=str(w/'apt.log'),FAIL_CLONE=str(w/'fail'),WRAPPER=str(wrapper),MOCK_BIN=str(bins),MIRROR='global')
    def run(ref='main',dry=False,**changes):
        e=dict(env,OMARCHY_ALARM_REF=ref);e.update(changes)
        for key in [k for k,v in e.items() if v is None]:del e[key]
        return subprocess.run(['/bin/bash','-s','--',*(['--dry-run'] if dry else [])],input=entry,text=True,capture_output=True,env=e,timeout=20)
    shutil.copy(wrapper,bins/'git')
    for ref,want in [('main',second),('topic',first),('v-test',first),(first,first)]:
        p=run(ref);assert p.returncode==0 and 'CHECKED_OUT='+want in p.stdout,(ref,p.stdout,p.stderr)
        assert not list(scratch.iterdir()),'bootstrap checkout leaked'
    before={p:p.stat().st_mtime_ns for p in w.rglob('*')}
    p=run(dry=True);assert p.returncode==0 and 'no fetch or writes' in p.stderr
    assert before=={p:p.stat().st_mtime_ns for p in w.rglob('*')},'dry-run changed filesystem'
    assert not (w/'curl.log').exists(),'bootstrap fetched an archive'
    (bins/'git').unlink();p=run();assert p.returncode==0 and 'install' in (w/'apt.log').read_text(),p.stderr
    assert 'git ca-certificates' in (w/'apt.log').read_text()
    (bins/'git').unlink();(bins/'apt-get').rename(bins/'apt-saved');p=run()
    assert p.returncode!=0 and 'git is required' in p.stderr,p.stderr
    (bins/'apt-saved').rename(bins/'apt-get');shutil.copy(wrapper,bins/'git')
    (w/'fail').touch();p=run(MIRROR='cn',OMARCHY_ALARM_REPO=None)
    assert p.returncode!=0 and 'git clone failed' in p.stderr
    assert not (w/'curl.log').exists(),'clone failure requested archive'
    (w/'fail').unlink();(w/'git.log').unlink();p=run(MIRROR='auto',OMARCHY_ALARM_REPO=None)
    assert p.returncode==0,p.stderr
    assert 'gitee.com/zenbardofsuhe/' in (w/'git.log').read_text()
    assert 'github.com' not in (w/'git.log').read_text()
    assert 'archive' not in (w/'curl.log').read_text()
    # Preserve clone arguments through the wrapper so real Git validates branch/tag
    # handling. Only transport is redirected to the fixture: no network is needed.
    for override in [None,'gitee','https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm']:
        for ref,want,branch in [('main',second,'main'),('topic',first,'topic'),('v-test',first,'v-test'),(first,first,'main')]:
            (w/'git.log').unlink(missing_ok=True);(w/'curl.log').unlink(missing_ok=True)
            p=run(ref,MIRROR='cn',OMARCHY_ALARM_REPO=override)
            assert p.returncode==0 and 'CHECKED_OUT='+want in p.stdout,(ref,p.stderr)
            calls=(w/'git.log').read_text()
            assert '--branch '+branch+' -- https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm ' in calls,calls
            assert 'github.com' not in calls and 'archive' not in calls,calls
            assert not (w/'curl.log').exists(),'explicit CN requested HTTP/archive/probe'
            assert not list(scratch.iterdir()),'CN checkout leaked'
    # CN apt bootstraps using a temporary signed Debian source, not a tarball.
    (bins/'git').unlink();p=run(first,MIRROR='cn',OMARCHY_ALARM_REPO=None)
    assert p.returncode==0 and 'CHECKED_OUT='+first in p.stdout,p.stderr
    assert 'Dir::Etc::sourcelist=' in (w/'apt.log').read_text()
    assert not list(scratch.iterdir())
    # Pad v0.2.7 upgrade: a failing inner installer made the EXIT trap read an
    # out-of-scope local ("tmp: unbound variable"), masking its status and
    # leaking the checkout. The inner status and cleanup must both survive.
    (repo/'install.sh').write_text('#!/bin/bash\necho inner-failed >&2\nexit 3\n')
    git('add','.');git('commit','-qm','failing')
    p=run('main')
    assert p.returncode==3 and 'inner-failed' in p.stderr,(p.returncode,p.stderr)
    assert 'unbound variable' not in p.stderr,p.stderr
    assert not list(scratch.iterdir()),'failed bootstrap leaked its checkout'
print('PASS bootstrap: real branch/tag/SHA, apt git bootstrap, no apt, no archives, Gitee-only CN branch/tag/SHA, auto CN, offline dry-run, failing inner status + cleanup')
PY
