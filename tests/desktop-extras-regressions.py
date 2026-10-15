#!/usr/bin/env python3
"""Verify optional desktop extras preserve user config and fail closed."""
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
from pathlib import Path
import tarfile
import tempfile
import sys
sys.dont_write_bytecode = True
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('extras', ROOT / 'lib/desktop-extras.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    home, cache = root / 'home', root / 'cache'
    home.mkdir(); cache.mkdir()
    config = home / '.config/nvim'
    config.mkdir(parents=True)
    (config / 'init.lua').write_text('user configuration\n')
    with patch.object(m, 'asset', side_effect=AssertionError('must not download')):
        assert 'preserved' in m.install_lazyvim({}, home, cache, 'cn')
    assert (config / 'init.lua').read_text() == 'user configuration\n'
    (config / 'init.lua').unlink(); config.rmdir()
    archive = root / 'fixture.tar.gz'
    def bundle(complete):
        entries = {'config/lazy-lock.json': json.dumps({'lazy.nvim': {'commit': '123'}}),
                   'plugins.json': json.dumps([dict(name='lazy.nvim', commit='123')]),
                   'config/lua/config/lazy.lua': 'local root = "@PLUGIN_ROOT@"\n'}
        if complete:
            entries['plugins/lazy.nvim/lua/lazy/init.lua'] = 'return {}\n'
        with tarfile.open(archive, 'w:gz') as tar:
            for name, data in entries.items():
                member = tarfile.TarInfo(name); member.size = len(data); member.mode = 0o644
                tar.addfile(member, io.BytesIO(data.encode()))
    bundle(False)
    with patch.object(m, 'asset', return_value=archive):
        try:
            m.install_lazyvim({'version': 'fixture'}, home, cache, 'cn')
        except ValueError as error:
            assert 'missing' in str(error)
        else:
            raise AssertionError('incomplete bundle accepted')
    assert not config.exists()
    assert not (home / '.local/share/omarchy-lazyvim').exists()
    bundle(True)
    with patch.object(m, 'asset', return_value=archive):
        assert 'installed starter' in m.install_lazyvim({'version': 'fixture'}, home, cache, 'cn')
        assert 'preserved' in m.install_lazyvim({'version': 'fixture'}, home, cache, 'cn')
    assert '@PLUGIN_ROOT@' not in (config / 'lua/config/lazy.lua').read_text()

for manifest in ('aur-assets.json', 'lazyvim-assets.json'):
    for item in json.loads((ROOT / 'packages/desktop-extras' / manifest).read_text()):
        assert item['integrity'].startswith('sha256-hex:')
        assert len(item['integrity'].split(':')[1]) == 64
        assert '/' not in item['file']
print('PASS desktop extras: absent-only LazyVim, incomplete bundle rejection, offline snapshot, pinned assets')

# Real makepkg distinguishes empty architecture arrays from unset variables.
# Keep the top-level SHA256 mandatory, and verify corrupt sources still fail.
if shutil.which('makepkg'):
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary)
        payload = stage / 'fixture.txt'; payload.write_text('verified source fixture\n')
        digest = hashlib.sha256(payload.read_bytes()).hexdigest()
        (stage / 'PKGBUILD').write_text(
            "pkgname=fixture-source\npkgver=1\npkgrel=1\narch=('any')\n"
            "source=('fixture.txt')\nsha256sums=('" + digest + "')\n"
            "source_aarch64=()\nsource_x86_64=()\nsha256sums_aarch64=()\nsha512sums=()\n"
            "package() { :; }\n")
        m.normalize_source_arrays(stage)
        env = dict(os.environ, HOME=str(stage))
        subprocess.run(['makepkg', '--verifysource', '--ignorearch'], cwd=stage, env=env, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        payload.write_text('corrupt source\n')
        result = subprocess.run(['makepkg', '--verifysource', '--ignorearch'], cwd=stage, env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        assert result.returncode != 0, 'makepkg accepted corrupted source'
    print('PASS real makepkg source verification after empty architecture-array normalization')
else:
    print('SKIP real makepkg source verification: executable unavailable')

# The pinned Yaru workaround generates required GTK colors but packages only
# icons. Exercise its package function with a local Meson install stand-in.
with tempfile.TemporaryDirectory() as temporary:
    stage = Path(temporary)
    shutil.copyfile(ROOT / 'packages/desktop-extras/aur/yaru-icon-theme/PKGBUILD', stage / 'PKGBUILD')
    m.fix_yaru_icon_recipe(stage)
    text = (stage / 'PKGBUILD').read_text()
    assert '-Dgtk=true' in text and '-Dgtk=false' not in text
    source = stage / 'yaru-26.10.3'; source.mkdir(); (source / 'LICENSE_CCBYSA').write_text('license fixture')
    package = stage / 'pkg'; package.mkdir()
    script = r'''source ./PKGBUILD
meson() {
  mkdir -p "$pkgdir/usr/share/themes/Yaru" "$pkgdir/usr/share/icons/Yaru"
  touch "$pkgdir/usr/share/themes/Yaru/generated.css" "$pkgdir/usr/share/icons/Yaru/index.theme"
}
package
'''
    subprocess.run(['bash', '-euc', script], cwd=stage, env=dict(os.environ, pkgdir=str(package)), check=True)
    assert not (package / 'usr/share/themes').exists()
    assert (package / 'usr/share/icons/Yaru/index.theme').is_file()
    assert (package / 'usr/share/licenses/yaru-icon-theme/LICENSE_CCBYSA').is_file()
print('PASS Yaru shared color-generation workaround preserves icon-only packaging')

# Preserve the previous global package that already provides the same schemas.
with patch.object(m.subprocess, 'run', side_effect=[subprocess.CompletedProcess([], 1), subprocess.CompletedProcess([], 0)]), patch.object(m, 'asset', side_effect=AssertionError('must preserve rime-ice-git')):
    assert 'rime-ice-git (preserved)' in m.install_aur({'name': 'rime-ice'}, Path('/unused'), Path('/unused'), 'global')
print('PASS prior rime-ice-git preserved without conflicting install')
