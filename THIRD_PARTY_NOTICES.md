# Third-party notices

## calibre 9.11.0

The production image includes the calibre command-line runtime and its built-in
news recipes. calibre is copyright Kovid Goyal and contributors and is licensed
under the GNU General Public License version 3.

- Project: https://calibre-ebook.com/
- License: https://github.com/kovidgoyal/calibre/blob/v9.11.0/LICENSE
- Binary used by the image:
  https://download.calibre-ebook.com/9.11.0/calibre-9.11.0-x86_64.txz
- Binary SHA-256:
  `9cf6d10ad892a9c179fdc03c4f78105c880de1ba039f35813dd0f1910b4ce3d6`
- Corresponding source:
  https://download.calibre-ebook.com/9.11.0/calibre-9.11.0.tar.xz
- Source SHA-256:
  `50d42e3b32ec5116f6b1df099537f4becaf36bfedecf9f581b743f11d8b6cb36`

The News invokes calibre as a separate process. Project-owned modifications to
the bridge are included in this repository. Built-in recipes are loaded from
the pinned calibre distribution at runtime rather than copied into this
repository.

See [docs/operations/CALIBRE_COMPLIANCE.md](docs/operations/CALIBRE_COMPLIANCE.md)
for exact source-retrieval and release requirements.
