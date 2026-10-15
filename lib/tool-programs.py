#!/usr/bin/env python3
"""Install pinned aarch64 programs; never provision tool configuration or identity."""
import argparse
import base64
import concurrent.futures
import hashlib
import http.client
import json
import os
import re
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CN_HOSTS = {'registry.npmmirror.com', 'cdn.npmmirror.com', 'gitee.com', 'foruda.gitee.com'}
GITEE_ASSET_PATH = '/zenbardofsuhe/omarchy-xiaomipad9pm/releases/download/tools-v0.2.9/'


def cn_url(asset):
    """A reviewed manifest may select a different operator-owned release per file."""
    if 'cn_base_url' not in asset:
        return asset['cn_url']
    base = asset['cn_base_url']
    parsed = urllib.parse.urlsplit(base)
    if (parsed.scheme != 'https' or parsed.netloc != 'gitee.com' or parsed.query or parsed.fragment
            or not re.fullmatch(r'/zenbardofsuhe/[a-zA-Z0-9_-]+/releases/download/tools-v0\.2\.9/', parsed.path)):
        raise ValueError('CN asset base must be an operator-owned Gitee tools release')
    filename = asset.get('asset_name', asset.get('file', ''))
    if not re.fullmatch(r'[A-Za-z0-9._-]+', filename) or filename in ('.', '..'):
        raise ValueError('invalid CN asset filename')
    return base + filename


def check_url(url, mirror, redirect=False, asset_path=GITEE_ASSET_PATH):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError('only credential-free HTTPS downloads are allowed')
    if mirror == 'cn' and parsed.hostname not in CN_HOSTS:
        raise ValueError('CN download host refused: ' + str(parsed.hostname))
    if mirror == 'cn' and parsed.hostname == 'gitee.com':
        path = urllib.parse.unquote(parsed.path)
        if '..' in path.split('/'):
            raise ValueError('CN Gitee path traversal refused')
        filename = path.removeprefix(asset_path)
        release = path.startswith(asset_path) and filename and '/' not in filename and filename not in ('.', '..')
        attachment = redirect and re.fullmatch(re.escape(asset_path.split('/releases/')[0]) + r'/attach_files/[0-9]+/download/[^/]+', path)
        if not release and not attachment:
            raise ValueError('CN Gitee download must use the operator-owned tools-v0.2.9 release')
    if mirror == 'cn' and parsed.hostname == 'foruda.gitee.com':
        path = urllib.parse.unquote(parsed.path)
        if not redirect or not path.startswith('/attach_file/') or '..' in path.split('/'):
            raise ValueError('CN Gitee CDN requires an attachment redirect')


class RedirectPolicy(urllib.request.HTTPRedirectHandler):
    def __init__(self, mirror, asset_path=GITEE_ASSET_PATH):
        self.mirror = mirror
        self.asset_path = asset_path

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_url(newurl, self.mirror, redirect=True, asset_path=self.asset_path)
        if self.mirror == 'cn' and urllib.parse.urlsplit(newurl).hostname == 'foruda.gitee.com':
            if urllib.parse.urlsplit(req.full_url).hostname not in ('gitee.com', 'foruda.gitee.com'):
                raise ValueError('Gitee CDN redirect must originate from Gitee')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def verify(path, integrity):
    algorithm, expected = integrity.split('-', 1)
    if algorithm not in ('sha256', 'sha512'):
        raise ValueError('unsupported checksum')
    digest = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    actual = 'hex:' + digest.hexdigest() if expected.startswith('hex:') else base64.b64encode(digest.digest()).decode()
    if actual != expected:
        raise ValueError('checksum mismatch: ' + path.name)


def download(tool, cache, mirror):
    url = cn_url(tool) if mirror == 'cn' else tool['url']
    asset_path = urllib.parse.urlsplit(tool['cn_base_url']).path if mirror == 'cn' and 'cn_base_url' in tool else GITEE_ASSET_PATH
    check_url(url, mirror, asset_path=asset_path)
    target = cache / (tool['name'] + '-' + tool['version'] + '.asset')
    if target.exists():
        try:
            verify(target, tool['integrity'])
            return target
        except ValueError:
            target.unlink()
    if mirror == 'cn' and tool.get('cn_parts'):
        assembly = target.with_suffix('.assembled.part')
        try:
            with assembly.open('wb') as output:
                for index, part in enumerate(tool['cn_parts'], 1):
                    piece = download(dict(part, name=tool['name'] + '-part' + str(index),
                                          version=tool['version'], url=part['cn_url'],
                                          cn_url=part['cn_url'], integrity=part['integrity']), cache, mirror)
                    # Recheck at the assembly boundary, including warm caches.
                    verify(piece, part['integrity'])
                    if piece.stat().st_size != part['size']:
                        raise ValueError('split asset size mismatch')
                    with piece.open('rb') as source:
                        shutil.copyfileobj(source, output)
            verify(assembly, tool['integrity'])
            assembly.replace(target)
        finally:
            assembly.unlink(missing_ok=True)
        return target
    print('Downloading ' + tool['name'] + ' ' + tool['version'] + ' from ' + urllib.parse.urlsplit(url).hostname, flush=True)
    opener = urllib.request.build_opener(RedirectPolicy(mirror, asset_path))
    part = target.with_suffix('.part')
    # A slow link can resume across retries and installer runs. Only a complete
    # hash-verified asset is published; range headers are never trusted blindly.
    deadline = time.monotonic() + 6 * 60 * 60
    if part.exists():
        try:
            verify(part, tool['integrity'])
            part.replace(target)
            return target
        except ValueError:
            pass  # An incomplete prefix is expected here.
    for attempt in range(3):
        try:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('download exceeded six hour deadline; partial saved')
            offset = part.stat().st_size if part.exists() else 0
            headers = {'User-Agent': 'curl/8.0'}
            if offset:
                headers['Range'] = 'bytes=' + str(offset) + '-'
            with opener.open(urllib.request.Request(url, headers=headers), timeout=min(60, remaining)) as response:
                status = getattr(response, 'status', 200)
                response_headers = getattr(response, 'headers', {})
                expected = None
                if status == 206:
                    match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', response_headers.get('Content-Range', ''))
                    if not match:
                        raise ValueError('invalid Content-Range')
                    first, last, total = map(int, match.groups())
                    if first != offset or last < first or last >= total:
                        raise ValueError('resume response does not match saved prefix')
                    expected = total
                    mode = 'ab'
                elif status == 200:
                    # A server may ignore Range. Restart instead of appending.
                    mode = 'wb'
                    if response_headers.get('Content-Length'):
                        expected = int(response_headers['Content-Length'])
                else:
                    raise ValueError('unexpected download response status')
                with part.open(mode) as output:
                    read = getattr(response, 'read1', response.read)
                    while True:
                        if time.monotonic() >= deadline:
                            raise TimeoutError('download exceeded six hour deadline; partial saved')
                        chunk = read(1024 * 1024)
                        if not chunk:
                            break
                        output.write(chunk)
                if expected is not None and part.stat().st_size != expected:
                    raise urllib.error.URLError('incomplete response; partial saved')
            verify(part, tool['integrity'])
            part.replace(target)
            break
        except urllib.error.HTTPError as error:
            if error.code == 416:
                part.unlink(missing_ok=True)  # Invalid/obsolete saved prefix.
            if attempt == 2 or time.monotonic() >= deadline:
                raise
            time.sleep(attempt + 1)
        except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException, ssl.SSLError):
            if part.exists() and part.stat().st_size == 0:
                part.unlink()
            if attempt == 2 or time.monotonic() >= deadline:
                raise
            print('Retrying ' + tool['name'] + ' with saved partial download', flush=True)
            time.sleep(attempt + 1)
        except ValueError:
            part.unlink(missing_ok=True)
            raise
    return target


def unpack(archive, destination, strip):
    # Refuse traversal, devices and links. These upstream program archives only
    # need directories and regular files; nothing may escape the staging prefix.
    with tarfile.open(archive) as tar:
        for member in tar:
            parts = Path(member.name).parts
            if member.name.startswith('/') or '..' in parts:
                raise ValueError('unsafe archive member')
            parts = parts[strip:]
            if not parts:
                continue
            path = destination.joinpath(*parts)
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                path.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, path.open('wb') as output:
                    shutil.copyfileobj(source, output)
                path.chmod(member.mode & 0o755)
            elif member.issym() or member.islnk():
                # Node/npm dependencies are handled by npm, not these archives.
                raise ValueError('archive link refused: ' + member.name)
            else:
                raise ValueError('non-program archive member refused')


def isolated_env(home, scratch):
    # Do not read the desktop user's npm/mise config, credentials, plugins or
    # project hooks. mise link only registers already installed program prefixes.
    env = {key: os.environ[key] for key in ('PATH', 'LANG', 'LC_ALL', 'SSL_CERT_FILE', 'SSL_CERT_DIR') if key in os.environ}
    env.update(HOME=str(scratch), XDG_CONFIG_HOME=str(scratch / 'config'),
               XDG_CACHE_HOME=str(scratch / 'cache'), XDG_DATA_HOME=str(scratch / 'data'),
               MISE_CONFIG_DIR=str(scratch / 'config/mise'), MISE_SYSTEM_CONFIG_DIR=str(scratch / 'system'),
               MISE_GLOBAL_CONFIG_FILE=str(scratch / 'config/mise/config.toml'), MISE_DATA_DIR=str(home / '.local/share/mise'),
               MISE_CACHE_DIR=str(scratch / 'cache/mise'), MISE_STATE_DIR=str(scratch / 'state/mise'),
               MISE_CEILING_PATHS=str(scratch), MISE_PARANOID='1', MISE_YES='1',
               npm_config_userconfig=str(scratch / 'user.npmrc'), npm_config_globalconfig=str(scratch / 'global.npmrc'),
               npm_config_ignore_scripts='true', npm_config_audit='false', npm_config_fund='false')
    return env


def publish_command(home, name, target):
    command = home / '.local/bin' / name
    command.parent.mkdir(parents=True, exist_ok=True)
    owned = command.is_symlink() and str(command.resolve()).startswith(str(home / '.local/share/omarchy-tools') + '/')
    if command.exists() or command.is_symlink():
        if owned:
            command.unlink()
        else:
            # Preserve an existing user command instead of silently replacing it.
            backup = command.with_name(name + '.pre-omarchy-' + str(time.time_ns()))
            command.rename(backup)
            print('Preserved existing command: ' + str(backup), flush=True)
    command.symlink_to(target)


def register(home, name, version, prefix, entry, env):
    bindir = prefix / 'bin'
    bindir.mkdir(exist_ok=True)
    command = bindir / name
    source = prefix / entry
    if not source.is_file():
        raise ValueError('missing program entry: ' + entry)
    source.chmod(source.stat().st_mode | 0o755)
    if source != command and not command.exists():
        command.symlink_to(os.path.relpath(source, bindir))
    if name != 'mise':
        # Explicit backend IDs avoid registry aliases/plugins and version lookup.
        subprocess.run([str(home / '.local/bin/mise'), 'link', '--force',
                        'http:' + name + '@' + version, str(prefix)],
                       env=env, cwd=env['HOME'], stdin=subprocess.DEVNULL, check=True, timeout=60)
    publish_command(home, name, command)


def install_one(tool, home, cache, mirror, env):
    name, version = tool['name'], tool['version']
    base = home / '.local/share/omarchy-tools' / name
    base.mkdir(parents=True, exist_ok=True)
    prefix = base / version
    identity = hashlib.sha256(json.dumps(tool, sort_keys=True).encode()).hexdigest()
    marker = prefix / '.omarchy-program'
    if not marker.exists() or marker.read_text().strip() != identity:
        asset = download(tool, cache, mirror)
        with tempfile.TemporaryDirectory(prefix='.stage-', dir=base) as temporary:
            stage = Path(temporary) / 'program'
            stage.mkdir()
            if tool['format'] == 'binary':
                target = stage / tool['entry']
                target.parent.mkdir(parents=True)
                shutil.copyfile(asset, target)
            else:
                unpack(asset, stage, tool['strip'])
            if not (stage / tool['entry']).is_file():
                raise ValueError('missing program entry: ' + tool['entry'])
            (stage / '.omarchy-program').write_text(identity + '\n')
            if prefix.exists():
                # Keep the former prefix recoverable if a manifest is revised.
                prefix.rename(base / (version + '.previous-' + str(time.time_ns())))
            stage.rename(prefix)
    register(home, name, version, prefix, tool['entry'], env)
    for alias in tool.get('aliases', []):
        publish_command(home, alias, prefix / 'bin' / name)


def npm_target_compatible(package):
    """Match npm platform allow/deny lists for our fixed ALARM target."""
    for field, target in (('os', 'linux'), ('cpu', 'arm64'), ('libc', 'glibc')):
        allowed = package.get(field)
        if not allowed:
            continue
        if isinstance(allowed, str):
            allowed = [allowed]
        if allowed == ['any']:
            continue
        if '!' + target in allowed:
            return False
        positive = [entry for entry in allowed if not entry.startswith('!')]
        if positive and target not in positive:
            return False
    return True


def install_npm(tool, home, mirror, env):
    name, version = tool['name'], tool['version']
    base = home / '.local/share/omarchy-tools' / name
    base.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'packages/tool-programs' / name
    lock_text = (source / 'package-lock.json').read_text()
    lock = json.loads(lock_text)
    for package in lock['packages'].values():
        if 'resolved' in package:
            url = urllib.parse.urlsplit(package['resolved'])
            if url.scheme != 'https' or url.hostname != 'registry.npmjs.org' or not package.get('integrity', '').startswith('sha512-'):
                raise ValueError('npm dependency must have a pinned npm tarball and SHA512')
    fingerprint = hashlib.sha256(lock_text.encode()).hexdigest()
    prefix = base / (version + '-' + fingerprint[:12])
    if not (prefix / '.omarchy-program').exists():
        with tempfile.TemporaryDirectory(prefix='.stage-', dir=base) as temporary:
            stage = Path(temporary) / 'program'
            stage.mkdir()
            shutil.copyfile(source / 'package.json', stage / 'package.json')
            if mirror == 'cn':
                lock_text = lock_text.replace('https://registry.npmjs.org/', 'https://registry.npmmirror.com/')
            (stage / 'package-lock.json').write_text(lock_text)
            registry = 'https://registry.npmmirror.com' if mirror == 'cn' else 'https://registry.npmjs.org'
            # npm itself follows redirects without a host allowlist. Fetch every
            # locked tarball ourselves, verify SHA512, then run npm fully offline.
            cache = home / '.cache/omarchy-alarm/programs'
            dependencies = []
            pinned_urls = {}
            for package in lock['packages'].values():
                if 'resolved' not in package:
                    continue
                # npm skips incompatible optional native packages; do not make
                # their unrelated tarball availability a prerequisite in CN.
                if package.get('optional') is True and not npm_target_compatible(package):
                    continue
                previous = pinned_urls.get(package['resolved'])
                if previous:
                    if previous != package['integrity']:
                        raise ValueError('conflicting checksums for one npm tarball URL')
                    continue
                pinned_urls[package['resolved']] = package['integrity']
                dependencies.append(dict(name='npm-' + hashlib.sha256(package['resolved'].encode()).hexdigest()[:20],
                    version=package['version'], url=package['resolved'],
                    cn_url=package['resolved'].replace('https://registry.npmjs.org/', 'https://registry.npmmirror.com/'),
                    integrity=package['integrity']))
            with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
                assets = list(pool.map(lambda tool: download(tool, cache, mirror), dependencies))
            tarballs = Path(env['HOME']) / ('npm-tarballs-' + name)
            tarballs.mkdir(exist_ok=True)
            npm_assets = []
            for asset in assets:
                local = tarballs / (asset.stem + '.tgz')
                local.symlink_to(asset)
                npm_assets.append(local)
            npm_env = dict(env, npm_config_registry=registry, npm_config_update_notifier='false',
                           npm_config_os='linux', npm_config_cpu='arm64', npm_config_libc='glibc')
            subprocess.run(['npm', 'cache', 'add', '--offline', '--ignore-scripts', *map(str, npm_assets)],
                           cwd=stage, env=npm_env, check=True, timeout=300)
            subprocess.run(['npm', 'ci', '--offline', '--ignore-scripts', '--no-audit', '--no-fund', '--omit=dev', '--registry=' + registry],
                           cwd=stage, env=npm_env, check=True, timeout=600)
            entry = stage / 'node_modules' / tool['package'] / tool['entry']
            if not entry.is_file():
                raise ValueError(name + ' package entry missing')
            (stage / '.omarchy-program').write_text(fingerprint + '\n')
            stage.rename(prefix)
    register(home, name, version, prefix, 'node_modules/' + tool['package'] + '/' + tool['entry'], env)


def failure_reason(error):
    if isinstance(error, subprocess.CalledProcessError):
        # All commands here are installer-owned argv, never inherited user hooks.
        # Include the mise backend/version spec while avoiding large npm lists.
        count = 5 if Path(error.cmd[0]).name == 'mise' else 3
        return ' '.join(map(str, error.cmd[:count])) + ' exited ' + str(error.returncode)
    return str(error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', action='append', default=[], help='Install only this named program (repeatable)')
    args = parser.parse_args()
    home = Path.home()
    mirror = os.environ.get('MIRROR', 'global')
    if mirror not in ('cn', 'global'):
        raise ValueError('resolve MIRROR before installing programs')
    manifest = json.loads((ROOT / 'packages/tool-programs/manifest.json').read_text())
    known = {t['name'] for t in manifest['tools'] + manifest['npm_tools']}
    if set(args.only) - known:
        parser.error('unknown program: ' + ', '.join(sorted(set(args.only) - known)))
    state = home / '.local/state/omarchy-alarm'
    cache = home / '.cache/omarchy-alarm/programs'
    state.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    results = []
    with tempfile.TemporaryDirectory(prefix='isolated-', dir=cache) as temporary:
        env = isolated_env(home, Path(temporary))
        for tool in manifest['tools']:
            if args.only and tool['name'] not in args.only:
                continue
            if mirror == 'cn' and tool.get('cn_skip'):
                result = 'SKIPPED (CN policy) ' + tool['name'] + ': ' + tool['cn_skip']
                results.append(result)
                print(result, flush=True)
                continue
            try:
                if tool['name'] != 'mise' and not (home / '.local/bin/mise').is_file():
                    raise RuntimeError('mise unavailable; rerun installer after fixing its download')
                install_one(tool, home, cache, mirror, env)
                result = 'OK ' + tool['name'] + ' ' + tool['version']
            except Exception as error:
                result = 'FAILED (nonfatal) ' + tool['name'] + ': ' + failure_reason(error)
            results.append(result)
            print(result, flush=True)
        for tool in manifest['npm_tools']:
            if args.only and tool['name'] not in args.only:
                continue
            try:
                if not (home / '.local/bin/mise').is_file():
                    raise RuntimeError('mise unavailable; rerun installer after fixing its download')
                install_npm(tool, home, mirror, env)
                results.append('OK ' + tool['name'] + ' ' + tool['version'])
            except Exception as error:
                results.append('FAILED (nonfatal) ' + tool['name'] + ': ' + failure_reason(error))
            print(results[-1], flush=True)
    report = state / 'tool-programs.txt'
    report.write_text('mirror=' + mirror + '\n' + '\n'.join(results) + '\n')
    print('Program installation report: ' + str(report), flush=True)
    if any(line.startswith('FAILED') for line in results):
        print('WARNING: Some optional programs failed. Desktop installation continues; rerun to retry.', flush=True)


if __name__ == '__main__':
    main()
