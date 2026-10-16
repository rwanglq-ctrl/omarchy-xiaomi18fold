#!/usr/bin/env python3
"""Offline behavioral regressions for the program-only installer boundary."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from unittest.mock import patch
import urllib.request

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('programs', ROOT / 'lib/tool-programs.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
manifest = json.loads((ROOT / 'packages/tool-programs/manifest.json').read_text())
gold = json.loads((ROOT / 'packages/tool-programs/gold-inventory.json').read_text())
actual = {t['name']: t['version'] for t in manifest['tools'] + manifest['npm_tools']}
assert all(actual.get(name) == version for name, version in gold.items())
assert manifest['tools'][0]['name'] == 'mise'
assert 'node' in {t['name'] for t in manifest['tools']}
assert next(t for t in manifest['npm_tools'] if t['name'] == 'pi')['package'] == '@earendil-works/pi-coding-agent'
for tool in manifest['tools']:
    if tool.get('cn_skip'):
        assert tool['name'] in ('omp', 'cursor-agent') and 'cn_parts' not in tool and 'cn_url' not in tool
        assert tool['url'].startswith(('https://github.com/', 'https://downloads.cursor.com/'))
        continue
    m.check_url(m.cn_url(tool), 'cn')
    assert tool['integrity'].startswith(('sha512-', 'sha256-hex:'))
    for part in tool.get('cn_parts', []):
        m.check_url(part['cn_url'], 'cn')
        assert 0 < part['size'] < 100_000_000
        assert part['integrity'].startswith('sha256-hex:')
for host in ('github.com', 'raw.githubusercontent.com', 'api.github.com', 'registry.npmjs.org', 'ghfast.top', 'downloads.cursor.com'):
    for url in ('https://' + host + '/asset', 'https://registry.npmmirror.com@' + host + '/asset'):
        try:
            m.RedirectPolicy('cn').redirect_request(urllib.request.Request('https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/asset'), None, 302, '', {}, url)
        except ValueError:
            pass
        else:
            raise AssertionError('CN redirected to forbidden host: ' + host)
m.check_url('https://github.com/upstream/file', 'global')
for path in ('/someone/third-party/releases/download/v1/file',
             '/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/../file',
             '/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/%2e%2e%2ffile'):
    try:
        m.check_url('https://gitee.com' + path, 'cn')
    except ValueError:
        pass
    else:
        raise AssertionError('CN accepted a different Gitee release or path traversal')


# Accept Gitee's official release -> owned attachment -> official CDN chain.
release = 'https://gitee.com' + m.GITEE_ASSET_PATH + 'fixture.tar.gz'
attachment = 'https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/attach_files/123/download/fixture.tar.gz'
cdn = 'https://foruda.gitee.com/attach_file/fixture/fixture.tar.gz'
policy = m.RedirectPolicy('cn')
request = policy.redirect_request(urllib.request.Request(release), None, 302, '', {}, attachment)
request = policy.redirect_request(request, None, 302, '', {}, cdn)
assert request.full_url == cdn
try:
    policy.redirect_request(urllib.request.Request('https://registry.npmmirror.com/package'), None, 302, '', {}, cdn)
except ValueError:
    pass
else:
    raise AssertionError('Gitee CDN accepted a redirect from another service')
for url in ('https://gitee.com/third-party/repo/attach_files/123/download/file',
            'https://foruda.gitee.com/not-an-attachment/file',
            'https://foruda.gitee.com/attach_file/../file'):
    try:
        policy.redirect_request(urllib.request.Request(release), None, 302, '', {}, url)
    except ValueError:
        pass
    else:
        raise AssertionError('untrusted attachment redirect accepted')

with tempfile.TemporaryDirectory() as temporary:
    cache = Path(temporary)
    data = b'complete verified asset'
    tool = dict(name='resumable', version='1', url=release, cn_url=release,
                integrity='sha256-hex:' + hashlib.sha256(data).hexdigest())
    part = cache / 'resumable-1.part'
    target = cache / 'resumable-1.asset'
    class Response(io.BytesIO):
        def __init__(self, data, status, headers):
            super().__init__(data); self.status = status; self.headers = headers
    from unittest.mock import Mock
    opener = Mock()
    # A truncated response and subsequent stalls retain bytes across runs.
    opener.open.side_effect = [Response(data[:5], 200, {'Content-Length': str(len(data))}),
                               m.urllib.error.URLError('stall'), m.urllib.error.URLError('stall')]
    with patch.object(m.urllib.request, 'build_opener', return_value=opener), patch.object(m.time, 'sleep'):
        try:
            m.download(tool, cache, 'cn')
        except m.urllib.error.URLError:
            pass
        else:
            raise AssertionError('truncated response accepted')
    assert part.read_bytes() == data[:5] and not target.exists()
    opener.open.side_effect = None
    opener.open.return_value = Response(data[5:], 206, {'Content-Range': f'bytes 5-{len(data)-1}/{len(data)}'})
    with patch.object(m.urllib.request, 'build_opener', return_value=opener):
        assert m.download(tool, cache, 'cn').read_bytes() == data
    assert opener.open.call_args[0][0].get_header('Range') == 'bytes=5-'
    target.unlink()
    # Range ignored: restart safely, without appending duplicate content.
    part.write_bytes(data[:5])
    opener.open.return_value = Response(data, 200, {'Content-Length': str(len(data))})
    with patch.object(m.urllib.request, 'build_opener', return_value=opener):
        assert m.download(tool, cache, 'cn').read_bytes() == data
    target.unlink()
    # A stale oversized prefix rejected by the server must reset before retry.
    part.write_bytes(data[:5])
    opener.open.side_effect = [m.urllib.error.HTTPError(release, 416, 'range rejected', {}, None),
                              Response(data, 200, {'Content-Length': str(len(data))})]
    with patch.object(m.urllib.request, 'build_opener', return_value=opener), patch.object(m.time, 'sleep'):
        assert m.download(tool, cache, 'cn').read_bytes() == data
    assert opener.open.call_args_list[-2][0][0].get_header('Range') == 'bytes=5-'
    assert opener.open.call_args_list[-1][0][0].get_header('Range') is None
    assert all(0 < call.kwargs['timeout'] <= 60 for call in opener.open.call_args_list)
    target.unlink()
    class SSLFailure(Response):
        def read1(self, _size):
            raise m.ssl.SSLError('fixture TLS read failure')
    opener.open.side_effect = [SSLFailure(b'', 200, {}), Response(data, 200, {})]
    with patch.object(m.urllib.request, 'build_opener', return_value=opener), patch.object(m.time, 'sleep'):
        assert m.download(tool, cache, 'cn').read_bytes() == data
    target.unlink()
    opener.open.side_effect = None
    for header, payload in [('bytes 0-4/23', data[5:]),
                            (f'bytes 5-{len(data)-1}/{len(data)}', b'X' * (len(data)-5))]:
        part.write_bytes(data[:5])
        opener.open.return_value = Response(payload, 206, {'Content-Range': header})
        with patch.object(m.urllib.request, 'build_opener', return_value=opener):
            try:
                m.download(tool, cache, 'cn')
            except ValueError:
                pass
            else:
                raise AssertionError('corrupt resume accepted')
        assert not part.exists() and not target.exists()
print('PASS Gitee owned attachment chain, resumable transport, range validation and checksum rejection')

# Multipart CN transport never requests the upstream/full asset. Both each
# fragment and the reconstructed original must pass independent checksums.
with tempfile.TemporaryDirectory() as temporary:
    cache = Path(temporary)
    fragments = [b'first half ', b'second half']
    cn_base = 'https://gitee.com' + m.GITEE_ASSET_PATH
    tool = dict(name='split', version='1', url='https://github.com/upstream/big',
                cn_url=cn_base + 'big', integrity='sha256-hex:' + hashlib.sha256(b''.join(fragments)).hexdigest(),
                cn_parts=[dict(cn_url=cn_base + str(i), integrity='sha256-hex:' + hashlib.sha256(data).hexdigest(), size=len(data))
                          for i, data in enumerate(fragments)])
    requested = []
    def open_part(request, timeout):
        requested.append(request.full_url)
        assert request.full_url in [part['cn_url'] for part in tool['cn_parts']]
        return io.BytesIO(fragments[int(request.full_url.rsplit('/', 1)[1])])
    opener = Mock(); opener.open.side_effect = open_part
    with patch.object(m.urllib.request, 'build_opener', return_value=opener):
        target = m.download(tool, cache, 'cn')
        assert target.read_bytes() == b''.join(fragments)
        assert m.download(tool, cache, 'cn') == target
    assert len(requested) == 2
    target.unlink()
    # Assembled target can be rebuilt offline from individually verified parts.
    with patch.object(m.urllib.request, 'build_opener', side_effect=AssertionError('unexpected network')):
        assert m.download(tool, cache, 'cn').read_bytes() == b''.join(fragments)
    target.unlink()
    second = cache / 'split-part2-1.asset'
    second.unlink()
    opener.open.side_effect = lambda *_args, **_kwargs: io.BytesIO(b'corrupt fragment')
    with patch.object(m.urllib.request, 'build_opener', return_value=opener):
        try:
            m.download(tool, cache, 'cn')
        except ValueError:
            pass
        else:
            raise AssertionError('corrupt split fragment accepted')
    assert not target.exists() and not list(cache.glob('*.part'))
    opener.open.side_effect = m.urllib.error.URLError('missing part')
    with patch.object(m.urllib.request, 'build_opener', return_value=opener), patch.object(m.time, 'sleep'):
        try:
            m.download(tool, cache, 'cn')
        except m.urllib.error.URLError:
            pass
        else:
            raise AssertionError('missing split fragment accepted')
    assert not target.exists()
    # Correct individual fragments are still rejected if concatenation changes.
    opener.open.side_effect = open_part
    tool['integrity'] = 'sha256-hex:' + hashlib.sha256(b'different original').hexdigest()
    with patch.object(m.urllib.request, 'build_opener', return_value=opener):
        try:
            m.download(tool, cache, 'cn')
        except ValueError:
            pass
        else:
            raise AssertionError('reconstructed checksum ignored')
    assert not target.exists() and not list(cache.glob('*.assembled.part'))
print('PASS split CN assets: fragment/original checksums, missing/corrupt rejection, cache reuse, no upstream requests')

# Transient transport errors retry; total elapsed time bounds a slow response.
with tempfile.TemporaryDirectory() as temporary:
    cache = Path(temporary)
    data = b'program'
    fixture = dict(name='retry', version='1', url='https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/asset',
                   cn_url='https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/asset',
                   integrity='sha256-hex:' + hashlib.sha256(data).hexdigest())
    from unittest.mock import Mock
    opener = Mock()
    opener.open.side_effect = [m.urllib.error.URLError('temporary failure'), io.BytesIO(data)]
    with patch.object(m.urllib.request, 'build_opener', return_value=opener), patch.object(m.time, 'sleep'):
        assert m.download(fixture, cache, 'cn').read_bytes() == data
    assert opener.open.call_count == 2
    (cache / 'retry-1.asset').unlink()
    opener.open.side_effect = None
    opener.open.return_value = io.BytesIO(data)
    with patch.object(m.urllib.request, 'build_opener', return_value=opener), patch.object(m.time, 'monotonic', side_effect=[0, 1, 21601, 21602]):
        try:
            m.download(fixture, cache, 'cn')
        except TimeoutError:
            pass
        else:
            raise AssertionError('unbounded slow download')
    assert not list(cache.iterdir()), 'failed download left partial files'

with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary)
    cache = home / 'cache'
    cache.mkdir()
    content = b'verified-program'
    tool = dict(name='fixture', version='1', url='https://github.com/upstream/file',
                cn_url='https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/releases/download/tools-v0.2.9/file', integrity='sha256-hex:' + hashlib.sha256(content).hexdigest())
    requests = []
    class Opener:
        def open(self, req, timeout):
            requests.append(req.full_url)
            return io.BytesIO(content)
    with patch.object(m.urllib.request, 'build_opener', return_value=Opener()):
        asset = m.download(tool, cache, 'cn')
        assert requests == [tool['cn_url']]
        m.download(tool, cache, 'cn')
        assert len(requests) == 1
        asset.write_bytes(b'corrupted')
        m.download(tool, cache, 'cn')
        assert len(requests) == 2 and asset.read_bytes() == content
        tool['integrity'] = 'sha256-hex:' + '0' * 64
        try:
            m.download(tool, cache, 'cn')
        except ValueError as error:
            assert 'checksum mismatch' in str(error)
        else:
            raise AssertionError('bad checksum accepted')
        assert not asset.exists() and not asset.with_suffix('.part').exists()
    archive = cache / 'malicious.tar'
    with tarfile.open(archive, 'w') as tar:
        info = tarfile.TarInfo('../escaped')
        info.size = 1
        tar.addfile(info, io.BytesIO(b'x'))
    try:
        m.unpack(archive, home, 0)
    except ValueError:
        pass
    else:
        raise AssertionError('archive traversal accepted')
    protected = [home / p for p in ('.config/mise/config.toml', '.npmrc', '.claude/settings.json', '.codex/auth.json', '.pi/agent/auth.json', '.config/herdr/config.toml')]
    for path in protected:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('preserve user bytes\n')
    before = {p: p.read_bytes() for p in protected}
    scratch = home / 'scratch'
    scratch.mkdir()
    env = m.isolated_env(home, scratch)
    assert env['HOME'] == str(scratch) and env['npm_config_ignore_scripts'] == 'true'
    assert env['MISE_CEILING_PATHS'] == str(scratch)
    assert 'TOKEN' not in ' '.join(env) and 'API_KEY' not in ' '.join(env)
    program = home / '.local/share/omarchy-tools/fixture/1'
    program.mkdir(parents=True)
    (program / 'fixture').write_text('#!/bin/sh\necho fixture\n')
    old = home / '.local/bin/fixture'
    old.parent.mkdir(parents=True)
    old.write_text('user-command')
    calls = []
    def run(args, **kwargs):
        calls.append(args)
        assert args[1:3] == ['link', '--force']
        assert kwargs['env']['HOME'] == str(scratch)
        return subprocess.CompletedProcess(args, 0)
    with patch.object(m.subprocess, 'run', side_effect=run):
        m.register(home, 'fixture', '1', program, 'fixture', env)
        m.register(home, 'fixture', '1', program, 'fixture', env)
    assert old.is_symlink() and len(list(old.parent.glob('fixture.pre-omarchy-*'))) == 1
    assert next(old.parent.glob('fixture.pre-omarchy-*')).read_text() == 'user-command'
    assert {p: p.read_bytes() for p in protected} == before
    visited = []
    def install(tool, *args):
        visited.append(tool['name'])
        if tool['name'] == 'mise':
            (home / '.local/bin/mise').write_text('fixture')
        if tool['name'] == 'claude':
            raise ValueError('checksum mismatch fixture')
    with patch.object(m.Path, 'home', return_value=home), patch.dict(os.environ, MIRROR='cn'), patch.object(m, 'install_one', side_effect=install), patch.object(m, 'install_npm'):
        m.main()
    assert visited == [t['name'] for t in manifest['tools'] if not t.get('cn_skip')]
    report = (home / '.local/state/omarchy-alarm/tool-programs.txt').read_text()
    assert 'FAILED (nonfatal) claude' in report and 'OK gh' in report and 'OK pi' in report
    assert {p: p.read_bytes() for p in protected} == before
    (home / '.local/bin/mise').unlink()
    with patch.object(m.Path, 'home', return_value=home), patch.dict(os.environ, MIRROR='cn'), patch.object(m, 'install_one', side_effect=ValueError('mise download failed')), patch.object(m, 'install_npm') as npm_install:
        m.main()
        npm_install.assert_not_called()
    report = (home / '.local/state/omarchy-alarm/tool-programs.txt').read_text()
    assert 'FAILED (nonfatal) pi: mise unavailable' in report

lock = json.loads((ROOT / 'packages/tool-programs/pi/package-lock.json').read_text())
for package in lock['packages'].values():
    if 'resolved' in package:
        assert package['resolved'].startswith('https://registry.npmjs.org/')
        assert package['integrity'].startswith('sha512-')
source = (ROOT / 'lib/tool-programs.py').read_text()
assert "['npm', 'ci', '--offline', '--ignore-scripts'" in source
assert "['npm', 'cache', 'add', '--offline', '--ignore-scripts'" in source
container = (ROOT / 'container/install.sh').read_text()
assert 'OMARCHY_PROGRAMS_ONLY=1' in container
assert "step install_tool_programs" in container and 'install_optional_mise' not in container
assert 'herdr|opencode|mise|claude|codex|pi|crush|cursor|gh|omp)' in container
print('PASS tool programs: CN URL/redirect boundary, checksums/cache, archive safety, config preservation, optional failure, offline npm')

assert m.npm_target_compatible({'os': ['!darwin', '!win32'], 'cpu': ['arm64'], 'libc': ['any']})
assert not m.npm_target_compatible({'cpu': ['!arm64']})
assert not m.npm_target_compatible({'os': ['linux'], 'libc': ['musl']})
assert m.npm_target_compatible({})

# Exercise the real npm offline cache/install path with a tiny local dependency.
# No registry access is possible: download is replaced only at the transport seam.
import shutil
missing_real_tools = [name for name in ('npm', 'mise') if not shutil.which(name)]
for name in missing_real_tools:
    print('SKIP real ' + name + ' regression: executable unavailable', flush=True)
if missing_real_tools and os.environ.get('ALARM_REQUIRE_REAL_TOOL_TESTS') == '1':
    raise SystemExit('Release gate requires real npm and mise tests')
if shutil.which('npm'):
    with tempfile.TemporaryDirectory() as temporary:
        base = Path(temporary)
        root, home, scratch = base / 'root', base / 'home', base / 'scratch'
        scratch.mkdir(); (home / '.cache/omarchy-alarm/programs').mkdir(parents=True)
        source = root / 'packages/tool-programs/fixture-npm'; source.mkdir(parents=True)
        package = dict(name='fixture-npm', version='1.0.0', bin={'fixture-npm': 'cli.js'})
        archive = base / 'fixture.tgz'
        with tarfile.open(archive, 'w:gz') as tar:
            for name, content in [('package.json', json.dumps(package)), ('cli.js', '#!/usr/bin/env node\nconsole.log("fixture 1.0.0")\n')]:
                data = content.encode(); info = tarfile.TarInfo('package/' + name); info.size = len(data); info.mode = 0o755
                tar.addfile(info, io.BytesIO(data))
        import base64
        integrity = 'sha512-' + base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()
        project = dict(name='fixture-project', version='1.0.0', dependencies={'fixture-npm': '1.0.0'})
        (source / 'package.json').write_text(json.dumps(project))
        (source / 'package-lock.json').write_text(json.dumps(dict(name='fixture-project', version='1.0.0', lockfileVersion=3,
            packages={'': project, 'node_modules/fixture-npm': dict(version='1.0.0', resolved='https://registry.npmjs.org/fixture-npm/-/fixture-npm-1.0.0.tgz', integrity=integrity, bin=package['bin'])})))
        # A complete lock retains unavailable off-target optional packages.
        # Only the ARM64/glibc fixture is cached; real offline npm must succeed.
        target = dict(name='fixture-native-arm64', version='1.0.0', os=['linux'], cpu=['arm64'], libc=['glibc'])
        target_archive = base / 'target.tgz'
        with tarfile.open(target_archive, 'w:gz') as tar:
            data = json.dumps(target).encode(); info = tarfile.TarInfo('package/package.json'); info.size = len(data); info.mode = 0o644
            tar.addfile(info, io.BytesIO(data))
        target_integrity = 'sha512-' + base64.b64encode(hashlib.sha512(target_archive.read_bytes()).digest()).decode()
        project['optionalDependencies'] = {'fixture-native-arm64': '1.0.0', 'fixture-native-windows': '1.0.0', 'fixture-native-musl': '1.0.0'}
        (source / 'package.json').write_text(json.dumps(project))
        fixture_lock = json.loads((source / 'package-lock.json').read_text())
        fixture_lock['packages'][''] = project
        for name, metadata in [('fixture-native-arm64', target),
                               ('fixture-native-windows', dict(os=['win32'], cpu=['x64'])),
                               ('fixture-native-musl', dict(os=['linux'], cpu=['arm64'], libc=['musl']))]:
            fixture_lock['packages']['node_modules/' + name] = dict(metadata, version='1.0.0', optional=True,
                resolved='https://registry.npmjs.org/' + name + '/-/package-1.0.0.tgz', integrity=target_integrity)
        fixture_lock['packages']['node_modules/fixture-npm/node_modules/fixture-native-arm64'] = fixture_lock['packages']['node_modules/fixture-native-arm64'].copy()
        (source / 'package-lock.json').write_text(json.dumps(fixture_lock))
        downloads = []
        def fixture_download(tool, cache, mirror):
            downloads.append(tool['url'])
            if 'fixture-native-arm64/' in tool['url']:
                return target_archive
            if 'fixture-npm/' in tool['url']:
                return archive
            raise AssertionError('downloaded incompatible optional package: ' + tool['url'])
        tool = dict(name='fixture-npm', version='1.0.0', package='fixture-npm', entry='cli.js')
        env = m.isolated_env(home, scratch)
        with patch.object(m, 'ROOT', root), patch.object(m, 'download', side_effect=fixture_download), patch.object(m, 'register'):
            m.install_npm(tool, home, 'cn', env)
            m.install_npm(tool, home, 'cn', env)
        prefixes = list((home / '.local/share/omarchy-tools/fixture-npm').iterdir())
        assert len(prefixes) == 1
        assert len(downloads) == 2
        assert (prefixes[0] / 'node_modules/fixture-native-arm64/package.json').is_file()
        assert not (prefixes[0] / 'node_modules/fixture-native-windows').exists()
        assert not (prefixes[0] / 'node_modules/fixture-native-musl').exists()
        result = subprocess.check_output(['node', str(prefixes[0] / 'node_modules/fixture-npm/cli.js')], text=True)
        assert result.strip() == 'fixture 1.0.0'
        assert not (home / '.config').exists()
    print('PASS real npm offline install: ARM64 optional present, Windows/musl omitted, idempotent rerun')

if shutil.which('mise'):
    with tempfile.TemporaryDirectory() as temporary:
        home = Path(temporary)
        scratch = home / '.cache/programs/isolated'; scratch.mkdir(parents=True)
        # A broken project config above the ceiling must never be evaluated.
        config = home / 'mise.toml'; config.write_text('not valid toml !!!\n')
        # The persistent cache ceiling must also never enter config discovery.
        (scratch.parent / 'mise.toml').write_text('not valid toml !!!\n')
        (scratch / 'mise.toml').write_text('not valid toml !!!\n')
        (home / '.local/bin').mkdir(parents=True)
        (home / '.local/bin/mise').symlink_to(shutil.which('mise'))
        prefix = home / '.local/share/omarchy-tools/fixture/1'; prefix.mkdir(parents=True)
        (prefix / 'fixture').write_text('#!/bin/sh\necho fixture\n')
        env = m.isolated_env(home, scratch)
        previous_cwd = Path.cwd()
        try:
            os.chdir(home)  # Removing register's isolated cwd must fail this test.
            m.register(home, 'fixture', '1', prefix, 'fixture', env)
            m.register(home, 'fixture', '1', prefix, 'fixture', env)
        finally:
            os.chdir(previous_cwd)
        assert config.read_text() == 'not valid toml !!!\n'
        assert (home / '.local/share/mise/installs/http-fixture/1').is_symlink()
    print('PASS real mise registration with untrusted parent configuration, repeated without config writes')

# Failed optional items must remain visible at the end, including a helper
# crash before it writes its own report. A later successful retry clears them.
with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary)
    source = (ROOT / 'container/install.sh').read_text()
    functions = source[source.index('install_tool_programs() {'):source.index('\nif ! $dry_run; then')]
    script = functions + r'''
mkdir -p "$HOME/.local/state/omarchy-alarm"
printf 'FAILED (nonfatal) yay: fixture checksum failure\n' > "$HOME/.local/state/omarchy-alarm/aur-extras.txt"
python3() { return 7; }
install_tool_programs
report_optional_results
echo DESKTOP-CONTINUES
'''
    result = subprocess.run(['bash', '-euc', script], env=dict(os.environ, HOME=str(home), ROOT=str(ROOT)),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    assert 'DESKTOP-CONTINUES' in result.stdout
    assert 'OPTIONAL ITEMS FAILED' in result.stderr
    assert 'yay: fixture checksum failure' in result.stderr
    assert 'AI program provisioning: helper failed' in result.stderr
    for report in (home / '.local/state/omarchy-alarm').glob('*.txt'):
        report.write_text('OK fixture\n')
    result = subprocess.run(['bash', '-euc', functions + '\nreport_optional_results'],
                            env=dict(os.environ, HOME=str(home)), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    assert 'FAILED' not in result.stdout + result.stderr
print('PASS final optional summary: named failures, helper crash, desktop continuation, clean retry')

for name in ('omp', 'cursor-agent'):
    # Option C: no download, cache reuse, mise registration or config writes for CN skipped tools.
    with tempfile.TemporaryDirectory() as temporary:
        home = Path(temporary)
        with patch.object(m.Path, 'home', return_value=home), patch.dict(os.environ, MIRROR='cn'), patch.object(sys, 'argv', ['tool-programs.py', '--only', name]), patch.object(m, 'install_one', side_effect=AssertionError('CN skipped tools must never install')), patch.object(m, 'install_npm', side_effect=AssertionError('only omp requested')):
            m.main()
        report = (home / '.local/state/omarchy-alarm/tool-programs.txt').read_text()
        assert 'SKIPPED (CN policy) ' + name in report and 'MIRROR=global' in report and '--only ' + name in report
        assert not (home / '.config').exists()
        with patch.object(m.Path, 'home', return_value=home), patch.dict(os.environ, MIRROR='global'), patch.object(sys, 'argv', ['tool-programs.py', '--only', name]), patch.object(m, 'install_one') as install:
            (home / '.local/bin').mkdir(parents=True, exist_ok=True)
            (home / '.local/bin/mise').touch()
            m.main()
            assert install.call_count == 1 and install.call_args.args[0]['name'] == name
    print('PASS CN skip is explicit and network-free; global retains upstream install: ' + name)

# Reviewed per-part base changes scope to exactly that release/repository.
overflow = dict(cn_base_url='https://gitee.com/zenbardofsuhe/fixture-tools/releases/download/tools-v0.2.9/', asset_name='fixture.part002')
url = m.cn_url(overflow)
path = '/zenbardofsuhe/fixture-tools/releases/download/tools-v0.2.9/'
m.check_url(url, 'cn', asset_path=path)
for url in ('https://gitee.com:8443' + path + 'fixture', 'https://gitee.com/zenbardofsuhe/fixture-tools/attach_files/123/download/..', 'https://gitee.com' + m.GITEE_ASSET_PATH + 'fixture'):
    try: m.check_url(url, 'cn', redirect=True, asset_path=path)
    except ValueError: pass
    else: raise AssertionError('unsafe or wrong-repository URL accepted: ' + url)
print('PASS scoped asset base, port and traversal guards')
