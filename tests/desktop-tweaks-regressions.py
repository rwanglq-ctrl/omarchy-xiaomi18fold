#!/usr/bin/env python3
"""Run fresh/repeated IME seed and helper installation without touching real HOME."""
import os
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'container/install.sh').read_text()
def function(name):
    start = source.index(name + '() {')
    return source[start:source.index('\n}\n', start) + 3]
script = '\n'.join(function(n) for n in ('seed_omarchy_config', 'install_input_defaults', 'install_config_overlay', 'configure_input_and_fonts', 'report_optional_results'))
script = script.replace('/usr/share/rime-data', '$TEST_RIME_DATA')
script += '''
fc-cache() { :; }
rime_deployer() { printf '%s\\n' "$*" >> "$HOME/deploy.log"; return "${TEST_DEPLOY_FAIL:-0}"; }
seed_omarchy_config; install_config_overlay; configure_input_and_fonts; report_optional_results
'''
with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary) / 'home'; home.mkdir()
    upstream = Path(temporary) / 'upstream'
    (upstream / 'config/fcitx5').mkdir(parents=True)
    (upstream / 'config/fcitx5/config').write_text('incorrect upstream fixture')
    (upstream / 'config/hypr').mkdir()
    (upstream / 'config/hypr/input.lua').write_text('upstream keyboard settings')
    (upstream / 'config/hypr/.luarc.json').write_text('{}')
    rime_data = Path(temporary) / 'rime-data'; rime_data.mkdir()
    (rime_data / 'rime_ice.schema.yaml').touch()
    env = dict(os.environ, HOME=str(home), ROOT=str(ROOT), OMARCHY_PATH=str(upstream), TEST_RIME_DATA=str(rime_data))
    subprocess.run(['bash', '-euc', function('seed_omarchy_config') + '\nseed_omarchy_config'], env=env, check=True)
    assert not (home / '.config/hypr/input.lua').exists()
    assert (home / '.config/hypr/.luarc.json').read_text() == '{}'
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    input_file = home / '.config/hypr/input.lua'
    assert 'kb_options = "caps:super,compose:ralt"' in input_file.read_text()
    rime_file = home / '.local/share/fcitx5/rime/default.custom.yaml'
    preset = rime_file.read_text()
    assert preset.index('schema: rime_ice') < preset.index('schema: luna_pinyin_simp')
    assert '--build ' + str(rime_file.parent) in (home / 'deploy.log').read_text()
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert rime_file.read_text() == preset
    legacy_input = (ROOT / 'tests/fixtures/v028/input.lua').read_text()
    legacy_rime = (ROOT / 'tests/fixtures/v028/default.custom.yaml').read_text()
    interim_input = '-- Device defaults only: retain the upstream keyboard layout and modifiers.\nhl.config({ input = { touchpad = { tap_to_click = true } } })\n-- AVF translates touchpad scrolling into oversized wheel events.\nhl.device({ name = "crosvm-virtio-mouse-0", scroll_factor = 0.01 })\n'
    v029_input = (ROOT / 'tests/fixtures/v029/input.lua').read_bytes()
    default_input = (ROOT / 'config/hypr/input.lua').read_bytes()
    baseline = home / '.local/state/omarchy-alarm/input.lua'
    dist = baseline.with_suffix('.lua.dist')
    for previous_input in (legacy_input.encode(), interim_input.encode(), v029_input):
        # No recorded baseline: exercise the exact historical-default allowlist.
        baseline.unlink(missing_ok=True)
        input_file.write_bytes(previous_input)
        subprocess.run(['bash', '-euc', script], env=env, check=True)
        assert input_file.read_text() == (ROOT / 'config/hypr/input.lua').read_text()
    # A current default remains recognized after state loss.
    baseline.unlink()
    result = subprocess.run(['bash', '-euc', script], env=env, check=True, capture_output=True, text=True)
    assert 'Preserved edited/symlinked' not in result.stdout
    assert baseline.read_bytes() == default_input and not dist.exists()
    # Even a one-byte edit of v0.2.9 must be preserved, with a fresh .dist.
    for modified in (v029_input + b' ', v029_input.replace(b'compose:caps', b'compose:ralt')):
        input_file.write_bytes(modified)
        dist.unlink(missing_ok=True)
        subprocess.run(['bash', '-euc', script], env=env, check=True)
        assert input_file.read_bytes() == modified
        assert dist.read_bytes() == default_input
    # A symlink to an exact historical default is still user-owned.
    linked = home / 'linked-input.lua'; linked.write_bytes(v029_input)
    input_file.unlink(); input_file.symlink_to(linked)
    dist.unlink()
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert input_file.is_symlink() and linked.read_bytes() == v029_input
    assert dist.read_bytes() == default_input
    input_file.unlink()
    for previous_rime in (legacy_rime, ''.join(line for line in legacy_rime.splitlines(keepends=True) if '__include:' not in line and 'schema: rime_ice' not in line)):
        rime_file.write_text(previous_rime)
        subprocess.run(['bash', '-euc', script], env=env, check=True)
        assert rime_file.read_text() == preset
    input_file.write_text(legacy_input + '-- custom edit\n')
    rime_file.write_text(legacy_rime + '# custom edit\n')
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert input_file.read_text() == legacy_input + '-- custom edit\n'
    assert rime_file.read_text() == legacy_rime + '# custom edit\n'
    input_file.write_text((ROOT / 'config/hypr/input.lua').read_text())
    rime_file.write_text(preset)
    assert input_file.read_text() == (ROOT / 'config/hypr/input.lua').read_text()
    # The exact stock fallback is upgraded after the optional package succeeds.
    rime_file.write_text(preset.replace('    - schema: rime_ice\n', ''))
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert rime_file.read_text() == preset
    # Deployment failure is nonfatal and prominently repeated in final summary.
    failed = subprocess.run(['bash', '-euc', script], env=dict(env, TEST_DEPLOY_FAIL='1'), check=True, capture_output=True, text=True)
    assert 'WARNING: OPTIONAL ITEMS FAILED' in failed.stderr
    assert 'FAILED (nonfatal) Rime schema deployment' in failed.stderr
    assert 'Shift_L' in (home / '.config/fcitx5/config').read_text()
    assert 'DefaultIM=rime' in (home / '.config/fcitx5/profile').read_text()
    for name in ('portal-autostart', 'lock-ime-reset-autostart', 'fcitx5-autostart'):
        assert os.access(home / '.local/bin' / name, os.X_OK)
    protected = [home / '.config/fcitx5/config', home / '.config/fcitx5/profile', rime_file, input_file]
    for path in protected: path.write_text('user preferences\n')
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert all(p.read_text() == 'user preferences\n' for p in protected)
    protected[0].unlink(); protected[0].symlink_to(home / 'missing-user-file')
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert protected[0].is_symlink() and not protected[0].exists()
    input_file.unlink(); input_file.symlink_to(home / 'missing-input')
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert input_file.is_symlink() and not input_file.exists()
    input_file.unlink()
    input_file.write_text((upstream / 'config/hypr/input.lua').read_text())
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert 'kb_options = "caps:super,compose:ralt"' in input_file.read_text()
    # No schema package: seed usable stock fallback, then upgrade on retry.
    rime_file.unlink(); (rime_data / 'rime_ice.schema.yaml').unlink()
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert 'schema: rime_ice' not in rime_file.read_text()
    (rime_data / 'rime_ice.schema.yaml').touch()
    subprocess.run(['bash', '-euc', script], env=env, check=True)
    assert rime_file.read_text() == preset
print('PASS fresh/repeated input defaults, custom/symlink preservation, Rime fallback upgrade/deployment/failure summary')
# Shift-breaking options, service startup and CPU thread overrides are absent.
config = '\n'.join(p.read_text() for p in (ROOT / 'config/hypr').glob('*.lua'))
for forbidden in ('LP_NUM_THREADS', 'shift:both_capslock_cancel', 'ts-proxy'):
    assert forbidden not in config
for helper in ('remote-access-autostart', 'wayvnc-autostart', 'upgrade-all'):
    assert 'o.launch_on_start("' + helper + '")' not in config
assert 'hl.unbind("SUPER + CTRL + RETURN")' in config
assert 'xdg-terminal-exec herdr' in config
assert 'scroll_factor = 0.01' in config and 'tap_to_click = true' in config
print('PASS generic settings and opt-in boundary')

# Exercise compositor lock transitions: one reset on each unlocked->locked edge.
import socket
with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary); bindir = base / 'bin'; bindir.mkdir()
    runtime = base / 'runtime'; (runtime / 'hypr/test').mkdir(parents=True)
    sock = socket.socket(socket.AF_UNIX); sock.bind(str(runtime / 'hypr/test/.socket.sock'))
    scripts = {
        'omarchy-hyprland-session-locked': 'n=$(cat "$TEST_STATE/step" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$TEST_STATE/step"; case "$n" in 1|2|4) exit 0;; *) exit 1;; esac',
        'fcitx5-remote': 'echo "$*" >> "$TEST_STATE/resets"',
        'sleep': '[ "$(cat "$TEST_STATE/step")" -lt 4 ]',
    }
    for name, body in scripts.items():
        path = bindir / name; path.write_text('#!/bin/sh\n' + body + '\n'); path.chmod(0o755)
    env = dict(os.environ, PATH=str(bindir)+':'+os.environ['PATH'], XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='test', TEST_STATE=str(base))
    subprocess.run(['bash', str(ROOT / 'container/bin/lock-ime-reset-autostart')], env=env, timeout=10)
    assert (base / 'resets').read_text().splitlines() == ['-c', '-c']
    sock.close()
launcher = (ROOT / 'host/bin/arch-hyprland').read_text()
assert 'exec dbus-run-session -- "$@"' in launcher
assert '--setenv=DBUS_SESSION_BUS_ADDRESS=' not in launcher
assert 'DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:?}/bus"' in (ROOT / 'container/bin/host-run').read_text()
print('PASS real lock-probe transitions and private desktop bus / explicit host bus')
