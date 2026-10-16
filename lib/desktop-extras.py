#!/usr/bin/env python3
"""Pinned AUR sources and an absent-only, offline LazyVim starter."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('tool_programs', ROOT / 'lib/tool-programs.py')
programs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(programs)
BASE = 'https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/'


def asset(item, cache, mirror):
    return programs.download(dict(item, url=BASE + item['file'], cn_url=BASE + item['file']), cache, mirror)


def normalize_source_arrays(stage):
    # Source bundles already fold every architecture's selected input into the
    # checksum-verified top-level source/sha256sums arrays. makepkg distinguishes
    # declared-empty arrays from unset variables; remove obsolete declarations
    # after verifying/unpacking the published bundle, without changing its bytes.
    with (stage / 'PKGBUILD').open('a') as recipe:
        recipe.write('\n# All bundled inputs are in source/sha256sums above.\n'
                     'unset source_aarch64 source_x86_64 sha256sums_aarch64 '
                     'sha256sums_x86_64 sha512sums sha512sums_aarch64 sha512sums_x86_64\n')


def fix_yaru_icon_recipe(stage):
    # Yaru 26.10.3 icons consume GTK-generated color definitions even with GTK
    # disabled upstream. Generate those prerequisites, then package icons only.
    recipe = stage / 'PKGBUILD'
    text = recipe.read_text()
    install = 'DESTDIR="$pkgdir" meson install -C build --no-rebuild'
    if text.count('-Dgtk=false') != 1 or text.count(install) != 1:
        raise ValueError('unexpected pinned Yaru recipe; refusing an ambiguous edit')
    text = text.replace('-Dgtk=false', '-Dgtk=true')
    text = text.replace(install, install + '\n  rm -rf -- "${pkgdir:?}/usr/share/themes"')
    recipe.write_text(text)


def install_aur(item, home, cache, mirror):
    if subprocess.run(['pacman', '-Q', item['name']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        return 'already installed (preserved)'
    if item['name'] == 'rime-ice' and subprocess.run(['pacman', '-Q', 'rime-ice-git'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        return 'already provided by rime-ice-git (preserved)'
    archive = asset(item, cache, mirror)
    with tempfile.TemporaryDirectory(prefix='aur-', dir=cache) as temporary:
        stage = Path(temporary)
        programs.unpack(archive, stage, 0)
        normalize_source_arrays(stage)
        if item['name'] == 'yaru-icon-theme':
            fix_yaru_icon_recipe(stage)
        env = dict(os.environ)
        env['CARGO_HOME'] = str(stage / '.cargo')
        env['GOPATH'] = str(stage / '.go')
        env['GOTOOLCHAIN'] = 'local'
        env['CARGO_NET_GIT_FETCH_WITH_CLI'] = 'true'
        if mirror == 'cn':
            # No fallback to upstream: registry checksums remain cargo.lock's.
            (stage / '.cargo').mkdir()
            (stage / '.cargo/config.toml').write_text('[source.crates-io]\nreplace-with = "rsproxy"\n[source.rsproxy]\nregistry = "sparse+https://rsproxy.cn/index/"\n')
            env.update(GOPROXY='https://goproxy.cn', GOSUMDB='sum.golang.google.cn', GOPRIVATE='', GONOPROXY='none', GONOSUMDB='none')
            # Vendored releases have no Cargo git dependencies. Deny any future
            # git fetch during makepkg rather than silently adding GitHub access.
            wrappers = stage / '.network-guard'
            wrappers.mkdir()
            (wrappers / 'git').write_text('#!/bin/sh\necho "CN source build refuses git network access" >&2\nexit 1\n')
            (wrappers / 'git').chmod(0o755)
            env['PATH'] = str(wrappers) + ':' + env['PATH']
        subprocess.run(['makepkg', '--verifysource', '--ignorearch'], cwd=stage, env=env, check=True, timeout=120)
        subprocess.run(['makepkg', '--ignorearch', '--syncdeps', '--install', '--needed', '--noconfirm', '--nocheck'], cwd=stage, env=env, check=True, timeout=7200)
    return 'installed from verified source bundle'


def install_lazyvim(item, home, cache, mirror):
    config = home / '.config/nvim'
    if config.exists() or config.is_symlink():
        return 'existing ~/.config/nvim preserved'
    archive = asset(item, cache, mirror)
    with tempfile.TemporaryDirectory(prefix='lazyvim-', dir=cache) as temporary:
        stage = Path(temporary)
        programs.unpack(archive, stage, 0)
        lock = json.loads((stage / 'config/lazy-lock.json').read_text())
        provenance = json.loads((stage / 'plugins.json').read_text())
        pins = {plugin['name']: plugin['commit'] for plugin in provenance}
        if pins != {name: pin['commit'] for name, pin in lock.items()}:
            raise ValueError('LazyVim plugin snapshot does not match lockfile')
        for name in pins:
            if not (stage / 'plugins' / name).is_dir():
                raise ValueError('LazyVim plugin missing: ' + name)
        config.parent.mkdir(parents=True, exist_ok=True)
        plugins = home / '.local/share/omarchy-lazyvim'
        plugins.parent.mkdir(parents=True, exist_ok=True)
        versioned = plugins / item['version']
        if not versioned.exists():
            plugins.mkdir(exist_ok=True)
            (stage / 'plugins').rename(versioned)
        # Generated starter resolves only our pinned local plugin snapshot.
        lazy = stage / 'config/lua/config/lazy.lua'
        lazy.write_text(lazy.read_text().replace('@PLUGIN_ROOT@', str(versioned)))
        if config.exists() or config.is_symlink():
            return 'existing ~/.config/nvim preserved'
        (stage / 'config').rename(config)
    return 'installed starter and pinned plugins; automatic network updates disabled'


def main():
    home = Path.home()
    mirror = os.environ.get('MIRROR', 'global')
    if mirror not in ('cn', 'global'):
        raise ValueError('resolve MIRROR before desktop extras')
    cache = home / '.cache/omarchy-alarm/desktop-extras'
    cache.mkdir(parents=True, exist_ok=True)
    kind = sys.argv[1]
    filename = 'aur-assets.json' if kind == 'aur' else 'lazyvim-assets.json'
    items = json.loads((ROOT / 'packages/desktop-extras' / filename).read_text())
    results = []
    for item in items:
        try:
            detail = (install_aur if kind == 'aur' else install_lazyvim)(item, home, cache, mirror)
            result = 'OK ' + item['name'] + ': ' + detail
        except Exception as error:
            result = 'FAILED (nonfatal) ' + item['name'] + ': ' + str(error)
        print(result, flush=True)
        results.append(result)
    state = home / '.local/state/omarchy-alarm'
    state.mkdir(parents=True, exist_ok=True)
    (state / (kind + '-extras.txt')).write_text('\n'.join(results) + '\n')


if __name__ == '__main__':
    main()
