# Calibre distribution compliance

The News production image contains the unmodified calibre 9.11.0 Linux runtime.
The application invokes `ebook-convert` through a file-based subprocess
contract. calibre and its built-in recipes remain GPLv3 components; The News is
licensed separately under AGPLv3.

## Retrieve the exact corresponding source

Download:

```sh
curl --fail --location --output calibre-9.11.0.tar.xz \
  https://download.calibre-ebook.com/9.11.0/calibre-9.11.0.tar.xz
```

Verify:

```sh
echo "50d42e3b32ec5116f6b1df099537f4becaf36bfedecf9f581b743f11d8b6cb36  calibre-9.11.0.tar.xz" \
  | sha256sum --check --strict
```

The image binary is independently pinned and verified in the Dockerfile. Its
expected SHA-256 is
`9cf6d10ad892a9c179fdc03c4f78105c880de1ba039f35813dd0f1910b4ce3d6`.

## Release requirement

For every publicly distributed The News image containing calibre:

1. Keep `THIRD_PARTY_NOTICES.md` in the image and source release.
2. Publish or mirror the exact source archive above for as long as that image
   is distributed; do not depend on an unversioned `latest` download.
3. Retain calibre's GPLv3 license and recipe copyright notices.
4. Publish the source for any calibre or built-in recipe modifications under
   GPLv3-compatible terms.
5. Update both checksums, URLs, and notices before changing calibre versions.

Publisher content is not part of the software distribution and must never be
included in an image, repository fixture, or source release.
