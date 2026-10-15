#!/usr/bin/env python3
"""Operator: prepare checksum-verified, upstream AUR source bundles for Gitee."""
import hashlib,json,pathlib,subprocess,tarfile,tempfile,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=pathlib.Path('/tmp/v029-assets'); OUT.mkdir(exist_ok=True)
manifest=[]
manifest_path=ROOT/'packages/desktop-extras/aur-assets.json'
existing={item['name']: item for item in json.loads(manifest_path.read_text())} if manifest_path.exists() else {}
for recipe in sorted((ROOT/'packages/desktop-extras/aur').glob('*/PKGBUILD')):
    item=existing.get(recipe.parent.name)
    if item and (OUT/item['file']).is_file():
        if hashlib.sha256((OUT/item['file']).read_bytes()).hexdigest() != item['integrity'].split(':')[1]:
            raise ValueError('Existing asset checksum mismatch: '+item['file'])
        manifest.append(item)
        print('Verified existing',item['file'],flush=True)
        continue
    # Vendored and reviewed recipes only. Source declarations expand in bash;
    # no prepare/build/package functions are executed on the operator machine.
    script='source "$1"; printf "%s\\0" "$pkgver"; for i in "${!source[@]}"; do printf "%s\\0%s\\0" "${source[$i]}" "${sha256sums[$i]:-${sha512sums[$i]}}"; done; for i in "${!source_aarch64[@]}"; do printf "%s\\0%s\\0" "${source_aarch64[$i]}" "${sha256sums_aarch64[$i]}"; done'
    fields=subprocess.check_output(['bash','-c',script,'bash',str(recipe)]).decode().split('\0')[:-1]
    version=fields.pop(0); name=recipe.parent.name
    with tempfile.TemporaryDirectory() as td:
        stage=pathlib.Path(td); sources=[]; hashes=[]
        for url,digest in zip(fields[::2],fields[1::2]):
            if '::' in url: filename,url=url.split('::',1)
            else: filename=urllib.parse.unquote(url.rsplit('/',1)[1])
            if digest=='SKIP': raise ValueError('Unverified source '+url)
            target=stage/filename
            print('Fetch',url,flush=True)
            with urllib.request.urlopen(url,timeout=90) as response: target.write_bytes(response.read())
            algorithm='sha256' if len(digest)==64 else 'sha512'
            if hashlib.new(algorithm,target.read_bytes()).hexdigest()!=digest: raise ValueError('Checksum mismatch '+url)
            sources.append(filename); hashes.append(hashlib.sha256(target.read_bytes()).hexdigest())
        text=recipe.read_text()
        # Later assignment replaces remote source lists. makepkg still checks
        # every local input and runs the original packaging functions.
        text+='\n# Offline, verified source snapshot for Omarchy ARM.\nsource=('+ ' '.join("'"+x+"'" for x in sources)+')\nsource_x86_64=()\nsource_aarch64=()\nsha512sums=()\nsha256sums=('+ ' '.join("'"+x+"'" for x in hashes)+')\nsha256sums_aarch64=()\n'
        (stage/'PKGBUILD').write_text(text)
        filename=f'aur-{name}-{version}-sources.tar.gz'; output=OUT/filename
        with tarfile.open(output,'w:gz') as tar:
            for child in sorted(stage.iterdir()): tar.add(child,arcname=child.name)
        digest=hashlib.sha256(output.read_bytes()).hexdigest()
        manifest.append(dict(name=name,version=version,file=filename,integrity='sha256-hex:'+digest))
        print(digest,filename,flush=True)
(ROOT/'packages/desktop-extras/aur-assets.json').write_text(json.dumps(manifest,indent=2)+'\n')
pathlib.Path('/tmp/v029-evidence/desktop-assets.txt').write_text(''.join(x['integrity'].split(':')[1]+'  '+x['file']+'\n' for x in manifest))
