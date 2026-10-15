#!/usr/bin/env bash
# Exercise the production patch-id upgrade function using cached pinned upstream.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" "$HOME/.cache/omarchy-alarm-tests/upstream" <<'PY'
from pathlib import Path
import os,re,subprocess,sys,tempfile
root=Path(sys.argv[1]); upstream=Path(sys.argv[2]);assert (upstream/'.git').exists(),'run the patches check first'
source=(root/'container/install.sh').read_text()
function=re.search(r'^clone_and_patch_omarchy\(\) \{\n.*?^\}',source,re.M|re.S).group()
with tempfile.TemporaryDirectory(prefix='patch-upgrade-') as d:
    w=Path(d); checkout=w/'omarchy'
    def git(*args):return subprocess.check_output(['git','-C',str(checkout),*args],text=True).strip()
    subprocess.run(['git','clone','--quiet','--shared',str(upstream),str(checkout)],check=True)
    git('config','commit.gpgsign','false')
    git('switch','-c','arm-port')
    for patch in sorted((root/'patches').glob('*.patch'))[:-1]:
        git('-c','user.name=tests','-c','user.email=tests@example.com','am',str(patch))
    old=git('rev-parse','HEAD')
    env=dict(os.environ,ROOT=str(root),OMARCHY_PATH=str(checkout),MIRROR='global')
    def apply():return subprocess.run(['bash','-c','set -eu\n'+function+'\nclone_and_patch_omarchy'],env=env,capture_output=True,text=True)
    result=apply();assert result.returncode==0,result.stderr
    new=git('rev-parse','HEAD');assert old!=new and git('rev-list','--count',old+'..'+new)=='1'
    result=apply();assert result.returncode==0 and git('rev-parse','HEAD')==new,result.stderr
    assert git('status','--porcelain')==''
    (checkout/'local-user-file').write_text('preserve this\n')
    result=apply();assert result.returncode!=0 and 'local changes' in result.stderr
    assert (checkout/'local-user-file').read_text()=='preserve this\n' and git('rev-parse','HEAD')==new
print('PASS patch upgrade: existing prior-patch install, apply only newest, stable rerun, preserve local changes')
PY
