#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
from pathlib import Path
import os,re,shutil,signal,subprocess,sys,tempfile,time
root=Path(sys.argv[1]); host=(root/'host/install.sh').read_text()
def function(source,name):
    match=re.search(r'^'+name+r'\(\) \{\n.*?^\}',source,re.M|re.S)
    assert match,name
    return match.group()
with tempfile.TemporaryDirectory(prefix='audit-regressions-') as d:
    w=Path(d); bins=w/'bin'; bins.mkdir()
    for cmd in ['bash','mktemp','rm','grep']:(bins/cmd).symlink_to(shutil.which(cmd))
    def script(name,body):
        p=bins/name;p.write_text('#!/bin/bash\n'+body);p.chmod(0o755)
    script('curl','exit 0\n')
    common='set -eu\nwarn() { echo "$*"; }; note() { echo "$*"; }; die() { echo "$*"; exit 1; };\n'
    source=common+function(host,'verify_gpg')+'\nverify_gpg "$TEST_FILE"\n'
    env=dict(os.environ,PATH=str(bins),DRY_RUN='0',ALARM_URL='https://example.com/rootfs',ALARM_KEY='test-key',SCRIPT_DIR=str(root/'host'),TEST_FILE=str(w/'rootfs'))
    def verify(mode):
        return subprocess.run(['/bin/bash','-c',source],env=dict(env,GPG_MODE=mode),capture_output=True,text=True)
    result=verify('absent');assert result.returncode==0 and 'UNVERIFIED: gpg not installed' in result.stdout,result
    script('gpg','''case "$*" in *--import*) exit 0;; esac
case "$GPG_MODE" in
 valid) echo '[GNUPG:] VALIDSIG test-key' ;;
 bad) echo '[GNUPG:] BADSIG other-key'; exit 1 ;;
 unknown) echo '[GNUPG:] NO_PUBKEY other-key'; exit 1 ;;
esac
''')
    assert verify('valid').returncode==0
    for mode in ['bad','unknown']:
        result=verify(mode);assert result.returncode!=0,(mode,result)
    for mirror in ['global','cn']:
        result=subprocess.run(['bash',str(root/'host/install.sh'),'--dry-run','--user','testuser','--mirror',mirror],capture_output=True,text=True)
        assert result.returncode==0 and 'gnupg' in result.stderr,result.stderr
    # Exercise the exact post-apt helper with both distinct privilege failures.
    source=common+function(host,'check_target_sudo')+'\ncheck_target_sudo\n'
    def sudo_check():return subprocess.run(['/bin/bash','-c',source],env=dict(env,TARGET_USER='testuser'),capture_output=True,text=True)
    result=sudo_check();assert result.returncode!=0 and 'sudo-unavailable' in result.stdout
    script('sudo','exit 1\n');script('runuser','shift 3\nexec "$@"\n')
    result=sudo_check();assert result.returncode!=0 and 'sudo-needs-password' in result.stdout,result
    script('sudo','exit 0\n');assert sudo_check().returncode==0
    assert host.index('if (( ! DRY_RUN && DISPLAY_HOOK )); then check_target_sudo') > host.index('install -y --no-install-recommends "${missing[@]}"')
    result=subprocess.run(['bash',str(root/'host/install.sh'),'--render-only',str(w/'rendered'),'--user','testuser'],capture_output=True,text=True)
    assert result.returncode==0,result.stderr
    diag=(w/'rendered/bin/arch-diag').read_text();assert (root/'VERSION').read_text().strip() in diag and '@VERSION@' not in diag
    result=subprocess.run([str(w/'rendered/bin/arch-hyprland')],env=dict(os.environ,PATH='',OMARCHY_SESSION_INTERNAL='1'),capture_output=True,text=True)
    assert result.returncode!=0 and 'sudo-unavailable' in result.stderr,result
    # Burst logs remain bounded without delaying or dropping the final evidence.
    state=w/'logs';state.mkdir()
    for i in range(14):
        (state/f'arch-session-{i:02}.log').write_text('old')
        (state/f'arch-diag-{i:02}.log').write_text('old')
    log=state/'arch-session-current.log';log.touch(mode=0o600)
    payload=b'x'*(20*1024*1024)+b'\nLAST decisive evidence\n'
    result=subprocess.run([str(root/'host/bin/arch-log'),str(log)],input=payload,capture_output=True)
    assert result.returncode==0,result.stderr
    data=log.read_bytes();assert len(data)<=8*1024*1024 and data.endswith(b'LAST decisive evidence\n')
    assert b'discarded (8 MiB limit)' in data and log.stat().st_mode&0o777==0o600
    assert len(list(state.glob('arch-session-*.log')))==10 and len(list(state.glob('arch-diag-*.log')))==10
    # A service-wide TERM must not cut off the owner's final diagnostics.
    proc=subprocess.Popen([str(root/'host/bin/arch-log'),str(log)],stdin=subprocess.PIPE,stderr=subprocess.PIPE)
    proc.stdin.write(b'logger alive\n');proc.stdin.flush()
    end=time.monotonic()+5
    while not log.read_bytes().endswith(b'logger alive\n') and time.monotonic()<end:time.sleep(.01)
    assert log.read_bytes().endswith(b'logger alive\n')
    proc.send_signal(signal.SIGTERM)
    proc.stdin.write(b'after TERM\n');proc.stdin.close()
    assert proc.wait(timeout=5)==0 and log.read_bytes().endswith(b'after TERM\n')
    groups=subprocess.run(['awk','-F:', 'NF && $2 != 0 && !seen[$2]++'],input='device0:0\nvideo:44\ndevice44:44\n',text=True,capture_output=True)
    assert groups.stdout=='video:44\n'
    assert 'NF && $2 != 0 && !seen[$2]++' in host
    readme=(root/'README.md').read_text();trouble=(root/'docs/troubleshooting.md').read_text()
    assert 'arch-selftest' in readme and '/run/user/UID/hypr/INSTANCE/hyprland.log' in trouble
    assert '/raw/v0.2.4/' not in readme and 'OMARCHY_ALARM_REF=v0.2.4' not in readme
    # README is an installation/usage guide; investigations belong in docs.
    narrative = r'根因|root cause|v0\.2\.\d+\s*修复|validation|investigation|blackscreen|启动诊断|复现|修复已确认|VM evidence|troubleshooting|故障排除|Provenance'
    troubleshooting_link = '[故障排除 / Troubleshooting](docs/troubleshooting.md)'
    def readme_usage_only(text):
        lines = text.splitlines()
        if lines.count(troubleshooting_link) != 1:
            return False
        body = '\n'.join(line for line in lines if line != troubleshooting_link)
        targets = re.findall(r'\]\(\s*<?([^\s)>]+)|^\s{0,3}\[[^\]]+\]:\s*<?([^\s>]+)', body, re.M)
        for inline, reference in targets:
            target = inline or reference
            if not re.match(r'https?://|#', target, re.I) or re.search(r'/(?:docs/|CHANGELOG(?:\.|/|$))', target, re.I):
                return False
        return not re.search(narrative, body, re.I)
    assert readme_usage_only(readme), 'README allows exactly one troubleshooting link; move history to CHANGELOG or docs'
    assert not readme_usage_only(readme.replace(troubleshooting_link, ''))
    assert not readme_usage_only(readme + '\n' + troubleshooting_link)
    assert not readme_usage_only(readme.replace(troubleshooting_link, troubleshooting_link + ' root cause'))
    for forbidden in ['根因', 'root cause', 'v0.2.7 修复', '[validation](docs/v0.2.7-validation.md)', '[notes](docs/history.md)', '[notes](./docs/history.md)', '[notes](CHANGELOG.md)', '[notes](https://github.com/example/repo/blob/main/docs/history.md)', '[notes]: docs/history.md']:
        assert not readme_usage_only(readme + '\n' + forbidden), forbidden
    for instruction in ['MIRROR=cn', 'gitee.com/', 'OMARCHY_ALARM_REF=main', 'Resume', 'hypr-switch arch', 'hypr-switch debian', '~/.local/bin/arch-selftest', '## 卸载', '## 已知限制']:
        assert instruction in readme, instruction
print('PASS audit: sudo bootstrap ordering/tokens, signature policy, version rendering, docs')
PY
