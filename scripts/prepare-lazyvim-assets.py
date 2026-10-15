#!/usr/bin/env python3
"""Prepare a source-only LazyVim snapshot from a reviewed, locked staging tree.

Usage: prepare-lazyvim-assets.py STAGE (containing config/nvim and data/nvim/lazy).
The operator first syncs upstream LazyVim/starter in an isolated STAGE. This
script checks each plugin HEAD against lazy-lock.json and exports committed
files only, excluding git credentials, build outputs and host-native binaries.
"""
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
stage = Path(sys.argv[1])
config = stage / 'config/nvim'
lock = json.loads((config / 'lazy-lock.json').read_text())
output = Path('/tmp/v029-assets/lazyvim-v0.2.9-sources.tar.gz')
manifest_path = ROOT / 'packages/desktop-extras/lazyvim-assets.json'
if output.exists() and manifest_path.exists():
    expected = json.loads(manifest_path.read_text())[0]['integrity'].split(':')[1]
    if hashlib.sha256(output.read_bytes()).hexdigest() != expected:
        raise ValueError('Existing LazyVim asset checksum mismatch')
    print('Verified existing', output)
    sys.exit(0)
provenance = []
with tempfile.TemporaryDirectory() as td:
    bundle = Path(td)
    shutil.copytree(config, bundle / 'config', ignore=shutil.ignore_patterns('.git'))
    for name, pin in lock.items():
        source = stage / 'data/nvim/lazy' / name
        head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
        if head != pin['commit']:
            raise ValueError('lock mismatch: ' + name)
        url = subprocess.check_output(['git', '-C', str(source), 'remote', 'get-url', 'origin'], text=True).strip()
        archive = subprocess.check_output(['git', '-C', str(source), 'archive', 'HEAD'])
        target = bundle / 'plugins' / name
        target.mkdir(parents=True)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(target, filter='data')
        provenance.append(dict(name=name, upstream=url, commit=head))
    (bundle / 'plugins.json').write_text(json.dumps(provenance, indent=2) + '\n')
    (bundle / 'config/lua/config/lazy.lua').write_text('''-- Pinned source plugins; installation and update checks are offline.
local root = "@PLUGIN_ROOT@"
vim.opt.rtp:prepend(root .. "/lazy.nvim")
require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  dev = { path = root, patterns = { "" }, fallback = false },
  install = { missing = false, colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = false },
  change_detection = { enabled = false, notify = false },
})
''')
    (bundle / 'config/lua/plugins/omarchy-offline.lua').write_text('''-- Extra language parsers, servers and formatters require explicit user setup.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "nvim-treesitter/nvim-treesitter", build = false,
    opts = function(_, opts) opts.ensure_installed = {}; opts.auto_install = false end },
  { "saghen/blink.cmp", build = false, opts = { fuzzy = { implementation = "lua" } } },
}
''')
    # Dereference repository symlinks into source files so the installer can use
    # its strict no-links archive extractor. Never include .git or build outputs.
    with tarfile.open(output, 'w:gz', dereference=True) as tar:
        for child in sorted(bundle.iterdir()):
            tar.add(child, arcname=child.name)
manifest = [dict(name='LazyVim', version='v0.2.9', file=output.name,
                 integrity='sha256-hex:' + hashlib.sha256(output.read_bytes()).hexdigest())]
(ROOT / 'packages/desktop-extras/lazyvim-assets.json').write_text(json.dumps(manifest, indent=2) + '\n')
(ROOT / 'packages/desktop-extras/lazyvim-plugins.json').write_text(json.dumps(provenance, indent=2) + '\n')
print(manifest[0]['integrity'], output)
