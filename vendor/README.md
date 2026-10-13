# Vendored install inputs

Omarchy v4.0.4, commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`,
from https://github.com/basecamp/omarchy (MIT; see OMARCHY-LICENSE).
The four numbered parts concatenate into a gzip tar of its shallow `.git`
directory. This retains exact upstream objects, tags and shallow boundary;
`git reset --hard v4.0.4` reconstructs the checkout without a network fetch.
The 119 MiB archive includes upstream theme wallpapers; parts stay below
GitHub's per-file limit. Only objects, refs, packed-refs, shallow, HEAD and remote config are included.
Clone reflogs, hooks, index and local tar ownership metadata are excluded.
No credentials or user configuration are included.

Reproduce from a fresh shallow clone:

```bash
git clone --depth 1 --branch v4.0.4 https://github.com/basecamp/omarchy.git upstream
tar --owner=0 --group=0 -czf omarchy.git.tar.gz -C upstream \
  .git/objects .git/refs .git/packed-refs .git/shallow .git/HEAD .git/config
split -b 32M -d omarchy.git.tar.gz omarchy-v4.0.4.git.tar.gz.part-
sha256sum omarchy-v4.0.4.git.tar.gz.part-* > SHA256SUMS
```

The public ALARM Build System key was retrieved from keyserver.ubuntu.com
and independently checked against the installer's existing fingerprint
`68B3537F39A313B3E574D06777193F152BDBE6A6`. Installation imports this local
key; a keyserver is no longer required. Rootfs MD5 checks transfer integrity,
not publisher authenticity; the existing optional detached signature policy
is retained (bad signatures abort; unavailable signatures warn).
