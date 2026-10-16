#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json, os, pathlib, shlex, shutil, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='install-session-') as tmp:
    w = pathlib.Path(tmp); bins = w/'bin'; bins.mkdir(); home = w/'home'; home.mkdir()
    calls = w/'calls'; entry = w/'entry with spaces.sh'
    def script(name, body):
        p = bins/name; p.write_text('#!/bin/bash\n'+body); p.chmod(0o755)
    script('tmux', '''printf '%s\\n' "$*" >> "$CALLS"
case "$1" in
 display-message) printf '%s\\n' "${SESSION:-other}" ;;
 has-session) [[ ${EXISTS:-0} == 1 ]] ;;
 new-session) printf '%s\\n' "${@: -1}" > "$RUNNER" ;;
 switch-client|attach) exit 0 ;;
 *) exit 99 ;;
esac
''')
    env = dict(os.environ, HOME=str(home), PATH=str(bins)+':'+os.environ['PATH'],
               TMPDIR=str(w), TMUX_TMPDIR=str(w), CALLS=str(calls), RUNNER=str(w/'runner'), MIRROR='cn')
    for k in ['TMUX', 'TMUX_PANE', 'OMARCHY_INSTALL_LOG']: env.pop(k, None)
    common = 'set -euo pipefail\nsource '+shlex.quote(str(root/'install.sh'))+'\n'
    def run(code, **extra):
        return subprocess.run(['bash','-c',common+code], env=dict(env, **extra), text=True, capture_output=True, timeout=20)
    # Source-only must never enter the installer, and a dry run does no I/O.
    before = sorted(str(p) for p in w.rglob('*'))
    p = run('omarchy_install_session 1 /missing --dry-run')
    assert p.returncode == 0 and not calls.exists(), p
    assert before == sorted(str(p) for p in w.rglob('*'))
    # An existing named session continues inline without creating/nesting tmux.
    p = run('omarchy_install_session 0 /missing; echo CONTINUED', TMUX='fixture', SESSION='omarchy-fold-install', OMARCHY_INSTALL_LOG='parent-log')
    assert p.returncode == 0 and 'CONTINUED' in p.stdout, p
    assert calls.read_text().count('display-message') == 1
    assert 'new-session' not in calls.read_text()
    calls.unlink()
    p = run('omarchy_install_session 0 /missing; echo UNSAFE', TMUX='fixture', SESSION='other', OMARCHY_INSTALL_LOG='parent-log')
    assert p.returncode != 0 and 'Cannot verify inherited install session' in p.stderr and 'UNSAFE' not in p.stdout, p
    calls.unlink()
    # Exact match prevents omarchy-fold-install-old being mistaken for this session.
    p = run('omarchy_install_session 0 /missing; echo DUPLICATE', EXISTS='1')
    assert p.returncode == 0 and 'DUPLICATE' not in p.stdout, p
    assert calls.read_text() == 'has-session -t =omarchy-fold-install\n'
    assert not (home/'.local').exists()
    calls.unlink()
    # Switching from another tmux session must never attach/nest.
    p = run('omarchy_install_session 0 /missing', TMUX='fixture', SESSION='other', EXISTS='1')
    assert p.returncode == 0 and 'switch-client -t =omarchy-fold-install' in calls.read_text(), p
    assert '\nattach' not in calls.read_text()
    calls.unlink()
    # Detached runner preserves quoted args/settings even on an old tmux server.
    entry.write_text(common+'''omarchy_install_session 0 "$0" "$@"
printf 'ARGS=<%s><%s> MIRROR=%s REF=%s\\n' "$1" "$2" "$MIRROR" "$OMARCHY_ALARM_REF"
echo TEST-STDERR >&2
exit 23
''')
    args = ['--profile=full', "a b;$(touch SHOULD-NOT-EXIST)'quote"]
    p = run('omarchy_install_session 0 '+shlex.quote(str(entry))+' '+shlex.join(args), OMARCHY_ALARM_REF='v-test')
    assert p.returncode == 0 and 'new-session -d -s omarchy-fold-install' in calls.read_text(), p
    runner = pathlib.Path((w/'runner').read_text().strip())
    text = runner.read_text()
    assert runner.stat().st_mode & 0o777 == 0o600
    assert 'export MIRROR=cn' in text and 'export OMARCHY_ALARM_REF=v-test' in text
    # Replace only the post-install interactive shell for this synchronous unit test.
    runner.write_text(text.replace('exec bash --noprofile --norc -i', 'exit "$rc"'))
    p = subprocess.run(['bash',str(runner)], env=dict(env, TMUX='fixture', SESSION='omarchy-fold-install', MIRROR='global'), text=True, capture_output=True, timeout=20)
    assert p.returncode == 23, p
    log = home/'.local/state/omarchy-alarm/install.log'
    assert "ARGS=<"+args[0]+"><"+args[1]+"> MIRROR=cn REF=v-test" in log.read_text(), log.read_text()
    assert 'TEST-STDERR' in log.read_text() and 'Install exit status: 23' in log.read_text()
    assert not runner.exists() and not (root/'SHOULD-NOT-EXIST').exists()
    assert log.stat().st_mode & 0o777 == 0o600
    # Missing tmux: exercise noninteractive apt in both modes without host writes.
    aptcalls = w/'apt'; aptenv = w/'aptenv'
    script('sudo', 'exec "$@"\n')
    script('apt-get', 'printf "%s\\n" "$*" >> "$APT_CALLS"\nprintf "%s\\n" "$DEBIAN_FRONTEND" >> "$APT_ENV"\n')
    for mode in ['cn', 'global']:
        aptcalls.unlink(missing_ok=True); aptenv.unlink(missing_ok=True)
        p = run('omarchy_session_apt', MIRROR=mode, APT_CALLS=str(aptcalls), APT_ENV=str(aptenv))
        assert p.returncode == 0, p
        text = aptcalls.read_text()
        assert 'install -y --no-install-recommends tmux ca-certificates' in text
        assert set(aptenv.read_text().splitlines()) == {'noninteractive'}
        assert ('Dir::Etc::sourcelist=' in text) == (mode == 'cn')
        assert not list(w.glob('omarchy-tmux-apt.*'))
    # The caller checks apt failure with ||, which suppresses Bash errexit
    # inside the helper; allocation/update failures must return explicitly.
    p = run('mktemp() { return 1; }; omarchy_session_apt || exit 37', MIRROR='cn')
    assert p.returncode == 37, p
    p = run('apt-get() { [[ $* != *update* ]] || return 1; echo UNSAFE-INSTALL; }; sudo() { "$@"; }; env() { shift; "$@"; }; omarchy_session_apt || exit 37', MIRROR='global')
    assert p.returncode == 37 and 'UNSAFE-INSTALL' not in p.stdout, p
    # Zero arguments must stay zero (printf %q with no operands emits '').
    entry.write_text(common+'''omarchy_install_session 0 "$0" "$@"
printf 'ARGC=%s\\n' "$#"
[[ $# == 0 ]]
''')
    p = run('omarchy_install_session 0 '+shlex.quote(str(entry)))
    assert p.returncode == 0, p
    runner = pathlib.Path((w/'runner').read_text().strip())
    runner.write_text(runner.read_text().replace('exec bash --noprofile --norc -i', 'exit "$rc"'))
    p = subprocess.run(['bash',str(runner)], env=dict(env, TMUX='fixture', SESSION='omarchy-fold-install'), text=True, capture_output=True, timeout=20)
    assert p.returncode == 0 and 'ARGC=0' in log.read_text(), p
    # Apt failure must explain the failed protection instead of continuing naked.
    p = run('''command() { if [[ $1 == -v && $2 == tmux ]]; then return 1; fi; builtin command "$@"; }
omarchy_session_apt() { return 42; }
omarchy_install_session 0 /missing
''')
    assert p.returncode != 0 and 'Cannot install tmux; retry after fixing apt' in p.stderr, p
    # Settings absent in this invocation must not leak from an old tmux server.
    entry.write_text(common+'''omarchy_install_session 0 "$0"
printf 'ENV=%s,%s,%s,%s\\n' "${MIRROR-unset}" "${OMARCHY_ALARM_REF-unset}" "${NETWORK_STALE-unset}" "$TERM"
''')
    clean_env = dict(env, TERM='outer-terminal')
    clean_env.pop('MIRROR', None)
    p = subprocess.run(['bash','-c',common+'omarchy_install_session 0 '+shlex.quote(str(entry))], env=clean_env, text=True, capture_output=True, timeout=20)
    assert p.returncode == 0, p
    runner = pathlib.Path((w/'runner').read_text().strip())
    runner.write_text(runner.read_text().replace('exec bash --noprofile --norc -i', 'exit "$rc"'))
    p = subprocess.run(['bash',str(runner)], env=dict(env, TMUX='fixture', SESSION='omarchy-fold-install', MIRROR='stale-cn', OMARCHY_ALARM_REF='stale-ref', NETWORK_STALE='stale', TERM='tmux-256color'), text=True, capture_output=True, timeout=20)
    assert p.returncode == 0 and 'ENV=unset,unset,unset,tmux-256color' in log.read_text(), p
    # A piped run can reconstruct itself before cloning, with no source file.
    p = run('omarchy_install_session 0 "" --profile core')
    runner = pathlib.Path((w/'runner').read_text().strip())
    assert 'omarchy_entry ()' in runner.read_text() and '( set -e; omarchy_entry --profile core' in runner.read_text()
    # sudo explicitly carries the verified tmux context and parent log.
    for path in [root/'install.sh', root/'host/install.sh']:
        text = path.read_text()
        assert 'TMUX="${TMUX:-}" TMUX_PANE="${TMUX_PANE:-}"' in text
        assert 'OMARCHY_INSTALL_LOG="${OMARCHY_INSTALL_LOG:-}"' in text
print('PASS install session: dry no-op, same/existing/other sessions, exact targets, quoted runner/env, durable stdout/stderr/status, CN/global apt, piped snapshot, sudo context')
PY
